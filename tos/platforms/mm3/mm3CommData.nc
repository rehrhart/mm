/*
 * Copyright (c) 2008, Eric B. Decker
 * All rights reserved.
 */

interface mm3CommData {
  command error_t send_data(void *buf, uint8_t buf_len);
  event void send_data_done(error_t rtn);
}
