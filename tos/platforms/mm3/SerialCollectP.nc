/*
 * mm3CollectP.nc - data collector (record managment) interface
 * between data collection and mass storage.
 * Copyright 2008, Eric B. Decker
 * Mam-Mark Project
 *
 */

#include "Collect.h"
#include "collect_msg.h"

module SerialCollectP {
  provides {
    interface Collect;
    interface Init;
  }
  uses {
    interface AMSend as SerialSend;
    interface Packet as SerialPacket;
    interface AMPacket as SerialAMPacket;
  }
}

implementation {
  #define SERIAL_COLLECT_BUFFER_SIZE	512

  enum {
    S_STARTED,
    S_STOPPED,
    S_FLUSHING,
  };
  
  message_t collectMsg;
  nx_uint8_t buffer[SERIAL_COLLECT_BUFFER_SIZE];
  uint8_t state = S_STOPPED;
  norace nx_uint8_t* next_byte;
  uint32_t bytes_left_to_flush;
  uint8_t length_to_send;  
  
  int putchar(uint8_t c);
  error_t flush();

  command error_t Init.init() {
    atomic {
      memset(buffer, 0, sizeof(buffer));
      next_byte = buffer;
      bytes_left_to_flush = 0; 
      length_to_send = 0;
      state = S_STARTED;
    }
    return SUCCESS;
  }

  command void Collect.collect(uint8_t *data, uint16_t dlen) {
    int i;
    for(i = 0; i < dlen; i++) {
      putchar(data[i]);
    }
    flush();
  }
  
  task void retrySend() {
    if(call SerialSend.send(AM_BROADCAST_ADDR, &collectMsg, sizeof(collect_msg_t)) != SUCCESS)
      post retrySend();
  }
  
  void sendNext() {
    collect_msg_t* m = (collect_msg_t*)call SerialPacket.getPayload(&collectMsg, sizeof(collect_msg_t));
    length_to_send = (bytes_left_to_flush < sizeof(collect_msg_t)) ? bytes_left_to_flush : sizeof(collect_msg_t);
    memset(m->buffer, 0, sizeof(collect_msg_t));
    memcpy(m->buffer, (nx_uint8_t*)next_byte, length_to_send);
    if(call SerialSend.send(AM_BROADCAST_ADDR, &collectMsg, sizeof(collect_msg_t)) != SUCCESS)
      post retrySend();  
    else {
      bytes_left_to_flush -= length_to_send;
      next_byte += length_to_send;
    }
  }
    
  event void SerialSend.sendDone(message_t* msg, error_t error) {    
    if(error == SUCCESS) {
      if(bytes_left_to_flush > 0)
        sendNext();
      else {
        next_byte = buffer;
        bytes_left_to_flush = 0; 
        length_to_send = 0;
        atomic state = S_STARTED;
      }
    }
    else post retrySend();
  }
  
  int putchar(uint8_t c) {
    atomic {
      if(state == S_STARTED && ((next_byte-buffer) < SERIAL_COLLECT_BUFFER_SIZE)) {
        *(next_byte++) = c;
        return 0;
      }
      else return -1;
    }
  }
  
  error_t flush() {
    atomic {
      if(state == S_STARTED && (next_byte > buffer)) {
        state = S_FLUSHING;
        bytes_left_to_flush = next_byte - buffer;
        next_byte = buffer;
      }
      else return FAIL;
    }
    sendNext();
    return SUCCESS;
  }
  
}
