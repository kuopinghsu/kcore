/****************************************************************************
 * arch/risc-v/src/kcore/kcore_head.S
 *
 ****************************************************************************/

#include <nuttx/config.h>

    .section .text
    .global __start

__start:
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* Load stack pointer */
    la sp, _ebss
    addi sp, sp, CONFIG_IDLETHREAD_STACKSIZE

    /* Clear the BSS */
    la a0, _sbss
    la a1, _ebss
1:
    bge a0, a1, 2f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 1b
2:

    /* Jump to kcore_start */
    call kcore_start

    /* Should never return */
3:
    j 3b
