/****************************************************************************
 * arch/risc-v/src/kcore/kcore_irq.c
 *
 ****************************************************************************/

#include <nuttx/config.h>
#include <nuttx/arch.h>

#include "riscv_internal.h"

/****************************************************************************
 * Public Functions
 ****************************************************************************/

void up_irqinitialize(void)
{
  /* Disable all interrupts */

  up_irq_save();

  /* Attach the ecall interrupt handler */

  riscv_exception_attach();

#ifndef CONFIG_SUPPRESS_INTERRUPTS
  up_irq_enable();
#endif
}

irqstate_t up_irq_enable(void)
{
  irqstate_t oldstat;

  /* Read and enable global interrupts */

  __asm__ __volatile__
    (
      "csrrsi %0, mstatus, 8\n"
      : "=r" (oldstat)
      :
      : "memory"
    );

  return oldstat;
}

void up_enable_irq(int irq)
{
  /* Enable the specified IRQ */
  
  irqstate_t flags = up_irq_save();
  
  if (irq < NR_IRQS)
    {
      /* For now, just enable machine external interrupts */
      
      uint32_t mie;
      __asm__ __volatile__
        (
          "csrrs %0, mie, %1\n"
          : "=r" (mie)
          : "r" (1 << irq)
          : "memory"
        );
    }
  
  up_irq_restore(flags);
}

void up_disable_irq(int irq)
{
  /* Disable the specified IRQ */
  
  irqstate_t flags = up_irq_save();
  
  if (irq < NR_IRQS)
    {
      /* Disable the specified interrupt bit in MIE */
      
      uint32_t mie;
      __asm__ __volatile__
        (
          "csrrc %0, mie, %1\n"
          : "=r" (mie)
          : "r" (1 << irq)
          : "memory"
        );
    }
  
  up_irq_restore(flags);
}
