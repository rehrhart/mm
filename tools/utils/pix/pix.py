import os
import codecs
import sys
import binascii
import struct
import argparse
from collections import OrderedDict
from decode_base import *


panic_dir_obj = aggie(OrderedDict([
    ('panic_dir_id',        atom(('I', '{}'))),
    ('panic_dir_sig',       atom(('<I', '{:x}'))),
    ('panic_dir_sector',    atom(('<I', '{}'))),
    ('panic_high_sector',   atom(('<I', '{}'))),
    ('panic_block_sector',  atom(('<I', '{}'))),
    ('panic_block_size',    atom(('<I', '{}'))),
    ('panic_dir_checksum',  atom(('<I', '{}')))
]))


panic_info_obj = aggie(OrderedDict([
    ('pi_sig',           atom(('<I', '{:x}'))),
    ('boot_count',       atom(('<I', '{}'))),
    ('systime',          atom(('<Q', '{}'))),
    ('fail_count',       atom(('<I', '{}'))),
    ('subsys',           atom(('<B', '{}'))),
    ('where',            atom(('<B', '{}'))),
    ('pad',              atom(('<H', '{}'))),
    ('arg_0',            atom(('<I', '{:x}'))),
    ('arg_1',            atom(('<I', '{:x}'))),
    ('arg_2',            atom(('<I', '{:x}'))),
    ('arg_3',            atom(('<I', '{:x}')))
]))


image_ver_obj = aggie(OrderedDict([
    ('build',          atom(('<H', '{}'))),
    ('minor',          atom(('<B', '{}'))),
    ('major',          atom(('<B', '{}')))
]))


hw_ver_obj = aggie(OrderedDict([
    ('hw_rev',         atom(('<B', '{}'))),
    ('hw_model',       atom(('<B', '{}')))
]))


image_info_obj = aggie(OrderedDict([
    ('ii_sig',         atom(('<I', '{:x}'))),
    ('image_start',    atom(('<I', '{}'))),
    ('image_length',   atom(('<I', '{}'))),
    ('vector_chk',     atom(('<I', '{}'))),
    ('image_chk',      atom(('<I', '{}'))),
    ('ver_id',         image_ver_obj),
    ('descriptor0',    atom(('<44B', '{}'))),
    ('descriptor1',    atom(('<44B', '{}'))),
    ('stamp_date',     atom(('<30B', '{}'))),
    ('hw_ver',         hw_ver_obj)
]))


add_info_obj = aggie(OrderedDict([
    ('ai_sig',           atom(('<I', '{}'))),
    ('ram_sector',       atom(('<I', '{}'))),
    ('ram_size',         atom(('<I', '{}'))),
    ('io_sector',        atom(('<I', '{}'))),
    ('fcrumb_sector',    atom(('<I', '{}'))),
]))


crash_info_obj = aggie(OrderedDict([
    ('ci_sig',    atom(('<I', '{}'))),
    ('axLR',      atom(('<I', '{}'))),
    ('MSP',       atom(('<I', '{}'))),
    ('PSP',       atom(('<I', '{}'))),
    ('primask',   atom(('<I', '{}'))),
    ('basepri',   atom(('<I', '{}'))),
    ('faultmask', atom(('<I', '{}'))),
    ('control',   atom(('<I', '{}'))),
    ('cc_sig',    atom(('<I', '{}'))),
    ('flags',     atom(('<I', '{}'))),
    ('bxReg_0',    atom(('<I', '{}'))),
    ('bxReg_1',    atom(('<I', '{}'))),
    ('bxReg_2',    atom(('<I', '{}'))),
    ('bxReg_3',    atom(('<I', '{}'))),
    ('bxReg_4',    atom(('<I', '{}'))),
    ('bxReg_5',    atom(('<I', '{}'))),
    ('bxReg_6',    atom(('<I', '{}'))),
    ('bxReg_7',    atom(('<I', '{}'))),
    ('bxReg_8',    atom(('<I', '{}'))),
    ('bxReg_9',    atom(('<I', '{}'))),
    ('bxReg_10',    atom(('<I', '{}'))),
    ('bxReg_11',    atom(('<I', '{}'))),
    ('bxReg_12',    atom(('<I', '{}'))),
    ('bxSP',      atom(('<I', '{}'))),
    ('bxLR',      atom(('<I', '{}'))),
    ('bxPC',      atom(('<I', '{}'))),
    ('bxPSR',     atom(('<I', '{}'))),
    ('axPSR',     atom(('<I', '{}'))),
    ('fpRegs',    atom(('<32I', '{}'))),
    ('fpscr',     atom(('<I', '{}')))
]))


ram_header_obj = aggie(OrderedDict([
    ('start',     atom(('<I', '{}'))),
    ('end',       atom(('<I', '{}')))
]))


panic_block_0_obj = aggie(OrderedDict([
    ('panic_info', panic_info_obj),
    ('image_info', image_info_obj),
    ('add_info',   add_info_obj),
    ('padding',    atom(('13I', '{}'))),
    ('crash_info', crash_info_obj),
    ('ram_header', ram_header_obj)
]))


def panic_args():
    parser = argparse.ArgumentParser(
        description='Panic Dump Inspector')

    parser.add_argument('input',
                        type=argparse.FileType('rb'),
                        help='panic dump file')

    parser.add_argument('-o', '--output',
                        type=argparse.FileType('wb'),
                        help='path to store output files')

    parser.add_argument('-d', '--display',
                        action='store_true',
                        help='display panic info')

    parser.add_argument('-x', '--extract',
                        action='store_true',
                        help='extract panic dump for debugging')

    return parser.parse_args()

# Global scope
args = panic_args()
inFile = args.input
outFile = args.output

pblk = 'ffffff'
PLIST = []
BLK = 0
pi_sig_hex = '0x44665041'
dir_sig_hex = '0xddddb00b'

if(not args.input):
    print("Panic File Does Not Exist")
    sys.exit(0)

# Read in Directory block for verification
raw = inFile.read()
consumed = panic_dir_obj.set(raw)
panic_dir_sector = (panic_dir_obj['panic_dir_sector'].val)
print ("panic_dir_sector: %d" % (panic_dir_sector))


panic_high_sector = (panic_dir_obj['panic_high_sector'].val)
panic_block_size = (panic_dir_obj['panic_block_size'].val)
dir_sig = (panic_dir_obj['panic_dir_sig'].val)

if (hex(dir_sig) != dir_sig_hex):
    print('dir_sig_mismatch')
    sys.exit(0)

# Checks each panic block for verification
def panic_verify(bptr,list):
    consumed = panic_block_0_obj.set(bptr)
    panic_info = panic_block_0_obj['panic_info']
    pi_sig = (panic_info['pi_sig'].val)
    if (hex(pi_sig) == pi_sig_hex):
        PLIST.append(("Panic Block %d: " % (BLK)) + str(panic_info))
        return list
    else:
        return False

# Searches panic file for panic dumps
def panic_search(plist):
    offset = 512
    global BLK
    while(args.input != ""):
        buf = raw[offset:(offset+512)]
        if not buf: break
        p = panic_verify(buf,plist)
        if (p):
            BLK += 1
        offset += 76800
    return plist

print "Panic Inspector and Extractor \n"
if(args.input and not args.display and not args.output):
    print "usage: pix.py [-h] [-o OUTPUT] [-d] [-x] input \n"
    print "pix.py: error: too few arguments"


if(args.display):
    panic_search(PLIST)
    if(panic_search):
        print ("%s Panic Dumps Found:" % (len(PLIST)))
        for element in PLIST:
            print(element)


if(args.output and not args.extract):
    print "\nUse -x to specify panic dump for extraction"
    print "usage: pix.py [-h] [-o OUTPUT] [-d] [-x] input \n"
    print "pix.py: error: too few arguments"


if(args.output and args.extract):
    if(not args.display):
        print "\nUse -d to display list of panic dumps"
        print "usage: pix.py [-h] [-o OUTPUT] [-d] [-x] input \n"

    pblk = raw_input("\n Which Panic Dump to extract? [ex. '0']: ")
    if(pblk == "-d"):
        panic_search(PLIST)
        if(panic_search):
            print ("%s Panic Dumps Found:" % (len(PLIST)))
            for element in PLIST:
                print(element)
        pblk = raw_input("\n Which Panic Dump to extract? [ex. '0']: ")

    pblk_offset = 512*150*int(pblk)+512
    ex_blk = raw[pblk_offset:]
    consumed = panic_block_0_obj.set(ex_blk)

    panic_info = panic_block_0_obj['panic_info']
    image_info = panic_block_0_obj['image_info']
    add_info = panic_block_0_obj['add_info']
    crash_info = panic_block_0_obj['crash_info']
    ram_header = panic_block_0_obj['ram_header']

    ci_sig = (crash_info['ci_sig'].val)
    cc_sig = (crash_info['cc_sig'].val)
    cc_sig = struct.pack('>I',cc_sig)
    cc_flags = (crash_info['flags'].val)
    ci_sig = (crash_info['ci_sig'].val)
    cc_sig = (crash_info['cc_sig'].val)
    cc_sig = struct.pack('>I',cc_sig)
    cc_flags = (crash_info['flags'].val)
    bxReg_0 = (crash_info['bxReg_0'].val)
    bxReg_1 = (crash_info['bxReg_1'].val)
    bxReg_2 = (crash_info['bxReg_2'].val)
    bxReg_3 = (crash_info['bxReg_3'].val)
    bxReg_4 = (crash_info['bxReg_4'].val)
    bxReg_5 = (crash_info['bxReg_5'].val)
    bxReg_6 = (crash_info['bxReg_6'].val)
    bxReg_7 = (crash_info['bxReg_7'].val)
    bxReg_8 = (crash_info['bxReg_8'].val)
    bxReg_9 = (crash_info['bxReg_9'].val)
    bxReg_10 = (crash_info['bxReg_10'].val)
    bxReg_11 = (crash_info['bxReg_11'].val)
    bxReg_12 = (crash_info['bxReg_12'].val)
    bxSP = (crash_info['bxSP'].val)
    bxLR = (crash_info['bxLR'].val)
    bxPC = (crash_info['bxPC'].val)
    bxPSR = (crash_info['bxPSR'].val)
    axPSR = (crash_info['axPSR'].val)
    ai_sig = (add_info['ai_sig'].val)
    ii_sig = (image_info['ii_sig'].val)
    pi_sig = (panic_info['pi_sig'].val)
    pi_sig_hex = '44665041'

    ram_sector = (add_info['ram_sector'].val)
    ram_size = (add_info['ram_size'].val)
    io_sector = (add_info['io_sector'].val)
    io_dump_start = ((io_sector - panic_dir_sector) * 512)

    dump_end = (panic_dir_sector + (panic_block_size * 512))
    a5 = (add_info['fcrumb_sector'].val)
    ram_start = (ram_header['start'].val)
    ram_end = (ram_header['end'].val)
    ram_header_start = struct.pack('<I',ram_start)
    ram_header_end = struct.pack('<I',ram_end)
    regs_1 = [cc_flags,bxReg_0,bxReg_1,bxReg_2]
    regs_2 = [bxReg_3,bxReg_4,bxReg_5,bxReg_6]
    regs_3 = [bxReg_7,bxReg_8,bxReg_9,bxReg_10]
    regs_4 = [bxReg_11]
    regs_5 = [bxReg_12]
    regs_6 = [bxSP,bxLR,bxPC]
    regs_7 = [bxPSR,axPSR]

    outFile.write(cc_sig)
    for b in regs_1:
        outFile.write(struct.pack('<I',b))
    for b in regs_2:
        outFile.write(struct.pack('<I',b))
    for b in regs_3:
        outFile.write(struct.pack('<I',b))
    for b in regs_4:
        outFile.write(struct.pack('<I',b))
    for b in regs_5:
        outFile.write(struct.pack('<I',b))
    for b in regs_6:
        outFile.write(struct.pack('<I',b))
    for b in regs_7:
        outFile.write(struct.pack('<I',b))
    outFile.write(ram_header_start)
    outFile.write(ram_header_end)
    ram_dump = raw[ram_sector:ram_sector+ram_size]
    outFile.write(ram_dump)
    print ("\n Debug File Exported : %s" % (args.output))
    outFile.close