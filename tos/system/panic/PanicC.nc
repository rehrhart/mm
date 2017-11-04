/*
 * Copyright (c) 2008, 2012 Eric B. Decker
 * Copyright (c) 2017, Eric B. Decker
 * @author Eric B. Decker
 */

#include "panic.h"

configuration PanicC {
  provides interface Panic;
}

implementation {
  components PanicP, MainC, PlatformC;
  Panic = PanicP;
  PanicP.Platform  -> PlatformC;
  PanicP.SysReboot -> PlatformC;
  MainC.SoftwareInit -> PanicP;

  components FileSystemC as FS;
  PanicP.FS -> FS;

  components OverWatchC;
  PanicP.OverWatch -> OverWatchC;

  components SD0C, SSWriteC;
  PanicP.SSW   -> SSWriteC;
  PanicP.SDsa  -> SD0C;
  PanicP.SDraw -> SD0C;

  components ChecksumM;
  PanicP.Checksum -> ChecksumM;
}