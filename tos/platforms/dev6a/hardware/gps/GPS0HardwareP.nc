/*
 * Copyright (c) 2017 Eric B. Decker
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

#include <hardware.h>
#include <panic.h>
#include <platform_panic.h>
#include <msp432.h>

/* see gps_pwr_on for why we include gps.h */
#include <gps.h>

/*
 * The eUSCI for the UART is always clocked by SMCLK which is DCOCLK/2.  So
 * if MSP432_CLK is 16777216 (16MiHz) the SMCLK is 8MiHz, 8388608 Hz.
 */

#if (MSP432_CLK != 16777216)
#warning MSP432_CLK other than 16777216
#endif

#ifndef PANIC_GPS
enum {
  __pcode_gps = unique(UQ_PANIC_SUBSYS)
};

#define PANIC_GPS __pcode_gps
#endif

module GPS0HardwareP {
  provides {
    interface Init;
    interface Gsd4eUHardware as HW;
  }
  uses {
    interface HplMsp432Usci    as Usci;
    interface HplMsp432UsciInt as Interrupt;
    interface Panic;
    interface Platform;
  }
}
implementation {

  enum {
    UART_MAX_BUSY_WAIT = 10000,                 /* 10ms max busy wait time */
  };


#define gps_panic(where, arg, arg1) do {                 \
    call Panic.panic(PANIC_GPS, where, arg, arg1, 0, 0); \
  } while (0)

#define  gps_warn(where, arg)      do { \
    call  Panic.warn(PANIC_GPS, where, arg, 0, 0, 0); \
  } while (0)


  /* Baud rate divisor equations
   *
   * N.Frac = BRCLK / bps
   * brw = N
   * BRCLK = 8Mi (8388608)
   * EUSCI_A_MCTLW_BRS_OFS = lookup[Frac]
   *
   * (see table on page 736 of SLAU356E - Revised Dec 2016)
   */

  const msp432_usci_config_t gps_4800_config = {
    ctlw0 : EUSCI_A_CTLW0_SSEL__SMCLK,
    brw   : 1747,
    mctlw : (0 << EUSCI_A_MCTLW_BRF_OFS) |
            (0xb5 << EUSCI_A_MCTLW_BRS_OFS),
    i2coa : 0
  };


  const msp432_usci_config_t gps_9600_config = {
    ctlw0 : EUSCI_A_CTLW0_SSEL__SMCLK,
    brw   : 873,
    mctlw : (0 << EUSCI_A_MCTLW_BRF_OFS) |
            (0xee << EUSCI_A_MCTLW_BRS_OFS),
    i2coa : 0
  };


  const msp432_usci_config_t gps_115200_config = {
    ctlw0 : EUSCI_A_CTLW0_SSEL__SMCLK,
    brw   : 72,
    mctlw : (0 << EUSCI_A_MCTLW_BRF_OFS) |
            (0xee << EUSCI_A_MCTLW_BRS_OFS),
    i2coa : 0
  };


#ifdef notdef
  const msp432_usci_config_t gps_57600_config = {
    ctlw0 : EUSCI_A_CTLW0_SSEL__SMCLK,
    brw   : 145,
    mctlw : (0 << EUSCI_A_MCTLW_BRF_OFS) |
            (0xb5 << EUSCI_A_MCTLW_BRS_OFS),
    i2coa : 0
  };


  const msp432_usci_config_t gps_307200_config = {
    ctlw0 : EUSCI_A_CTLW0_SSEL__SMCLK,
    brw   : 27,
    mctlw : (0 << EUSCI_A_MCTLW_BRF_OFS) |
            (0x25 << EUSCI_A_MCTLW_BRS_OFS),
    i2coa : 0
  };


  const msp432_usci_config_t gps_921600_config = {
    ctlw0 : EUSCI_A_CTLW0_SSEL__SMCLK,
    brw   : 9,
    mctlw : (0 << EUSCI_A_MCTLW_BRF_OFS) |
            (0x08 << EUSCI_A_MCTLW_BRS_OFS),
    i2coa : 0
  };


  const msp432_usci_config_t gps_1228800_config = {
    ctlw0 : EUSCI_A_CTLW0_SSEL__SMCLK,
    brw   : 6,
    mctlw : (0 << EUSCI_A_MCTLW_BRF_OFS) |
            (0xbf << EUSCI_A_MCTLW_BRS_OFS),
    i2coa : 0
  };
#endif


  norace uint8_t *m_tx_buf;
  norace uint16_t m_tx_len;

  norace uint8_t *m_rx_buf;
  norace uint16_t m_rx_len;
  norace uint32_t m_tx_idx, m_rx_idx;

  command error_t Init.init() {
    call Usci.enableModuleInterrupt();
    GSD4E_PINS_MODULE;			/* connect from the UART */
    return SUCCESS;
  }


  async command void HW.gps_set_on_off() {
    GSD4E_ONOFF = 1;
  }

  async command void HW.gps_clr_on_off() {
    GSD4E_ONOFF = 0;
  }

  async command void HW.gps_set_reset() {
    GSD4E_CTS = 1;              /* say we want UART mode */
    GSD4E_RESETN_OUTPUT;
    GSD4E_RESETN = 0;
  }

  async command void HW.gps_clr_reset() {
    GSD4E_RESETN = 1;
    GSD4E_RESETN_FLOAT;
  }

  async command bool HW.gps_awake() {
    return GSD4E_AWAKE_P;
  }

  async command void HW.gps_pwr_on() {
    uint32_t t0;

    GSD4E_PINS_MODULE;			/* connect to the UART */

    /* we simulate a power on by hitting reset */
    call HW.gps_set_reset();
    t0 = call Platform.usecsRaw();
    while (call Platform.usecsRaw() - t0 < DT_GPS_RESET_PULSE_WIDTH_US) { }
    call HW.gps_clr_reset();
  }

  async command void HW.gps_pwr_off() {
    GSD4E_PINS_PORT;                    /* disconnect from the UART */
  }

  /*
   * gps_tx_finnish: wait for tx to finish
   *
   * input: byte_delay (in us) for last byte to leave
   *
   * tx_finnish first makes sure that the TXBUF is empty.  ie. that the
   * byte in TXBUF has actually been transferred into the shift register
   * and is on its way out.
   *
   * Then if byte_delay is set it will delay some more.  byte_delay is
   * a value used to let the last byte actually leave the shift register.
   * This is used prior to changing communications configurations.
   */
  async command void HW.gps_tx_finnish(uint32_t byte_delay) {
    uint32_t t0, t1;

    t0 = call Platform.usecsRaw();
    while (!call Usci.isTxIntrPending()) {
      t1 = call Platform.usecsRaw();
      if (t1 - t0 > UART_MAX_BUSY_WAIT) {
	gps_panic(1, t1, t0);
	return;
      }
    }
    t0 = call Platform.usecsRaw();
    while (1) {
      t1 = call Platform.usecsRaw();
      if (t1 - t0 > byte_delay)
        return;
    }
  }

  async command void HW.gps_speed_di(uint32_t speed) {
    const msp432_usci_config_t *config = NULL;

    switch(speed) {
      case    4800:     config =    &gps_4800_config;    break;
      case    9600:     config =    &gps_9600_config;    break;
      case  115200:     config =  &gps_115200_config;    break;
      default:          gps_panic(2, speed, 0);          break;

#ifdef notdef
      case   57600:     config =   &gps_57600_config;    break;
      case  307200:     config =  &gps_307200_config;    break;
      case  921600:     config =  &gps_921600_config;    break;
      case 1228800:     config = &gps_1228800_config;    break;
#endif
    }
    if (!config)
	gps_panic(3, speed, 0);
    call Usci.configure(config, FALSE);

    /* Usci.configure (via reset) turns off all interrupts and
     * cleans all IFGs out.
     */

  }

  /*
   * enable the rx interrupt.
   *
   * prior to enabling check for any rx errors and clear them if present
   */
  async command void HW.gps_rx_int_enable() {
    uint16_t stat_word;

    stat_word = call Usci.getStat();
    if (stat_word & EUSCI_A_STATW_RXERR)
      call Usci.getRxbuf();
    call Usci.enableRxIntr();
  }

  async command void HW.gps_rx_int_disable() {
    call Usci.disableRxIntr();
  }

  async command void HW.gps_clear_rx_errs() {
    call Usci.getRxbuf();
  }

  async command error_t HW.gps_receive_block(uint8_t *ptr, uint16_t len) {
    if (!len || !ptr)
      return FAIL;

    if (m_rx_buf)
      return EBUSY;

    m_rx_len = len;
    m_rx_idx = 0;
    m_rx_buf = ptr;
    call HW.gps_rx_int_enable();
    return SUCCESS;
  }

  async command void    HW.gps_receive_block_stop() {
    m_rx_buf = NULL;
  }

  async command void    HW.gps_rx_off() { }
  async command void    HW.gps_rx_on()  { }

  async command error_t HW.gps_send_block(uint8_t *ptr, uint16_t len) {
    if (!len || !ptr)
      return FAIL;

    if (m_tx_buf)
      return EBUSY;

    m_tx_len = len;
    m_tx_idx = 0;
    m_tx_buf = ptr;
    /*
     * There may be a pending send still in progress, the tail end.
     * If that is the case then TXIFG won't be asserted.  It will assert
     * when TXBUF goes empty and then we can start up this send.
     *
     * So just enable the interrupt and let it fly.
     */
    call Usci.enableTxIntr();
    return SUCCESS;
  }

  async command void    HW.gps_send_block_stop() {
    call Usci.disableTxIntr();
    m_tx_buf = NULL;
  }

  /*
   * WARNING: there is a nasty interaction between the Interrupt system
   * and how the TXIFG works on the eUSCI.  On the way in via interrupt
   * reading the eUSCI->IV register to get the IV clears the highest
   * IFG as well as generates the IV value.  This clears the TXIFG.
   *
   * So if this is the last byte that we are transmitting and we want
   * to turn off the TX interrupt driven system, we now have no TXIFG
   * indicating that the TXBUF is empty.  So how does one start the system
   * back up on the next transmit?  You can try to replace it by
   * writing IFG but that has implications on other parts of the eUSCI
   * race conditions etc.  So we turn off interrupts when the last byte
   * is written to the TXBUF (TXIFG goes down) and signal completion.
   *
   * If we then need to reconfigure and need to make sure that all the
   * bytes have been transmitted, one may need to take up to 2 byte
   * times before complete, one for the byte in the shift register and
   * one for the last byte written.
   */
  async event void Interrupt.interrupted(uint8_t iv) {
    uint16_t stat_word;
    uint8_t data;
    uint8_t *buf;

    switch(iv) {
      case MSP432U_IV_RXIFG:
        /*
         * first check for any rx errors.  If an rx error has messsed with
         * the stream we want to tell the protocol engine and blow things
         * up.  The next char however could be part of a good stream.
         */
        stat_word = call Usci.getStat();
        if (stat_word & EUSCI_A_STATW_RXERR)
          signal HW.gps_rx_err(stat_word);

        /* if there was an rx_err, the read of RxBuf will clear it */
        data = call Usci.getRxbuf();
        if (m_rx_buf) {
          m_rx_buf[m_rx_idx++] = data;
          if (m_rx_idx >= m_rx_len) {
            buf = m_rx_buf;
            m_rx_buf = NULL;
            signal HW.gps_receive_block_done(buf, m_rx_len, SUCCESS);
          }
        } else
          signal HW.gps_byte_avail(data);
        return;

      case MSP432U_IV_TXIFG:
        if (m_tx_buf == NULL) {
          /*
           * this will have the problem of TXIFG being down.
           * just panic to call attention to the issue.
           */
          call Usci.disableTxIntr();
          gps_panic(4, iv, 0);
          return;
        }

        data = m_tx_buf[m_tx_idx++];
        call Usci.setTxbuf(data);
        if (m_tx_idx >= m_tx_len) {
          buf = m_tx_buf;
          call Usci.disableTxIntr();
          m_tx_buf = NULL;
          signal HW.gps_send_block_done(buf, m_tx_len, SUCCESS);
        }
        return;

      case MSP432U_IV_NONE:
        break;

      default:
        gps_panic(5, iv, 0);
        break;
    }
  }

  async event void Panic.hook() { }
}
