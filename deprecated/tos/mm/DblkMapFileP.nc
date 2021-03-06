/*
 * Copyright (c) 2017 Daniel J. Maltbie
 * Copyright (c) 2018 Daniel J. Maltbie, Eric B. Decker
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
 * Contact: Daniel J. Maltbie <dmaltbie@daloma.org>
 *          Eric B. Decker <cire831@gmail.com>
 */

/**
 * This module handles Byte access to Dblk Stream storage using
 * the ByteMapFile interface.
 */

#include <TinyError.h>
#include <panic.h>
#include <platform_panic.h>
#include <sd.h>

typedef struct {
  uint32_t             base;         // first sector of dblk file
  uint32_t             eof;          // last sector with valid data
  uint32_t             cur;          // current sector in sbuf
} dblk_map_sectors_t;


typedef struct {
  uint32_t             file_pos;     // current file offset (pos)
  dblk_map_sectors_t   sector;       // pertinent file sector numbers
  error_t              err;          // last error encountered
  bool                 sbuf_ready;   // true if sbuf has valid data
  bool                 sbuf_requesting; // true if sd.request in progress
  bool                 sbuf_reading; // true if sd.read in progress
} dblk_map_file_t;

module DblkMapFileP {
  provides  interface ByteMapFileNew as DMF;
  uses {
    interface StreamStorage as SS;
    interface SDread        as SDread;
    interface Resource      as SDResource;
    interface Boot;
    interface Panic;
  }
}
implementation {
  dblk_map_file_t dmf_cb;
  uint8_t         dmf_sbuf[SD_BLOCKSIZE] __attribute__ ((aligned (4)));

  void dmap_panic(uint8_t where, parg_t p0, parg_t p1) {
    call Panic.panic(PANIC_TAGNET, where, p0, p1, dmf_cb.sector.base,
                     dmf_cb.sector.eof);
  }

  uint32_t sector_of(uint32_t pos) {
    uint32_t    sect;
    sect = (pos / SD_BLOCKSIZE) + dmf_cb.sector.base;
    if (sect >= dmf_cb.sector.eof)
      sect = dmf_cb.sector.eof - 1; // zzz not sure about -1
    return sect;
  }

  uint32_t offset_of(uint32_t pos) {
    return (pos % SD_BLOCKSIZE);
  }

  uint32_t fpos_of(uint32_t sect) {
    if ((sect < dmf_cb.sector.base) || (sect >= dmf_cb.sector.eof)) {
      dmap_panic(1, sect, 0);
      return 0;
    }
    return ((sect - dmf_cb.sector.base) * SD_BLOCKSIZE);
  }

  uint32_t eof_pos() {
    return ((dmf_cb.sector.eof - dmf_cb.sector.base) * SD_BLOCKSIZE);
  }

  bool is_eof(uint32_t pos) {
    if (pos >= eof_pos())
      return TRUE;
    return FALSE;
  }

  bool inbounds(uint32_t pos) {
    if (!is_eof(pos) && (sector_of(pos) == dmf_cb.sector.cur))
      return TRUE;
    return FALSE;
  }

  uint32_t remaining(uint32_t pos) {
    if (is_eof(pos))
      return 0;
    return (SD_BLOCKSIZE - offset_of(pos));
  }

  bool _get_new_sector(uint32_t pos) {
    error_t err;
    if (sector_of(pos) < dmf_cb.sector.eof) {
      dmf_cb.sbuf_ready      = FALSE;
      dmf_cb.sbuf_requesting = TRUE;
      dmf_cb.sbuf_reading    = FALSE;
      dmf_cb.sector.cur      = sector_of(pos);
      err = call SDResource.request();
      if (err == SUCCESS) return TRUE;
    }
    return FALSE;
  }

  event void SDResource.granted() {
    dmf_cb.sbuf_requesting = FALSE;
    if ((!dmf_cb.sbuf_ready) && (dmf_cb.sector.cur)) {
      if (!call SDread.read(dmf_cb.sector.cur, dmf_sbuf)) {
        dmf_cb.sbuf_reading = TRUE;
        return;
      }
    }
    call SDResource.release();
  }


  event void SDread.readDone(uint32_t blk_id, uint8_t *read_buf, error_t err) {
    call SDResource.release();
    dmf_cb.sbuf_ready      = TRUE;
    dmf_cb.sbuf_requesting = FALSE;
    dmf_cb.sbuf_reading    = FALSE;

    /* return original call's data so we can match if we want. */
    signal DMF.data_avail(0, 0, 0);
  }


  command error_t DMF.map(uint32_t context, uint8_t **bufp,
                          uint32_t offset, uint32_t *lenp) {
    uint32_t    count  = 0;

    if (dmf_cb.sbuf_ready) {
      count = (*lenp > remaining(dmf_cb.file_pos))   \
        ? remaining(dmf_cb.file_pos)                \
        : *lenp;
      *bufp = &dmf_sbuf[offset_of(dmf_cb.file_pos)];
      *lenp = count;
      dmf_cb.file_pos += count;
      if ((!is_eof(dmf_cb.file_pos)) &&
          (remaining(dmf_cb.file_pos) == 0))
        if (!_get_new_sector(dmf_cb.file_pos))
          return FAIL;
      return SUCCESS;
    }
    return EBUSY;
  }


  event void SS.dblk_advanced(uint32_t last) {
    bool was_zero = (!dmf_cb.sector.eof);

    // zzz for debugging, only set eof once
    // zzz if (!was_zero) return;

    dmf_cb.sector.eof = last;
    if (was_zero)
      _get_new_sector(dmf_cb.file_pos);  // get the first one
  }


  command uint32_t DMF.filesize(uint32_t context) {
    return ((dmf_cb.sector.eof - dmf_cb.sector.base) * SD_BLOCKSIZE);
  }


  command uint32_t DMF.commitsize(uint32_t context) {
    return 0;
  }


  event void Boot.booted() {
    dmf_cb.sector.base      = call SS.get_dblk_low();
    dmf_cb.sector.cur       = 0;
    dmf_cb.sector.eof       = call SS.eof_block_offset();
    dmf_cb.file_pos         = 0;
    dmf_cb.sbuf_ready       = FALSE;
    dmf_cb.sbuf_requesting  = FALSE;
    dmf_cb.sbuf_reading     = FALSE;
  }


          event void SS.dblk_stream_full() { }
  async   event void Panic.hook()          { }
  default event void DMF.data_avail(uint32_t context, uint32_t offset,
                                    uint32_t len) { }
}
