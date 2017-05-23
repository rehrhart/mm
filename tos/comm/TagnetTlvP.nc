/**
 * Copyright (c) 2017 Daniel J. Maltbie
 * All rights reserved.
 *
 */
/*
 * Redistribution and use in source and binary forms, with or without
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
 *
 * @author Daniel J. Maltbie <dmaltbie@daloma.org>
 *
 */

#include "TagnetTLV.h"

module TagnetTlvP {
  provides interface TagnetTLV;
}
implementation {

  int  _copy_bytes(uint8_t *s, uint8_t *d, int l) {
    int      x;
    for (x = 0; x < l; x++)  d[x] =  s[x];
    return l;
  }
  
  bool  _cmp_bytes(uint8_t *s, uint8_t *d, int l) {
    int      x;
    for (x = 0; x < l; x++)  if (d[x] != s[x]) return FALSE;
    return TRUE;
  }
  
  command uint8_t   TagnetTLV.copy_tlv(tagnet_tlv_t *s,  tagnet_tlv_t *d, uint8_t limit) {
    uint8_t l = s->len + sizeof(tagnet_tlv_t);
    if (l > limit)
      return 0;
    return _copy_bytes((uint8_t *) s, (uint8_t *) d, l);
  }

  command bool   TagnetTLV.eq_tlv(tagnet_tlv_t *s, tagnet_tlv_t *t) {
    if ((s->typ >= _TN_TLV_COUNT) || (t->typ >= _TN_TLV_COUNT)) {
//      panic_warn();
      return FALSE;
    }
    return (_cmp_bytes((uint8_t *)s, (uint8_t *)t, s->len + sizeof(tagnet_tlv_t)));
  }

  command uint8_t   TagnetTLV.get_len(tagnet_tlv_t *t) {
    if (t->typ >= _TN_TLV_COUNT) {
//      panic_warn();
      return 0;
    }
    return t->len + sizeof(tagnet_tlv_t);
  }

  command uint8_t   TagnetTLV.get_len_v(tagnet_tlv_t *t) {
    if (t->typ >= _TN_TLV_COUNT) {
//      panic_warn();
      return 0;
    }
    return t->len;
  }

  command tagnet_tlv_t  *TagnetTLV.get_next_tlv(tagnet_tlv_t *t, uint8_t limit) {
    tagnet_tlv_t      *next_tlv;
    int                nx;

    if ((t->len == 0) || (t->typ == TN_TLV_NONE))
      return NULL;
    if (t->typ >= _TN_TLV_COUNT) {
//      panic_warn();
      return NULL;
    }
    nx = t->len + sizeof(tagnet_tlv_t);
    if (nx < limit) {
      nx += (int) t;
      next_tlv = (tagnet_tlv_t *) nx;
      if ((next_tlv->len > 0)
          && (next_tlv->len < (limit - sizeof(tagnet_tlv_t)))
            && (next_tlv->typ != TN_TLV_NONE)
              && (next_tlv->typ < _TN_TLV_COUNT)) {
        return next_tlv;
      }
    }
    return NULL;
  }

  command tagnet_tlv_type_t TagnetTLV.get_tlv_type(tagnet_tlv_t *t) {
    if (t->typ >= _TN_TLV_COUNT) {
//      panic_warn();
      return TN_TLV_NONE;
    }
    return t->typ;
  }

  command uint8_t  TagnetTLV.integer_to_tlv(int32_t i,  tagnet_tlv_t *t, uint8_t limit) {
    t->typ = TN_TLV_INTEGER;
    t->len = 1;
    t->val[0] = i;
    return (sizeof(tagnet_tlv_t) + 1);
  }

  command bool   TagnetTLV.is_special_tlv(tagnet_tlv_t *t) {
    switch (t->typ) {
      case TN_TLV_SEQ_NO:
      case TN_TLV_NODE_ID:
      case TN_TLV_GPS_POS:
      case TN_TLV_UTC_TIME:
        return TRUE;
      default:
        return FALSE;
    }
    return FALSE; // shouldn't get here
  }

  command int   TagnetTLV.repr_tlv(tagnet_tlv_t *t,  uint8_t *b, uint8_t limit) {
    switch (t->typ) {
      case TN_TLV_STRING:
        if (t->len > limit) return -1;
        return _copy_bytes((uint8_t *)&t->val[0], b,  t->len);
      default:
        return -1;
    }
    return -1;   // shouldn't get here
  }

  command uint8_t   TagnetTLV.string_to_tlv(uint8_t *s, uint8_t length,
                                                    tagnet_tlv_t *t, uint8_t limit) {
    if ((length + sizeof(tagnet_tlv_t)) < limit) {
      _copy_bytes(s, (uint8_t *)&t->val[0], length);
      t->len = length;
      t->typ = TN_TLV_STRING;
      return length + sizeof(tagnet_tlv_t);
    }
    return 0;
  }

  command int32_t   TagnetTLV.tlv_to_integer(tagnet_tlv_t *t) {
    return t->val[0];   // zzz need to fix
  }
    
  command uint8_t   *TagnetTLV.tlv_to_string(tagnet_tlv_t *t, int *len) {
    uint8_t  *s = (uint8_t *)t + sizeof(tagnet_tlv_t);
    *len = t->len;
    return s;
  }

}
