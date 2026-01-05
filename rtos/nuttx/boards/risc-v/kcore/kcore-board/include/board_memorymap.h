/****************************************************************************
 * boards/risc-v/kcore/kcore-board/include/board_memorymap.h
 *
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.  The
 * ASF licenses this file to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
 * License for the specific language governing permissions and limitations
 * under the License.
 *
 ****************************************************************************/

#ifndef __BOARDS_RISCV_KCORE_KCORE_BOARD_INCLUDE_BOARD_MEMORYMAP_H
#define __BOARDS_RISCV_KCORE_KCORE_BOARD_INCLUDE_BOARD_MEMORYMAP_H

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <nuttx/config.h>

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

/* Kernel flash and RAM regions */

#define KFLASH_START_PADDR  0x80000000
#define KFLASH_SIZE         (64 * 1024)

#define KSRAM_START_PADDR   0x80000000
#define KSRAM_SIZE          (64 * 1024)

/* Kernel RAM start and end */

#define KRAM_START          KSRAM_START_PADDR
#define KRAM_END            (KSRAM_START_PADDR + KSRAM_SIZE)

/* Page pool */

#define PGPOOL_START        (KRAM_END)
#define PGPOOL_END          (KRAM_END)
#define PGPOOL_SIZE         (PGPOOL_END - PGPOOL_START)

/* ramdisk (not used) */

#define RAMDISK_START       (KFLASH_START_PADDR)
#define RAMDISK_SIZE        0

#endif /* __BOARDS_RISCV_KCORE_KCORE_BOARD_INCLUDE_BOARD_MEMORYMAP_H */
