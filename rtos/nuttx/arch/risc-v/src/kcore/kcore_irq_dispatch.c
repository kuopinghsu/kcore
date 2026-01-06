/****************************************************************************
 * arch/risc-v/src/kcore/kcore_irq_dispatch.c
 *
 ****************************************************************************/

#include <nuttx/config.h>
#include <nuttx/arch.h>

#include "riscv_internal.h"

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

#define RV_IRQ_MASK 27

/****************************************************************************
 * Public Functions
 ****************************************************************************/

void *riscv_dispatch_irq(uintptr_t vector, uintptr_t *regs)
{
  int irq = (vector >> RV_IRQ_MASK) | (vector & 0xf);

  /* Acknowledge the interrupt */

  riscv_ack_irq(irq);

  /* Deliver the IRQ */

  regs = (uintptr_t *)riscv_doirq(irq, (uintreg_t *)regs);

  return regs;
}
