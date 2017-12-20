/**
 * This module handles Byte access to the Dblk storage files
 *
 *<p>
 * @author Daniel J. Maltbie <dmaltbie@daloma.org>
 *
 * @Copyright (c) 2017 Daniel J. Maltbie
 * All rights reserved.
 *</p>
 */
/* Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 *
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#include <TinyError.h>
#include <mm_byteswap.h>
#include <message.h>
#include <Tagnet.h>
#include <TagnetAdapter.h>

module DblkByteStorageP {
  provides {
    interface  TagnetAdapter<tagnet_dblk_bytes_t>  as Dblk0Bytes;
    interface  TagnetAdapter<tagnet_dblk_bytes_t>  as Dblk1Bytes;
    interface  TagnetAdapter<uint8_t>              as DblkNote;
  }
  uses {
    interface DblkMapFile  as DMF;
    interface Boot;
    interface Collect;
    interface Panic;
  }
}
implementation {

  bool GetDblkBytes(tagnet_dblk_bytes_t *db, uint32_t *len) {
    error_t    err;

    nop();
    nop();                      /* BRK */
    switch (db->action) {
      case DBLK_GET_DATA:
        err = call DMF.seek(db->file, db->iota, 0);
        if (err == SUCCESS) {
          err = call DMF.map(db->file, &db->block, len);
        }
        if (err == SUCCESS) {
          db->iota   = call DMF.tell(db->file);
          db->count -= *len;
          db->error  = SUCCESS;
          return TRUE;
        }
        break;
      case  DBLK_GET_ATTR:
        db->iota   = call DMF.tell(db->file);
        db->count  = call DMF.filesize(db->file);
        return TRUE;
        break;
      default:
        err = EINVAL;
        break;
    }
    db->iota = call DMF.tell(db->file);
    db->count = 0;
    db->error = err;
    return FALSE;
  }

  command bool Dblk0Bytes.get_value(tagnet_dblk_bytes_t *db, uint32_t *len) {
    db->file = 0;
    return GetDblkBytes(db, len);
  }

  command bool Dblk0Bytes.set_value(tagnet_dblk_bytes_t *db, uint32_t *len) {
    return FALSE; }


  command bool Dblk1Bytes.get_value(tagnet_dblk_bytes_t *db, uint32_t *len) {
    db->file = 1;
    return GetDblkBytes(db, len);
  }

  command bool Dblk1Bytes.set_value(tagnet_dblk_bytes_t *db, uint32_t *len) {
    return FALSE; }


  command bool DblkNote.get_value(uint8_t *db, uint32_t *len) {
    return FALSE; }

  command bool DblkNote.set_value(uint8_t *db, uint32_t *len) {
    dt_note_t    note_block;
    /*
      uint16_t len;                 * size 28 + var *
      dtype_t  dtype;
      uint32_t recnum;
      uint64_t systime;
      uint16_t recsum;
      uint16_t note_len;
      uint16_t year;
      uint8_t  month;
      uint8_t  day;
      uint8_t  hrs;
      uint8_t  min;
      uint8_t  sec;
    */
    uint16_t     dlen;

    dlen = CF_BE_16(*len) - 1;
    note_block.len = dlen + sizeof(note_block);
    note_block.dtype = DT_NOTE;
    note_block.note_len = *len;
    call Collect.collect((void *) &note_block, sizeof(note_block),
                         db, dlen);
    return dlen;
  }

  event void DMF.mapped(uint8_t fd, uint32_t file_pos) {
    nop();
    nop();                            /* BRK */
  }

  async event void Panic.hook() { }

  event void Boot.booted() {
    nop();
    nop();                            /* BRK */
  }
}
