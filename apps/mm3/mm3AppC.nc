/*
 * Copyright (c) 2008, Eric B. Decker
 * All rights reserved.
 */

configuration mm3AppC {}
implementation {
  components SystemBootC, mm3C;
  SystemBootC.SoftwareInit -> mm3C;
  mm3C -> SystemBootC.Boot;
  
  components RegimeC;
  mm3C.Regime -> RegimeC;
  
  components LedsC;
  mm3C.Leds -> LedsC;

  /*
   * Include sensor components.  No need to wire.  They will
   * start when regimeChange() is signalled.
   */
  components BattC, TempC, SalC, AccelC, PTempC, PressC, SpeedC, MagC;
}
