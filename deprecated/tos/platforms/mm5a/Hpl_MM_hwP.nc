/*
 * Copyright (c) 2014-2016 Eric B. Decker
 * All rights reserved.
 *
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
 */

/**
 * The Hpl_MM_hw interface exports low-level access to control registers
 * of the mammark h/w.
 *
 * @author Eric B. Decker
 */

#include "hardware.h"

module Hpl_MM_hwP {
  provides interface Hpl_MM_hw as HW;
}

implementation {
  async command bool HW.mems_gyro_drdy()     { return GYRO_DRDY; }
  async command bool HW.mems_gyro_irq()      { return GYRO_IRQ; }
  async command bool HW.mems_mag_drdy()      { return MAG_DRDY; }
  async command bool HW.mems_mag_irq()       { return MAG_IRQ; }
  async command bool HW.mems_accel_int1()    { return ACCEL_INT1; }
  async command bool HW.mems_accel_int2()    { return ACCEL_INT2; }
  async command void HW.mems_accel_set_cs()  { ACCEL_CSN = 0; }
  async command void HW.mems_accel_clr_cs()  { ACCEL_CSN = 1; }
  async command void HW.mems_gyro_set_cs()   { GYRO_CSN = 0; }
  async command void HW.mems_gyro_clr_cs()   { GYRO_CSN = 1; }
  async command void HW.mems_mag_set_cs()    { MAG_CSN = 0; }
  async command void HW.mems_mag_clr_cs()    { MAG_CSN = 1; }

  async command bool HW.adc_drdy()           { return !ADC_DRDY_N; }
  async command void HW.adc_set_start()      { ADC_START = 1; }
  async command void HW.adc_clr_start()      { ADC_START = 0; }
  async command void HW.adc_set_cs()         { ADC_CSN = 0; }
  async command void HW.adc_clr_cs()         { ADC_CSN = 1; }

  async command bool HW.dock_irq()           { return DOCK_IRQ; }

  async command bool HW.gps_awake()          { return GSD4E_GPS_AWAKE; }
  async command void HW.gps_set_cs()         { GSD4E_GPS_CSN = 0; }
  async command void HW.gps_clr_cs()         { GSD4E_GPS_CSN = 1; }
  async command void HW.gps_set_on_off()     { GSD4E_GPS_ON_OFF = 1; }
  async command void HW.gps_clr_on_off()     { GSD4E_GPS_ON_OFF = 0; }
  async command void HW.gps_set_reset()      { GSD4E_GPS_RESET; }
  async command void HW.gps_clr_reset()      { GSD4E_GPS_UNRESET; }

  async command void HW.pwr_3v3_on()         { PWR_3V3_ENA = 1; }
  async command void HW.pwr_3v3_off()        { PWR_3V3_ENA = 0; }
  async command void HW.pwr_solar_ena()      { SOLAR_ENA = 1; }
  async command void HW.pwr_solar_dis()      { SOLAR_ENA = 0; }
  async command void HW.pwr_bat_sense_ena()  { BAT_SENSE_ENA = 1; }
  async command void HW.pwr_bat_sense_dis()  { BAT_SENSE_ENA = 0; }
  async command void HW.pwr_tmp_on()         { TEMP_PWR = 1; }
  async command void HW.pwr_tmp_off()        { TEMP_PWR = 0; }
}
