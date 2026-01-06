/****************************************************************************
 * arch/risc-v/include/kcore/irq.h
 *
 * Copyright (c) 2026 kcore Project
 * SPDX-License-Identifier: Apache-2.0
 *
 ****************************************************************************/

#ifndef __ARCH_RISCV_INCLUDE_KCORE_IRQ_H
#define __ARCH_RISCV_INCLUDE_KCORE_IRQ_H

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <arch/irq.h>

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

/* IRQ numbers */
#define KCORE_IRQ_UART0  10

/* Total number of IRQs */
#define NR_IRQS          16

#endif /* __ARCH_RISCV_INCLUDE_KCORE_IRQ_H */
