/*
 * Copyright (c) 2010 - Eric B. Decker, Carl Davis
 * All rights reserved.
 *
 * FileSystem.nc - simple raw area file system based on
 * contiguous blocks of a FAT32 filesystem.
 *
 * Block 0 of the SD is the MBR.  If the filesystem is
 * bootable then most of this block (512 bytes) is code
 * that boot straps the system.  The SD card we are using
 * is not bootable.  So we lay a record down in the middle
 * of the MBR identified by majik numbers that tells us
 * the absolute block numbers of the data areas.  These
 * areas have been built by special tools that allocate
 * according to FAT rules files that encompass these regions.
 * That way the actual data files can be accessed directly
 * from any system that understands the FAT filesystem.  No
 * special tools are needed.  This greatly eases the accessibility
 * of the resultant data on Winbloz machines (which unfortunately
 * need to be supported for post processing data).
 */

#include "file_system.h"
#include "dblk_loc.h"
#include "panic.h"

/*
 * These macros are used to ConvertFrom_LittleEndian to the native
 * format of the machine this code is running on.  The Data Block
 * Locator (the block of information in the MBR that tells us where
 * our data areas live) is written in little endian order because most
 * machines in existence (thanks Intel) are little endian.
 *
 * The MSP430 is little endian so these macros do nothing.  If a machine
 * is big endian they would have to do byte swapping.
 */

#define CF_LE_16(v) (v)
#define CF_LE_32(v) (v)
#define CT_LE_16(v) (v)
#define CT_LE_32(v) (v)

uint32_t w_t0, w_diff;

#ifdef ENABLE_ERASE
#ifdef ALWAYS_ERASE
bool     do_erase = 1;
#else
bool     do_erase;
#endif
uint32_t erase_start;
uint32_t erase_end;
#endif


typedef enum {
  FSS_IDLE = 0,				/* doing nothing */
  FSS_REQUEST,				/* resource requested */
  FSS_ZERO,				/* reading block zero */
  FSS_START,				/* read first block, chk empty */
  FSS_SCAN,				/* scanning for 1st blank */
} fs_state_t;


module FileSystemP {
  provides {
    interface Init;
    interface Boot as OutBoot;		/* signals OutBoot */
    interface FileSystem as FS;
  }
  uses {
    interface Boot;			/* incoming booted signal */
    interface SDread;
    interface SSWrite as SSW;
    interface Resource as SDResource;
    interface Panic;
  }
}
  
implementation {

  fs_control_t fsc;
  fs_state_t   fs_state;
  uint8_t     *fs_buf;
  uint32_t     lower, cur_blk, upper;


  /*
   * on boot, the data area is zero'd so most of the fsc structure
   * gets zero'd.
   */
  command error_t Init.init() {
    fsc.majik_a     = FSC_MAJIK_A;
    fsc.majik_b     = FSC_MAJIK_B;
    return SUCCESS;
  }


  /*
   * blk_empty
   *
   * check if a Stream storage data block is empty.
   * Currently, an empty (erased SD data block) looks like
   * it is zeroed.  So we look for all data being zero.
   */

  int blk_empty(uint8_t *buf) {
    uint16_t i;
    uint16_t *ptr;

    ptr = (void *) buf;
    for (i = 0; i < SD_BLOCKSIZE/2; i++)
      if (ptr[i])
	return(0);
    return(1);
  }


  /*
   * check_dblk_loc
   *
   * Check the Dblk Locator for validity.
   *
   * First, we look for the magic number in the majik spot
   * Second, we need the checksum to match.  Checksum is computed over
   * the entire dblk_loc structure.
   *
   * i: *dbl	dblk locator structure pointer
   *
   * o: rtn	0  if dblk valid
   *		1  if no dblk found
   *		2  if dblk checksum failed
   *		3  bad value in dblk
   */

  uint16_t check_dblk_loc(dblk_loc_t *dbl) {
    uint16_t *p;
    uint16_t sum, i;

    if (dbl->sig != CT_LE_32(TAG_DBLK_SIG))
      return(1);
    if (dbl->panic_start == 0 || dbl->panic_end == 0 ||
	dbl->config_start == 0 || dbl->config_end == 0 ||
	dbl->dblk_start == 0 || dbl->dblk_end == 0)
      return(3);
    if (dbl->panic_start > dbl->panic_end ||
	dbl->config_start > dbl->config_end ||
	dbl->dblk_start > dbl->dblk_end)
      return(3);
    p = (void *) dbl;
    sum = 0;
    for (i = 0; i < DBLK_LOC_SIZE_SHORTS; i++)
      sum += CF_LE_16(p[i]);
    if (sum)
      return(2);
    return(0);
  }


#define fs_panic(where, arg) do { call Panic.panic(PANIC_MS, where, arg, 0, 0, 0); } while (0)

  void fs_panic_idle(uint8_t where, uint16_t arg) {
    call Panic.panic(PANIC_MS, where, arg, 0, 0, 0);
    fs_state = FSS_IDLE;
  }


  event void Boot.booted() {
    error_t err;

    fs_state = FSS_REQUEST;
    if ((err = call SDResource.request()))
      fs_panic_idle(1, err);
    return;
  }


  event void SDResource.granted() {
    error_t err;

    if (fs_state != FSS_REQUEST) {
      fs_panic_idle(2, fs_state);
      return;
    }
    fs_state = FSS_ZERO;
    fs_buf = call SSW.get_temp_buf();
    if ((err = call SDread.read(0, fs_buf))) {
      fs_panic_idle(3, err);
      return;
    }
    return;
  }


  event void SDread.readDone(uint32_t blk_id, void *read_buf, error_t err) {
    dblk_loc_t *dbl;
    uint8_t    *dp;
    bool        empty;

    dp = fs_buf;
    if (err || dp == NULL || dp != read_buf) {
      call Panic.panic(PANIC_MS, 4, err, (uint16_t) dp, (uint16_t) read_buf, 0);
      return;
    }

    switch(fs_state) {
      default:
	  fs_panic_idle(13, fs_state);
	  return;

      case FSS_ZERO:
	dbl = (void *) ((uint8_t *) dp + DBLK_LOC_OFFSET);
	if ((err = check_dblk_loc(dbl))) {
	  fs_panic_idle(5, err);
	  return;
	}

	fsc.panic_start  = CF_LE_32(dbl->panic_start);
	fsc.panic_end    = CF_LE_32(dbl->panic_end);
	fsc.config_start = CF_LE_32(dbl->config_start);
	fsc.config_end   = CF_LE_32(dbl->config_end);
	fsc.dblk_start   = CF_LE_32(dbl->dblk_start);
	fsc.dblk_end     = CF_LE_32(dbl->dblk_end);

	fs_state = FSS_START;
	if ((err = call SDread.read(fsc.dblk_start, dp))) {
	  fs_panic_idle(6, err);
	  return;
	}
	return;

      case FSS_START:
	if (blk_empty(dp)) {
	  fsc.dblk_nxt = fsc.dblk_start;
	  break;
	}

	lower = fsc.dblk_start;
	upper = fsc.dblk_end;

	cur_blk = (upper - lower)/2 + lower;
	if (cur_blk == lower)
	  cur_blk = lower = upper;

	fs_state = FSS_SCAN;
	if ((err = call SDread.read(cur_blk, dp)))
	  fs_panic_idle(7, err);
	return;

      case FSS_SCAN:
	empty = blk_empty(dp);
	if (empty)
	  upper = cur_blk;
	else
	  lower = cur_blk;

	if (lower >= upper) {
	  /*
	   * we've looked at all the blocks.  Check the state of the last block looked at
	   * if empty we be good.  Otherwise no available storage.
	   */
	  if (empty) {
	    fsc.dblk_nxt = cur_blk;
	    break;
	  }
	  fs_panic_idle(8, (uint16_t) cur_blk);
	  return;
	}

	/*
	 * haven't looked at all the blocks.  try again
	 */
	cur_blk = (upper - lower)/2 + lower;
	if (cur_blk == lower)
	  cur_blk = lower = upper;
	if ((err = call SDread.read(cur_blk, dp)))
	  fs_panic_idle(9, err);
	return;
    }
    fs_state = FSS_IDLE;
    call SDResource.release();
    signal OutBoot.booted();
  }


  command uint32_t FS.area_start(uint8_t which) {
    switch (which) {
      case FS_AREA_PANIC:	return fsc.panic_start;
      case FS_AREA_CONFIG:	return fsc.config_start;
      case FS_AREA_TYPED_DATA:	return fsc.dblk_start;
      default:
	fs_panic(10, which);
	return 0;
    }
  }


  command uint32_t FS.area_end(uint8_t which) {
    switch (which) {
      case FS_AREA_PANIC:	return fsc.panic_end;
      case FS_AREA_CONFIG:	return fsc.config_end;
      case FS_AREA_TYPED_DATA:	return fsc.dblk_end;
      default:
	fs_panic(10, which);
	return 0;
    }
  }


  command uint32_t FS.get_nxt_blk(uint8_t area_type) {
    switch (area_type) {
      case FS_AREA_TYPED_DATA:	return fsc.dblk_nxt;
      default:
	fs_panic(11, area_type);
	return 0;
    }
  }


  command uint32_t FS.adv_nxt_blk(uint8_t area_type) {
    if (area_type != FS_AREA_TYPED_DATA) {
      fs_panic(12, area_type);
      return 0;
    }
    if (fsc.dblk_nxt) {
      fsc.dblk_nxt++;
      if (fsc.dblk_nxt > fsc.dblk_end)
	fsc.dblk_nxt = 0;
    }
    return fsc.dblk_nxt;
  }

}