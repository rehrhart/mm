/*
 * Copyright (c) 2017 Miles Maltbie, Eric B. Decker
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 * See COPYING in the top level directory of this source tree.
 *
 * Contact: Eric B. Decker <cire831@gmail.com>
 *          Miles Maltbie <milesmaltbie@gmail.com>
 */

#include <panic.h>
#include <platform_panic.h>
#include <sd.h>
#include <image_info.h>
#include <image_mgr.h>

#ifndef PANIC_IM
enum {
  __pcode_im = unique(UQ_PANIC_SUBSYS)
};

#define PANIC_IM __pcode_im
#endif

/*
 * Primary data structures:
 *
 * directory cache, in memory copy of the image directory on the SD.
 *
 * image_manager_working_buffer (IMWB).  An SD sized (514) buffer
 * for interacting with the SD.  Used to collect (marshal) incoming
 * data for writing to the SD.
 *
 * Image Manager Control Block:  The imcb collects all reasonable state
 *   information about what the ImageManager is currently doing.
 *
 *   region_start_blk:  where the ImageManager's region starts and end.  Do
 *   region_end_blk     not go outside these bounds.
 *
 *   dir                directory cache, ram copy of IM dir
 *   filling_blk:       When writing a slot, filling_blk is the next block that
 *   filling_limit_blk: will be written.  limit_blk is the limit of the slot
 *                      do not exceed.
 *
 *   filling_slot_p:    pointer to the current slot we are filling.
 *
 *   buf_ptr:           When filling, buf_ptr keeps track of where in the
 *                      IMWB we currently are working.
 *   bytes_remaining:   how much space is remaining before filling the IMWB.
 *   im_state:          current state of the ImageManager
 *
 *
 * *** State Machine Description
 *
 * IDLE                no active activity.  Free for next operation.
 *                     IMWB and CSB are meaningless.
 * FILL_WAITING        filling buffer.  IMWB and CSB active.
 * FILL_REQ_SD         req SD for IMWB flush.
 * FILL_WRITING        writing buffer (IMWB) to SD.
 * FILL_LAST_REQ_SD    req SD for last buffer write.
 * FILL_LAST_WRITE     finishing write of last buffer (partial).
 * FILL_SYNC_REQ_SD    req SD to write directory to finish new image.
 * FILL_SYNC_WRITE     write directory to update image finish.
 * DELETE_SYNC_REQ_SD  req SD for directory flush for delete.
 * DELETE_SYNC_WRITE   Flush directory cache for new empty entry
 * DSA_SYNC_REQ_SD
 * DSA_SYNC_WRITE
 * DSB_SYNC_REQ_SD
 * DSB_SYNC_WRITE
 * EJECT_SYNC_REQ_SD
 * EJECT_SYNC_WRITE
 */

typedef enum {
  IMS_IDLE                      = 0,
  IMS_INIT_REQ_SD,
  IMS_INIT_READ_DIR,
  IMS_INIT_SYNC_WRITE,

  IMS_FILL_WAITING,             /* filling states through FILL_SYNC_WRITE */
  IMS_FILL_REQ_SD,              /* these are grouped together as the      */
  IMS_FILL_WRITING,             /* FILLING meta states                    */

  IMS_FILL_LAST_REQ_SD,         /* flush last buffer */
  IMS_FILL_LAST_WRITE,

  IMS_FILL_SYNC_REQ_SD,         /* sync directory entry */
  IMS_FILL_SYNC_WRITE,

  IMS_DELETE_SYNC_REQ_SD,       /* delete, set to EMPTY */
  IMS_DELETE_SYNC_WRITE,
  IMS_DSA_SYNC_REQ_SD,          /* dir_set_active */
  IMS_DSA_SYNC_WRITE,
  IMS_DSB_SYNC_REQ_SD,          /* dir_set_backup */
  IMS_DSB_SYNC_WRITE,
  IMS_EJECT_SYNC_REQ_SD,        /* dir_eject_active */
  IMS_EJECT_SYNC_WRITE,
  IMS_MAX
} im_state_t;


/*
 * filling_slot_p and buf_ptr will be NULL when not in a FILLING meta state
 * will be valid while in a FILLING meta state
 *
 * IM is parameterized to make sure that the completion signalling goes to
 * the right place and only the right place (duh).  cid becomes valid on the
 * transition from IMS_IDLE to any other state.  It is meaningless if im_state
 * is IMS_IDLE.  We don't use an inactive value for cid.
 */
typedef struct {
  uint32_t region_start_blk;            /* start/end region limits from  */
  uint32_t region_end_blk;              /* file system                   */

  image_dir_t dir;                      /* directory cache */

  uint32_t filling_blk;                 /* filling, next block to write  */
  uint32_t filling_limit_blk;           /* filling, limit of the slot    */

  image_dir_slot_t *filling_slot_p;     /* filling, pnt to slot being filled */

  uint8_t  *buf_ptr;                    /* filling, pntr into IMWB       */
  uint16_t  bytes_remaining;            /* filling, bytes left in IMWB   */

  im_state_t im_state;                  /* current state */
  uint8_t    cid;                       /* client id */
} imcb_t;                               /* ImageManager Control Block (imcb) */


module ImageManagerP {
  provides {
    interface ImageManager     as IM[uint8_t cid];
    interface ImageManagerData as IMData;
    interface Boot             as Booted;   /* outBoot */
  }
  uses {
    interface Boot;                     /* inBoot */
    interface FileSystem   as FS;
    interface Resource as SDResource;   /* SD we are managing */
    interface Checksum;
    interface SDread;
    interface SDwrite;
    interface SDraw;                    /* other SD aux */;
    interface Platform;
    interface Panic;
  }
}
implementation {
  /*
   * IMWB: ImageManager Working Buffer, this buffer is used
   * to accumulate incoming bytes when writing an image to a slot.
   *
   * The IMWB is aligned to allow quad word aligned access, ie chk_zero.
   */
  uint8_t     im_wrk_buf[SD_BLOCKSIZE] __attribute__((aligned(4)));

  /*
   * control cells, imcb, ImageManager Control Block
   */
  imcb_t imcb;
  bool   do_erase, erase_panic;

  void im_panic(uint8_t where, parg_t p0, parg_t p1) {
    call Panic.panic(PANIC_IM, where, p0, p1, 0, 0);
  }

  bool cmp_ver_id(image_ver_t *ver0p, image_ver_t *ver1p) {
    uint8_t *s, *d;

    s = (void *) ver0p;
    d = (void *) ver1p;
    if (*s++ != *d++) return FALSE;
    if (*s++ != *d++) return FALSE;
    if (*s++ != *d++) return FALSE;
    if (*s++ != *d++) return FALSE;
    return TRUE;
  }

  /*
   * validate_slot:
   *
   * o mark working slot (fsp) to VALID, we are done with it
   * o update working control variables (no longer filling)
   * o update dir checksum
   *
   * the working control variables, fsp and buf_ptr need to be
   * set NULL anytime we are NOT filling.
   */
  void validate_slot() {
    image_dir_t *dir;

    imcb.filling_slot_p->slot_state = SLOT_VALID;
    imcb.filling_slot_p = NULL;         /* not filling anymore */
    imcb.buf_ptr = NULL;                /* not filling anymore */

    dir = &imcb.dir;
    dir->chksum = 0;
    dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));
  }

  /*
   * verify that the current state of Image Manager control
   * cells are reasonable.
   *
   * If not, panic.
   *
   * buf_ptr NULL or within bounds
   */
  void verify_IM() {
    uint32_t checksum;
    image_dir_t *dir;
    image_dir_slot_t *slot_p;
    parg_t panic_val;
    uint32_t slot_start, slot_end;
    int i;
    int active_count;
    int backup_count;
    bool fsp_found;
    bool bail;

    bail = FALSE;
    panic_val = 0;
    slot_start = slot_end = 0;          /* shut compiler up */

    do {

      /*
       * validate control structures
       *
       * 1) check IM state
       * 2) check region bounds
       * 3) directory scan
       *    . signature
       *    . checksum
       *    . entry state
       *    . start_sec valid for slot and within bounds
       *    . find filling_slot_p if any
       *    . count active and backup if any
       * 4) check for correct number of active and backups
       * 5) If Filling
       *    . check filling_slot_p reasonable (see dir scan)
       *    . buf_ptr, bytes_remaining
       *    . filling_blk, filling_limit_blk point into valid slot
       * 6) If not filling
       *    fsp_found (should be FALSE)
       *    buf_ptr and filling_slot_p should be NULL
       */

      /* Check IM state within bounds */
      if (imcb.im_state < IMS_IDLE ||
          imcb.im_state >= IMS_MAX) {
        panic_val = 1;
        break;
      }

      /* region start / end block check */
      if (imcb.region_start_blk != call FS.area_start(FS_LOC_IMAGE) ||
          imcb.region_end_blk != call FS.area_end(FS_LOC_IMAGE)) {
        panic_val = 2;
        break;
      }

      /*
       * do directory checks first.
       */
      dir = &imcb.dir;

      /* Check the directory signatures */
      if (dir->dir_sig != IMAGE_DIR_SIG ||
          dir->dir_sig_a != IMAGE_DIR_SIG) {
        panic_val = 3;
        break;
      }

      /* Check the checksum, should return 0 if dir is valid */
      checksum = call Checksum.sum32_aligned((void *) dir, sizeof(*dir));
      if (checksum) {
        panic_val = 4;
        break;
      }

      fsp_found = FALSE;
      active_count = 0;
      backup_count = 0;
      for (i = 0; i < IMAGE_DIR_SLOTS; i++) {
        /*
         * Check slot state
         * Check FSP Match
         * Check start sec
         */
        slot_p = &imcb.dir.slots[i];
        if (slot_p->slot_state < SLOT_EMPTY ||
            slot_p->slot_state >= SLOT_MAX) {
          panic_val = 5;
          bail = TRUE;
          break;
        }
        if (slot_p->slot_state == SLOT_ACTIVE)
          active_count++;
        if (slot_p->slot_state == SLOT_BACKUP)
          backup_count++;

        /* check for filling_slot_p presence */
        if (slot_p == imcb.filling_slot_p) {
          fsp_found = TRUE;
          if (slot_p->slot_state != SLOT_FILLING) {
            panic_val = 6;
            bail = TRUE;
            break;
          }
          slot_start = slot_p->start_sec;
          slot_end   = slot_p->start_sec + IMAGE_SIZE - 1;
        }
        if (slot_p->start_sec != (imcb.region_start_blk + ((IMAGE_SIZE_SECTORS * i) + 1))) {
          panic_val = 7;
          bail = TRUE;
          break;
        }
        if (slot_p->start_sec < imcb.region_start_blk ||
            slot_p->start_sec > imcb.region_end_blk) {
          panic_val = 8;
          bail = TRUE;
          break;
        }
      }
      if (bail)
        break;

      /*
       * directory scan complete
       *
       * how many active/backups found
       * if we have a backup we had better have an active too.
       */
      if (active_count > 1 || backup_count > 1) {
        panic_val = 9;
        break;
      }
      if (backup_count && !active_count) {
        panic_val = 14;
        break;
      }

      if (imcb.im_state >=  IMS_FILL_WAITING &&
          imcb.im_state <=  IMS_FILL_WRITING) {
        /*
         * In a FILLING state, do FILLING checks
         */
        if (!fsp_found) {
          panic_val = 10;
          break;
        }

        /*
         * Check filling_blk, filling_limit_blk
         * the slot block is defined by filling_slot_p->start_sec
         * and filling_limit_blk is calculated from start_sec.
         *
         * slot_start and end are set above and are the limits we
         * check against.
         */

        if (imcb.filling_blk < slot_start ||
            imcb.filling_blk > slot_end   ||
            imcb.filling_limit_blk < slot_start ||
            imcb.filling_limit_blk > slot_end ||
            imcb.filling_blk > imcb.filling_limit_blk) {
          panic_val = 11;
          break;
        }

        /*
         * filling so buf_ptr must be either within bounds of the
         * IMWB or just beyond (im_wrk_buf[SD_BLOCKSIZE])
         */
        if (imcb.buf_ptr < im_wrk_buf ||
            imcb.buf_ptr > &im_wrk_buf[SD_BLOCKSIZE]) {
          panic_val = 12;
          break;
        }

      } else {
        /*
         * not filling, verify reasonableness
         *
         * fsp_found should be FALSE
         * buf_ptr and filling_slot_p should both be NULL
         */
        if (fsp_found || imcb.buf_ptr || imcb.filling_slot_p) {
          panic_val = 13;
          break;
        }
      }
    } while (0);
    if (panic_val)
      im_panic(1, panic_val, imcb.im_state);
  }


  void write_dir_cache() {
    error_t err;

    verify_IM();
    if ((err = call SDwrite.write(imcb.region_start_blk, (void *) &imcb.dir))) {
      im_panic(2, err, 0);
      return;
    }
  }


  void write_slot_blk() {
    error_t err;

    if (imcb.filling_blk > imcb.filling_limit_blk)
      im_panic(3, imcb.filling_blk, imcb.filling_limit_blk);
    err = call SDwrite.write(imcb.filling_blk, im_wrk_buf);
    if (err)
      im_panic(4, err, 0);
  }


  /*
   * get_active_backup: find the active and/or backup dir slot if any
   *
   * input:  a, b       ptrs (pass by ref) to dir_slot ptrs
   *                    NULL if we aren't looking for said slot
   * output: *a, *b     updated to point at active/backup slots respectively.
   * return: none
   *
   * assumes that a reasonable call of verify_IM() has occured prior to calling
   * get_active_backup.
   */
  void get_active_backup(image_dir_slot_t **a, image_dir_slot_t **b) {
    image_dir_slot_t *sp;
    int i;

    if (a) *a = NULL;
    if (b) *b = NULL;
    for (i = 0; i < IMAGE_DIR_SLOTS; i++) {
      sp = &imcb.dir.slots[i];
      if (a && sp->slot_state == SLOT_ACTIVE)
        *a = sp;
      if (b && sp->slot_state == SLOT_BACKUP)
        *b = sp;
    }
  }


  void *memcpy_ua(void *dest, const void *src, size_t n) {
    bool on;
    void *p;

    on = call Platform.set_unaligned_traps(FALSE);
    p = memcpy(dest, src, n);
    call Platform.set_unaligned_traps(on);
    return p;
  }


  event void Boot.booted() {
    error_t err;

#ifdef IM_ERASE_ENABLE
    /*
     * FS.erase is split phase and will grab the SD,  We will wait on the
     * erase when we request.  The FS/erase will complete and then we
     * will get the grant.
     */
    nop();                              /* BRK */
    if (do_erase) {
      do_erase = 0;
      if (erase_panic)
        call FS.erase(FS_LOC_PANIC);
      else
        call FS.erase(FS_LOC_IMAGE);
    }
#endif

    imcb.region_start_blk = call FS.area_start(FS_LOC_IMAGE);
    imcb.region_end_blk   = call FS.area_end(FS_LOC_IMAGE);

    /*
     * first block of the area is reserved for the ImageManager
     * directory.
     */
    if ( ! imcb.region_start_blk)
      im_panic(5, 0, 0);
    imcb.im_state = IMS_INIT_REQ_SD;
    if ((err = call SDResource.request()))
      im_panic(6, err, 0);
  }


  image_dir_slot_t *dir_find_ver(image_ver_t *verp) {
    image_dir_t *dir;
    image_dir_slot_t *sp;
    int i;

    dir = &imcb.dir;
    verify_IM();
    for (i = 0; i < IMAGE_DIR_SLOTS; i++) {
      sp = &dir->slots[i];
      if ((sp->slot_state >= SLOT_VALID) &&
          cmp_ver_id(&(sp->ver_id), verp))
        return sp;
    }
    return NULL;
  }


  /***************************************************************************
   * ImageManageData access
   * not parameterized.
   *
   **************************************************************************/

  /*
   * Check_fit: Verifies that request length will fit image slot.
   *
   * input:  len        length of image being pushed to SD
   * output: none
   * return: bool       TRUE.  image fits.
   *                    FALSE, image too big for slot
   */
  command bool IMData.check_fit(uint32_t len) {
    if (len < IMAGE_MIN_SIZE) return FALSE;
    if (len > IMAGE_SIZE)     return FALSE;
    return TRUE;
  }


  /*
   * verEqual: compare two version structs  (EQUAL)
   *
   * input:  ver0       image_ver_t *ver0p, version
   *         ver1       ditto
   * return: bool       TRUE.  versions are not equal
   *                    FALSE, versions are equal
   */
  command bool IMData.verEqual(image_ver_t *ver0p, image_ver_t *ver1p) {
    return cmp_ver_id(ver0p, ver1p);
  }


  command void IMData.setVer(image_ver_t *srcp, image_ver_t *dstp) {
    uint8_t *s, *d;

    s = (void *) srcp;
    d = (void *) dstp;
    *d++ = *s++;
    *d++ = *s++;
    *d++ = *s++;
    *d++ = *s++;
  }


  command uint8_t IMData.slotStateLetter(slot_state_t state) {
    switch (state) {
      case SLOT_EMPTY:          return 'x';
      case SLOT_FILLING:        return 'f';
      case SLOT_VALID:          return 'v';
      case SLOT_BACKUP:         return 'b';
      case SLOT_ACTIVE:         return 'a';
      case SLOT_EJECTED:        return 'e';
      default:                  return '?';
    }
  }


  /*
   * dir_get_active: find current active if any
   *
   * input:  none
   * return: ptr        slot entry for current active.
   *                    NULL if no active image
   */
  command image_dir_slot_t *IMData.dir_get_active() {
    image_dir_slot_t *ap;

    verify_IM();
    get_active_backup(&ap, NULL);
    return ap;
  }


  /*
   * dir_get_backup: find current backup if any
   *
   * input:  none
   * return: ptr        slot entry for current active.
   *                    NULL if no active image
   */
  command image_dir_slot_t *IMData.dir_get_backup() {
    image_dir_slot_t *bkp;

    verify_IM();
    get_active_backup(NULL, &bkp);
    return bkp;
  }


  /*
   * dir_get_dir: Returns a pointer to the dir slot indexed by idx
   *
   * input:  idx
   * return: image_dir_slot_t * slot found
   */
  command image_dir_slot_t *IMData.dir_get_dir(uint8_t idx) {
    verify_IM();
    if (idx >= IMAGE_DIR_SLOTS)
      return NULL;
    return &imcb.dir.slots[idx];
  }


  /*
   * dir_find_ver: Returns a pointer to the slot for given image version.
   *
   * input:  ver_id
   * return: dir_find_ver(ver_id)
   */
  command image_dir_slot_t *IMData.dir_find_ver(image_ver_t *ver_id) {
    return dir_find_ver(ver_id);
  }


  /*
   * dir_coherent: indicates if the Dir on disk is coherent
   *
   * returns TRUE if in memory cache reflects the state of the on SD
   * directory.  No updates are pending.
   */
  command bool IMData.dir_coherent() {
    return imcb.im_state == IMS_IDLE;
  }


  /***************************************************************************
   * ImageManager access
   * parameterized.  Uses client id (cid).
   *
   **************************************************************************/

  /*
   * Alloc: Allocate an empty slot for an incoming image
   *
   * input : ver_id     name of the image
   * return: error_t    SUCCESS,  all good.
   *                    ENOMEM,   no slots available
   *                    EALREADY, image is already in the directory
   *
   * on SUCCESS, the ImageMgr will be ready to accept the data
   * stream that is the image.
   *
   * Only one valid image with the name ver_id is allowed.
   */
  command error_t IM.alloc[uint8_t cid](image_ver_t *verp) {
    image_dir_t *dir;
    image_dir_slot_t *sp, *ep;          /* slot ptr, empty ptr */
    imcb_t *imcp;
    int i;

    imcp = &imcb;
    if (imcp->im_state != IMS_IDLE)
        im_panic(7, imcp->im_state, 0);

    ep = NULL;
    dir = &imcb.dir;
    verify_IM();

    /*
     * scan the directory looking for the ver_id (only if VALID or above).
     * Also find the first empty slot.
     */
    for (i = 0; i < IMAGE_DIR_SLOTS; i++) {
      sp = &dir->slots[i];
      if ((sp->slot_state >= SLOT_VALID) &&
          cmp_ver_id(&(sp->ver_id), verp))
        return EALREADY;
      if (!ep && sp->slot_state == SLOT_EMPTY)
        ep = sp;
    }
    if (!ep)
      return ENOMEM;
    ep->slot_state = SLOT_FILLING;
    call IMData.setVer(verp, &ep->ver_id);
    dir->chksum = 0;
    dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));

    imcp->filling_blk = ep->start_sec;
    imcp->filling_limit_blk = ep->start_sec + IMAGE_SIZE_SECTORS - 1;
    imcp->filling_slot_p = ep;

    imcp->buf_ptr = &im_wrk_buf[0];
    imcp->bytes_remaining = SD_BLOCKSIZE;
    imcp->cid = cid;
    imcp->im_state = IMS_FILL_WAITING;
    return SUCCESS;
  }


  /*
   * Alloc_abort: abort a current Alloc.
   *
   * input:  none
   * output: none
   * return: error_t    SUCCESS,  all good.  slot marked empty
   *                    FAIL,     no alloc in progress (panic)
   *
   * alloc_abort can only be called in IMS_FILL_WAITING.  This
   * means if IM.write ever returns non-zero, one MUST wait
   * for a IM.write_complete before calling alloc_abort.
   */
  command error_t IM.alloc_abort[uint8_t cid]() {
    image_dir_t *dir;

    if (imcb.im_state != IMS_FILL_WAITING || imcb.cid != cid)
      im_panic(8, imcb.im_state, 0);

    verify_IM();

    imcb.filling_slot_p->slot_state = SLOT_EMPTY;
    imcb.buf_ptr = NULL;
    imcb.filling_slot_p = NULL;
    imcb.im_state = IMS_IDLE;
    imcb.cid      = -1;
    dir = &imcb.dir;
    dir->chksum = 0;
    dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));
    return SUCCESS;
  }


  /*
   * Delete: Sets the state of an image  to "empty", marking the slot  available for another image.
   *
   * input:  ver_id
   * return: error_t
   *
   * we do not allow the ACTIVE to be deleted.  One needs to activate a
   * different image.  Then one can delete this one.  ACTIVE always
   * indicates what is loaded into the NIB.  This is normal operation.
   *
   * will launch a Dir sync, completion signaled via delete_complete
   */
  command error_t IM.delete[uint8_t cid](image_ver_t *verp) {
    image_dir_t *dir;
    image_dir_slot_t *sp;
    error_t err;

    if (imcb.im_state != IMS_IDLE)
      im_panic(10, imcb.im_state, 0);

    /* dir_find_ver does the call to verify_IM */
    sp  = dir_find_ver(verp);
    if (!sp)
      return EINVAL;                      /* not found */

    if (sp->slot_state == SLOT_ACTIVE)
      return EINVAL;

    sp->slot_state = SLOT_EMPTY;
    dir = &imcb.dir;
    dir->chksum = 0;
    dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));
    imcb.im_state = IMS_DELETE_SYNC_REQ_SD;
    imcb.cid = cid;
    err = call SDResource.request();
    if (err)
      im_panic(12, err, 0);

    return SUCCESS;
  }


  /*
   * dir_set_active: marks a VALID or BACKUP image as ACTIVE.
   *
   * input: ver_id
   * output: none
   * return: error_t
   *
   * One can set to ACTIVE a BACKUP or a VALID.  If the BACKUP is being
   * set to ACTIVE, then the current ACTIVE gets downgraded to VALID.  This
   * is like EJECT but we keep the potentially good image around.  It is
   * technically not a failure.
   *
   * start a cache flush
   */
  command error_t IM.dir_set_active[uint8_t cid](image_ver_t *verp) {
    error_t err;
    image_dir_t *dir;
    image_dir_slot_t *newp, *active, *backup;

    if (imcb.im_state != IMS_IDLE)
      im_panic(13, imcb.im_state, 0);

    /* dir_find_ver does the call to verify_IM */
    newp = dir_find_ver(verp);

    /*
     * the image being proposed for the new active needs to exist
     * and must be in the VALID state.
     */
    if (!newp)
      return FAIL;

    switch (newp->slot_state) {
      default:
        return FAIL;

      case SLOT_ACTIVE:
        return EALREADY;

      case SLOT_VALID:
      case SLOT_BACKUP:
        break;
    }

    get_active_backup(&active, &backup);
    if (newp->slot_state == SLOT_BACKUP) {
      /*
       * activating the previous BACKUP, make the current ACTIVE
       * got to VALID.  We don't set it to BACKUP because that doesn't
       * make sense to swap like that.
       */
      active->slot_state = SLOT_VALID;
    } else {
      /* If we have an active, switch it to backup */
      if (active)
        active->slot_state = SLOT_BACKUP;
      if (backup)
        backup->slot_state = SLOT_VALID;
    }

    newp->slot_state = SLOT_ACTIVE;
    dir = &imcb.dir;
    dir->chksum = 0;
    dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));

    /*
     * directory has been updated.  Fire up a dir flush
     */
    imcb.im_state = IMS_DSA_SYNC_REQ_SD;
    imcb.cid = cid;
    if ((err = call SDResource.request()))
      im_panic(15, err, 0);
    return SUCCESS;
  }


  /*
   * dir_set_backup: set the specified image to BACKUP
   *
   * Image has to be present and VALID.  Will not change any other state
   * to BACKUP.
   *
   * If there is currently a BACKUP it will be changed to VALID.
   *
   * Forces a dir sync.
   */
  command error_t IM.dir_set_backup[uint8_t cid](image_ver_t *verp) {
    error_t err;
    image_dir_t *dir;
    image_dir_slot_t *newp, *active, *backup;

    if (imcb.im_state != IMS_IDLE)
      im_panic(16, imcb.im_state, 0);

    /* dir_find_ver does the call to verify_IM */
    newp = dir_find_ver(verp);
    if (!newp || newp->slot_state != SLOT_VALID)                          /* not found */
      return EINVAL;

    /*
     * setting backup, make sure we have an active
     * It doesn't make sense to have a BACKUP and no ACTIVE
     * yell and scream.  This is a sanity check.
     */
    get_active_backup(&active, &backup);

    /*
     * the image requested to set as  backup needs to exist
     * and must be in the VALID state.
     */
    if (!active)                        /* state of machine not right. */
      return FAIL;

    if (backup)
      backup->slot_state = SLOT_VALID;
    newp->slot_state = SLOT_BACKUP;
    dir = &imcb.dir;
    dir->chksum = 0;
    dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));

    /*
     * directory has been updated.  Fire up a dir flush
     */
    imcb.im_state = IMS_DSB_SYNC_REQ_SD;
    imcb.cid = cid;
    if ((err = call SDResource.request()))
      im_panic(18, err, 0);

    return SUCCESS;
  }


  /*
   * dir_eject_active: throw the current active out.
   *
   * there needs to be an active to throw out.  Move it to
   * EJECTED state.  If there is also a BACKUP then move that
   * to the ACTIVE state.
   *
   * Sync the directory.
   */
  command error_t IM.dir_eject_active[uint8_t cid]() {
    error_t err;
    image_dir_t *dir;
    image_dir_slot_t *active, *backup;

    if (imcb.im_state != IMS_IDLE)
      im_panic(19, imcb.im_state, 0);

    verify_IM();
    get_active_backup(&active, &backup);

    /*
     * weird state, why are we ejecting a NIB when there isn't
     * an ACTIVE.  Shouldn't be here.  Also how do we recover?
     *
     * FIXME
     */
    if (!active)
      im_panic(20, (parg_t) active, (parg_t) backup);

    active->slot_state = SLOT_EJECTED;
    if (backup)
      backup->slot_state = SLOT_ACTIVE;

    dir = &imcb.dir;
    dir->chksum = 0;
    dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));

    /*
     * directory has been updated.  Fire up a dir flush
     */
    imcb.im_state = IMS_EJECT_SYNC_REQ_SD;
    imcb.cid = cid;
    if ((err = call SDResource.request()))
      im_panic(21, err, 0);
    return SUCCESS;
  }


  /*
   * finish: an image is finished.
   *
   * o make sure any remaining data is written to the slot from the working buffer.
   * o Mark image as valid.
   * o sync the directory.
   *
   * input:  none
   * output: none
   * return: error_t
   */

  command error_t IM.finish[uint8_t cid]() {
    error_t err;

    nop();
    nop();                              /* BRK */
    if (imcb.im_state != IMS_FILL_WAITING)
      im_panic(22, imcb.im_state, 0);

    verify_IM();

    /*
     * we need to enforce the minimum size constraint.  The minimum
     * is the vector table + image_info.
     *
     * This only applies if we are on the first sector.  Otherwise we have
     * of course written enough data
     */
    if (imcb.filling_blk == imcb.filling_slot_p->start_sec) {
      /* on first sector of the slot.  If we are below IMAGE_MIN_SIZE
       * blow it up
       */
      if (SD_BLOCKSIZE - imcb.bytes_remaining < IMAGE_MIN_SIZE)
        im_panic(23, SD_BLOCKSIZE - imcb.bytes_remaining, 0);
    }

    /*
     * if there are no bytes in the IMWB then immediately transition
     * to writing/syncing the dir cache to the directory.
     */
    if (imcb.bytes_remaining == SD_BLOCKSIZE) {
      imcb.im_state = IMS_FILL_SYNC_REQ_SD;
      validate_slot();
    }
    else imcb.im_state = IMS_FILL_LAST_REQ_SD;

    err = call SDResource.request();
    if (err)
      im_panic(23, err, 0);

    return SUCCESS;
  }


  /*
   * Write: write a buffer of data to the allocated slot
   *
   * input:  buff ptr   pointer to data being written
   *         len        how much data needs to be written.
   * output: err        SUCCESS, no issues
   *                    ESIZE, write exceeds limits of slot
   *                    EINVAL, wrong state
   *
   * return: remainder  how many bytes still need to be written
   *
   * ImageManager will move the bytes from buff into the working buffer
   * (wbuff).  It will stop when wbuff is full.  It will return the number
   * of bytes that haven't been copied.  If it returns 0, the incoming
   * buffer has been completely consumed.  This indicates that the incoming
   * buffer can be released by the caller and used for other activities.
   *
   * When there is a remainder, the remaining bytes in the incoming buffer
   * still need be written.  But this can not happen until after wbuff has
   * been written to disk.  The caller must wait for the write_complete
   * signal.  It can then resend the remaining bytes using another call to
   * ImageManager.write(...).
   */
  command uint32_t IM.write[uint8_t cid](uint8_t *buf, uint32_t len) {
    uint32_t copy_len;
    uint32_t bytes_left;
    error_t  err;

    if (!len)                           /* nothing to do? */
      return 0;                         /* we consumed nothing, go figure */
    if (imcb.im_state != IMS_FILL_WAITING)
      im_panic(24, imcb.im_state, 0);

    verify_IM();

    if (len <= imcb.bytes_remaining) {
      copy_len = len;
      imcb.bytes_remaining -= len;
      bytes_left = 0;
    } else {
      copy_len = imcb.bytes_remaining;
      imcb.bytes_remaining = 0;
      bytes_left = len - copy_len;
    }

    memcpy_ua(imcb.buf_ptr, buf, copy_len);
    imcb.buf_ptr += copy_len;
    if (bytes_left) {
      imcb.im_state = IMS_FILL_REQ_SD;
      err = call SDResource.request();
      if (err)
        im_panic(25, err, 0);
    }
    return bytes_left;
  }


  event void SDResource.granted() {
    error_t err;

    nop();
    nop();                              /* BRK */
    switch(imcb.im_state) {
      default:
        im_panic(26, imcb.im_state, 0);
        return;

      case IMS_INIT_REQ_SD:
        imcb.im_state = IMS_INIT_READ_DIR;
        err = call SDread.read(imcb.region_start_blk, im_wrk_buf);
        if (err) {
          im_panic(27, err, 0);
          return;
        }
        return;

      case IMS_FILL_REQ_SD:
        imcb.im_state = IMS_FILL_WRITING;
        write_slot_blk();
        return;

      case IMS_FILL_LAST_REQ_SD:
        imcb.im_state = IMS_FILL_LAST_WRITE;
        write_slot_blk();
        return;

      case IMS_FILL_SYNC_REQ_SD:
        imcb.im_state = IMS_FILL_SYNC_WRITE;
        write_dir_cache();
        return;

      case IMS_DELETE_SYNC_REQ_SD:
        imcb.im_state = IMS_DELETE_SYNC_WRITE;
        write_dir_cache();
        return;

      case IMS_DSA_SYNC_REQ_SD:
        imcb.im_state = IMS_DSA_SYNC_WRITE;
        write_dir_cache();
        return;

      case IMS_DSB_SYNC_REQ_SD:
        imcb.im_state = IMS_DSB_SYNC_WRITE;
        write_dir_cache();
        return;

      case IMS_EJECT_SYNC_REQ_SD:
        imcb.im_state = IMS_EJECT_SYNC_WRITE;
        write_dir_cache();
        return;
    }
  }


  event void SDread.readDone(uint32_t blk_id, uint8_t *read_buf, error_t err) {
    image_dir_t *dir;
    int i;

    nop();
    nop();                              /* BRK */
    dir = &imcb.dir;
    if (imcb.im_state != IMS_INIT_READ_DIR)
      im_panic(28, imcb.im_state, err);

    /*
     * we just completed reading the directory sector.
     *
     * check for all zeroes.  If so we need to initialize the
     * directory to empty with proper start_sec fields.
     */
    if (call SDraw.chk_zero(im_wrk_buf)) {
      dir->imgr_id[0] = 'I';
      dir->imgr_id[1] = 'M';
      dir->imgr_id[2] = 'G';
      dir->imgr_id[3] = 'R';
      dir->dir_sig   = IMAGE_DIR_SIG;
      dir->dir_sig_a = IMAGE_DIR_SIG;
      for (i = 0; i < IMAGE_DIR_SLOTS; i++)
        dir->slots[i].start_sec =
          imcb.region_start_blk + ((IMAGE_SIZE_SECTORS * i) + 1);

      dir->chksum = 0;
      dir->chksum = 0 - call Checksum.sum32_aligned((void *) dir, sizeof(*dir));
      imcb.im_state = IMS_INIT_SYNC_WRITE;
      write_dir_cache();
      return;
    }

    /*
     * non-zero directory sectory, read in the directory and
     * check for validity.
     */
    memcpy_ua(dir, im_wrk_buf, sizeof(*dir));
    verify_IM();                        /* verify the directory */

    nop();                              /* BRK */
    imcb.im_state = IMS_IDLE;
    imcb.cid      = -1;
    signal Booted.booted();
    call SDResource.release();
    return;
  }


  event void SDwrite.writeDone(uint32_t blk, uint8_t *buf, error_t error) {
    uint8_t pcid;

    nop();
    nop();                              /* BRK */
    switch(imcb.im_state) {
      default:
        im_panic(29, imcb.im_state, 0);
        return;

      case IMS_INIT_SYNC_WRITE:
        imcb.cid      = -1;
        imcb.im_state = IMS_IDLE;
        signal Booted.booted();
        call SDResource.release();
        return;

      case IMS_FILL_WRITING:
        imcb.im_state = IMS_FILL_WAITING;
        imcb.filling_blk++;
        imcb.buf_ptr = &im_wrk_buf[0];
        imcb.bytes_remaining = SD_BLOCKSIZE;
        signal IM.write_continue[imcb.cid]();
        call SDResource.release();
        return;

      case IMS_FILL_LAST_WRITE:
        imcb.im_state = IMS_FILL_SYNC_WRITE;
        validate_slot();
        write_dir_cache();
        return;

      case IMS_FILL_SYNC_WRITE:
        pcid = imcb.cid;
        imcb.cid = -1;
        imcb.im_state = IMS_IDLE;
        signal IM.finish_complete[pcid]();
        call SDResource.release();
        return;

      case IMS_DELETE_SYNC_WRITE:
        pcid = imcb.cid;
        imcb.cid = -1;
        imcb.im_state = IMS_IDLE;
        signal IM.delete_complete[pcid]();
        call SDResource.release();
        return;

      case IMS_DSA_SYNC_WRITE:
        nop();                          /* BRK */
        pcid = imcb.cid;
        imcb.cid = -1;
        imcb.im_state = IMS_IDLE;
        signal IM.dir_set_active_complete[pcid]();
        call SDResource.release();
        return;

      case  IMS_DSB_SYNC_WRITE:
        pcid = imcb.cid;
        imcb.cid = -1;
        imcb.im_state = IMS_IDLE;
        signal IM.dir_set_backup_complete[pcid]();
        call SDResource.release();
        return;

      case IMS_EJECT_SYNC_WRITE:
        pcid = imcb.cid;
        imcb.cid = -1;
        imcb.im_state = IMS_IDLE;
        signal IM.dir_eject_active_complete[pcid]();
        call SDResource.release();
        return;
    }
  }

  default event void IM.write_continue[uint8_t cid]() { }
  default event void IM.finish_complete[uint8_t cid]() { }
  default event void IM.delete_complete[uint8_t cid]() { }
  default event void IM.dir_set_active_complete[uint8_t cid]() { }
  default event void IM.dir_set_backup_complete[uint8_t cid]() { }
  default event void IM.dir_eject_active_complete[uint8_t cid]() { }

  event void FS.eraseDone(uint8_t which) { }

  async event void Panic.hook() { }
}
