'''Core Data Type records/objects'''

# Copyright (c) 2017-2018, Daniel J. Maltbie, Eric B. Decker
# All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# See COPYING in the top level directory of this source tree.
#
# Contact: Daniel J. Maltbie <dmaltbie@daloma.org>
#          Eric B. Decker <cire831@gmail.com>

# basic data type object descriptors

__version__ = '0.2.6 (ch)'

import binascii
from   decode_base  import *
from   collections  import OrderedDict
from   sirf_headers import sirf_hdr_obj
from   sirf_headers import sirf_swver_obj

rtctime_obj = aggie(OrderedDict([
    ('sub_sec', atom(('<H', '{}'))),
    ('sec',     atom(('<B', '{}'))),
    ('min',     atom(('<B', '{}'))),
    ('hr',      atom(('<B', '{}'))),
    ('dow',     atom(('<B', '{}'))),
    ('day',     atom(('<B', '{}'))),
    ('mon',     atom(('<B', '{}'))),
    ('year',    atom(('<H', '{}'))),
]))

dt_hdr_obj = aggie(OrderedDict([
    ('len',     atom(('<H', '{}'))),
    ('type',    atom(('<H', '{}'))),
    ('recnum',  atom(('<I', '{}'))),
    ('rt',      rtctime_obj),
    ('recsum',  atom(('<H', '0x{:04x}'))),
]))

dt_simple_hdr   = aggie(OrderedDict([('hdr', dt_hdr_obj)]))

dt_reboot_obj   = aggie(OrderedDict([
    ('hdr',       dt_hdr_obj),
    ('prev_sync', atom(('<I', '{:08x}'))),
    ('majik',     atom(('<I', '{:08x}'))),
    ('dt_rev',    atom(('<I', '{:08x}'))),
    ('base',      atom(('<I', '{:08x}'))),
]))

#
# reboot is followed by the ow_control_block
# We want to decode that as well.  native order, little endian.
# see OverWatch/overwatch.h.
#
owcb_obj        = aggie(OrderedDict([
    ('ow_sig',          atom(('<I', '0x{:08x}'))),
    ('rpt',             atom(('<I', '0x{:08x}'))),
#
# change uptime from 64 bit ms time to 32 bit secs
# uptime and elapsed need to be changed.  Perhaps
# boot time (rtctime), calculate elapsed.
#
    ('uptime',          atom(('<Q', '0x{:08x}'))),
    ('reset_status',    atom(('<I', '0x{:08x}'))),
    ('reset_others',    atom(('<I', '0x{:08x}'))),
    ('from_base',       atom(('<I', '0x{:08x}'))),
    ('fail_count',      atom(('<I', '{}'))),
    ('fault_gold',      atom(('<I', '0x{:08x}'))),
    ('fault_nib',       atom(('<I', '0x{:08x}'))),
    ('subsys_disable',  atom(('<I', '0x{:08x}'))),
    ('ow_sig_b',        atom(('<I', '0x{:08x}'))),
    ('ow_req',          atom(('<B', '{}'))),
    ('reboot_reason',   atom(('<B', '{}'))),
    ('ow_boot_mode',    atom(('<B', '{}'))),
    ('owt_action',      atom(('<B', '{}'))),
    ('reboot_count',    atom(('<I', '{}'))),

# ditto for elapsed

    ('elapsed',         atom(('<Q', '0x{:08x}'))),
    ('strange',         atom(('<I', '{}'))),
    ('strange_loc',     atom(('<I', '0x{:04x}'))),
    ('vec_chk_fail',    atom(('<I', '{}'))),
    ('image_chk_fail',  atom(('<I', '{}'))),
    ('ow_sig_c',        atom(('<I', '0x{:08x}')))
]))


dt_version_obj  = aggie(OrderedDict([
    ('hdr',       dt_hdr_obj),
    ('base',      atom(('<I', '{:08x}')))]))


hw_version_obj      = aggie(OrderedDict([
    ('rev',       atom(('<B', '{:x}'))),
    ('model',     atom(('<B', '{:x}')))]))


image_version_obj   = aggie(OrderedDict([
    ('build',     atom(('<H', '{:x}'))),
    ('minor',     atom(('<B', '{:x}'))),
    ('major',     atom(('<B', '{:x}')))]))


image_info_obj  = aggie(OrderedDict([
    ('ii_sig',    atom(('<I', '0x{:08x}'))),
    ('im_start',  atom(('<I', '0x{:08x}'))),
    ('im_len',    atom(('<I', '0x{:08x}'))),
    ('vect_chk',  atom(('<I', '0x{:08x}'))),
    ('im_chk',    atom(('<I', '0x{:08x}'))),
    ('ver_id',    image_version_obj),
    ('desc0',     atom(('44s', '{:s}'))),
    ('desc1',     atom(('44s', '{:s}'))),
    ('build_date',atom(('30s', '{:s}'))),
    ('hw_ver',    hw_version_obj)]))


dt_sync_obj     = aggie(OrderedDict([
    ('hdr',       dt_hdr_obj),
    ('prev_sync', atom(('<I', '{:x}'))),
    ('majik',     atom(('<I', '{:08x}')))]))


# EVENT
event_names = {
     1: "SURFACED",
     2: "SUBMERGED",
     3: "DOCKED",
     4: "UNDOCKED",

     5: "GPS_GEO",
     6: "GPS_XYZ",
     7: "GPS_TIME",

     8: "SSW_DELAY_TIME",
     9: "SSW_BLK_TIME",
    10: "SSW_GRP_TIME",
    11: "PANIC_WARN",

    32: "GPS_BOOT",
    33: "GPS_BOOT_TIME",
    49: "GPS_BOOT_FAIL",
    50: "GPS_HW_CONFIG",
    34: "GPS_RECONFIG",
    35: "GPS_TURN_ON",
    36: "GPS_TURN_OFF",
    37: "GPS_STANDBY",
    38: "GPS_MPM",
    39: "GPS_FULL_PWR",
    40: "GPS_PULSE",
    41: "GPS_FAST",
    42: "GPS_FIRST",
    43: "GPS_SATS_2",
    44: "GPS_SATS_7",
    45: "GPS_SATS_41",
    46: "GPS_CYCLE_TIME",
    47: "GPS_RX_ERR",
    48: "GPS_AWAKE_S",
    51: "GPS_CMD",
    52: "GPS_RAW_TX",
    53: "GPS_SWVER_TO",
}

PANIC_WARN = 11
GPS_CMD    = 51


# GPS_CMD, first arg of GPS_CMD
gps_cmd_names = {
       0: "NOP",
       1: "TURNON",
       2: "TURNOFF",
       3: "STANDBY",
       4: "HIBERNATE",
       5: "WAKE",
       6: "PULSE",
       7: "AWAKE_STATUS",
       8: "RESET",
       9: "POWER_ON",
      10: "POWER_OFF",
      11: "SEND_MPM",
      12: "SEND_FULL",
      13: "RAW_TX",
    0x80: "REBOOT",
    0x81: "PANIC",
    0x82: "BRICK",
}


dt_event_obj    = aggie(OrderedDict([
    ('hdr',   dt_hdr_obj),
    ('event', atom(('<H', '{}'))),
    ('pcode', atom(('<B', '{}'))),
    ('w',     atom(('<B', '{}'))),
    ('arg0',  atom(('<I', '0x{:04x}'))),
    ('arg1',  atom(('<I', '0x{:04x}'))),
    ('arg2',  atom(('<I', '0x{:04x}'))),
    ('arg3',  atom(('<I', '0x{:04x}')))]))


#
# not implemented yet.
#
dt_debug_obj    = dt_simple_hdr

#
# dt, native, little endian
# used by DT_GPS_VERSION and DT_GPS_RAW_SIRFBIN (gps_raw)
#
dt_gps_hdr_obj = aggie(OrderedDict([('hdr',     dt_hdr_obj),
                                    ('mark',    atom(('<I', '0x{:04x}'))),
                                    ('chip',    atom(('B',  '0x{:02x}'))),
                                    ('dir',     atom(('B',  '{}'))),
                                    ('pad',     atom(('<H', '{}')))]))

dt_gps_ver_obj = aggie(OrderedDict([('gps_hdr',    dt_gps_hdr_obj),
                                    ('sirf_swver', sirf_swver_obj)]))

dt_gps_time_obj = dt_simple_hdr
dt_gps_geo_obj  = dt_simple_hdr
dt_gps_xyz_obj  = dt_simple_hdr

dt_sen_data_obj = dt_simple_hdr
dt_sen_set_obj  = dt_simple_hdr

dt_test_obj     = dt_simple_hdr

####
#
# NOTES
#
# A note record consists of a dt_note_t header (same as dt_header_t, a
# simple header) followed by n bytes of note.  typically a printable
# ascii string (yeah, localization is an issue, but not now).
#
dt_note_obj     = dt_simple_hdr
dt_config_obj   = dt_simple_hdr

# DT_GPS_RAW_SIRFBIN, dt, native, little endian
#  sirf data big endian.
dt_gps_raw_obj = aggie(OrderedDict([('gps_hdr',  dt_gps_hdr_obj),
                                    ('sirf_hdr', sirf_hdr_obj)]))
