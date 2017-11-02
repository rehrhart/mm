/**
 * Copyright (c) 2008, 2010, Eric Decker
 * All rights reserved.
 */

/**
 * @author Eric Decker
 */

#include "stream_storage.h"

interface SSWrite {
  /*
   * StreamStorage provides an interface to sector orientated 512 byte
   * stream storage devices.  Data is accessed as blocks of 512 bytes.
   * A stream of 512 byte blocks is written to the stream device.
   *
   * Note the actual size of the buffer is 514 because it includes
   * space for a 16 bit CRC.  The client shouldn't count on this and
   * this should be opaque to the client.
   */

  /**
   * Convert a stream buf_handle to its underlying buffer.
   *
   * @param buf_handle address of a ss_buf_handle (stream storage buf_handle).
   * @return
   *   <li>NULL   if bad buf_handle or buffer not allocated.
   *   <li>buffer if good buf_handle.
   */
  command uint8_t *buf_handle_to_buf(ss_wr_buf_t *buf_handle);


  /*
   * get_temp_buf provides a mechanism where a client can ask for space
   * controlled by SSWrite to use on a temporary basis.  It is assumed
   * that this occurs while booting and before SSWrite is active.
   *
   * This routine should not be used after the boot sequence completes.
   * Temp buffers can also be used after we've crashed.
   *
   * The important thing is the system is single threaded.
   */
  async command uint8_t *get_temp_buf();


  /**
   * request a new buffer from the Stream Storage system.
   *
   * @return
   *   <li>NULL   if no buffer available.
   *   <li>buf_handle if buffer available.  Buffer marked allocated.
   */
  command ss_wr_buf_t* get_free_buf_handle();

  /**
   * call when the buffer objectified by buf_handle has been filled and
   * should be flushed.  The handle is then returned to the free pool.  Do
   * not use the buffer or the buffer handle after calling buffer_full.
   *
   * @param buf_handle address of the ss_buf_handle ready to be flushed.
   */
  command void buffer_full(ss_wr_buf_t *buf_handle);

  /**
   * call when Collect has been kicked by a SysReboot.shutdown_flush to
   * force SSW to flush to disk any pending buffers.
   *
   * Needs to be async, called from the Panic context.
   */
  async command void flush_all();
}
