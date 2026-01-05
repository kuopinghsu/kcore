/****************************************************************************
 * boards/risc-v/kcore/kcore-board/include/board.h
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

#ifndef __BOARDS_RISCV_KCORE_KCORE_BOARD_INCLUDE_BOARD_H
#define __BOARDS_RISCV_KCORE_KCORE_BOARD_INCLUDE_BOARD_H

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <nuttx/config.h>

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

/* CPU frequency */

#define BOARD_FREQ_HZ           50000000  /* 50 MHz */

/* Memory configuration */

#define KCORE_MEM_BASE          0x80000000
#define KCORE_MEM_SIZE          0x200000   /* 2 MB */

/* Peripheral base addresses */

#define KCORE_UART0_BASE        0x10000000
#define KCORE_CLINT_BASE        0x200bff8

/* UART configuration */

#define KCORE_UART0_IRQ         10
#define KCORE_UART0_BAUD        115200

/* Timer configuration */

#define KCORE_MTIMER_FREQ       BOARD_FREQ_HZ

/* LED definitions (if available) */

#define LED_STARTED             0
#define LED_HEAPALLOCATE        1
#define LED_IRQSENABLED         2
#define LED_STACKCREATED        3
#define LED_INIRQ               4
#define LED_SIGNAL              5
#define LED_ASSERTION           6
#define LED_PANIC               7

/****************************************************************************
 * Public Types
 ****************************************************************************/

#ifndef __ASSEMBLY__

/****************************************************************************
 * Public Data
 ****************************************************************************/

#undef EXTERN
#if defined(__cplusplus)
#define EXTERN extern "C"
extern "C"
{
#else
#define EXTERN extern
#endif

/****************************************************************************
 * Public Function Prototypes
 ****************************************************************************/

/****************************************************************************
 * Name: kcore_board_initialize
 *
 * Description:
 *   All kcore architectures must provide the following entry point.
 *   This entry point is called early in the initialization before any
 *   devices have been initialized.
 *
 ****************************************************************************/

void kcore_board_initialize(void);

#undef EXTERN
#if defined(__cplusplus)
}
#endif

#endif /* __ASSEMBLY__ */
#endif /* __BOARDS_RISCV_KCORE_KCORE_BOARD_INCLUDE_BOARD_H */
