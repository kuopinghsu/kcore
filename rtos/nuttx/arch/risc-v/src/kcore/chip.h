/****************************************************************************
 * arch/risc-v/src/kcore/chip.h
 *
 ****************************************************************************/

#ifndef __ARCH_RISCV_SRC_KCORE_CHIP_H
#define __ARCH_RISCV_SRC_KCORE_CHIP_H

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <nuttx/config.h>

#ifndef __ASSEMBLY__
#include <stdint.h>
#endif

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

/* KCORE Memory Map */

#define KCORE_MEM_BASE    0x80000000
#define KCORE_MEM_SIZE    0x00200000  /* 2MB */

/* KCORE Peripherals */

#define KCORE_UART0_BASE  0x10000000
#define KCORE_CLINT_BASE  0x02000000

/****************************************************************************
 * Public Function Prototypes
 ****************************************************************************/

#endif /* __ARCH_RISCV_SRC_KCORE_CHIP_H */
