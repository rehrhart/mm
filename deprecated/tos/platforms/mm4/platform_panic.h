/*
 * panic codes.
 */


#ifndef __PLATFORM_PANIC_H__
#define __PLATFORM_PANIC_H__

#include "panic.h"

/*
 * KERN:	core kernal
 * ADC:		Analog Digital Conversion subsystem (AdcP.nc)
 * MISC:
 * COMM:	communications subsystem
 * MS:		Mass Storage (FileSystemP, SD)
 * SS:		Stream Storage, hard fail
 * SS_RECOV:	Stream Storage, recoverable
 * GPS:		gps subsystem
 */

enum {
  __pcode_adc  = PANIC_HC_START,          /* 0x70, see panic.h */
  __pcode_misc,
  __pcode_comm,
  __pcode_ms,
  __pcode_ss,
  __pcode_ss_recov,
  __pcode_gps,

#ifdef notdef
  __pcode_sns,
  __pcode_pwr,
#endif
};

#define PANIC_ADC       __pcode_adc
#define PANIC_MISC      __pcode_misc
#define PANIC_COMM      __pcode_comm
#define PANIC_MS        __pcode_ms
#define PANIC_SS        __pcode_ss
#define PANIC_SS_RECOV  __pcode_ss_recov
#define PANIC_GPS       __pcode_gps

#ifdef notdef
#define PANIC_SNS       __pcode_sns
#define PANIC_PWR       __pcode_pwr
#endif
#endif /* __PLATFORM_PANIC_H__ */
