/*
 * Copyright (c) 2016-2018 Eric B. Decker
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
 */

#include "hardware.h"

configuration PlatformC {
  provides {
    interface Init as PlatformInit;
    interface Platform;
    interface PlatformNodeId;
    interface SysReboot;
    interface Rtc;
  }
  uses interface Init as PeripheralInit;
}

implementation {
  components PlatformP;
  Platform       = PlatformP;
  PlatformNodeId = PlatformP;
  PlatformInit   = PlatformP;
  PeripheralInit = PlatformP.PeripheralInit;
  SysReboot      = PlatformP;

  components PlatformLedsC;
  PlatformP.PlatformLeds -> PlatformLedsC;

  /* pull in other modules we want */
  components PlatformPinsC;

  /* clocks are initilized by startup */

  /*
   * RealTime Clock Wiring
   */
  components PlatformRtcC;
  Rtc      = PlatformRtcC;
}
