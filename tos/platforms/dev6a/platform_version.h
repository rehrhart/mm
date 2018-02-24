/*
 * Copyright 2014, 2017 (c) Eric B. Decker
 * All rights reserved.
 */

/*
 * define platform versioning and structures for representing it
 *
 *    8     8    16
 * major.minor.build
 *
 * build is an autogenerated value via make system.
 */

#ifndef _H_PLATFORM_VERSION_H
#define _H_PLATFORM_VERSION_H

#define MAJOR 0
#define MINOR 4

#define HW_MODEL 0xF0
#define HW_REV   1

#endif  // _H_PLATFORM_VERSION_H
