/****************************************************************************
 * arch/risc-v/src/kcore/kcore_timerisr.c
 *
 ****************************************************************************/

#include <nuttx/config.h>
#include <nuttx/arch.h>
#include <nuttx/clock.h>

#include "riscv_internal.h"
#include "chip.h"

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

#define KCORE_CLINT_MTIME    (KCORE_CLINT_BASE + 0x0)
#define KCORE_CLINT_MTIMECMP (KCORE_CLINT_BASE + 0x8)

#define TICK_COUNT (10000000 / TICK_PER_SEC)

/****************************************************************************
 * Private Functions
 ****************************************************************************/

static int kcore_timerisr(int irq, void *context, void *arg)
{
  /* Set next timer interrupt */

  volatile uint64_t *mtimecmp = (uint64_t *)KCORE_CLINT_MTIMECMP;
  *mtimecmp += TICK_COUNT;

  /* Process timer interrupt */

  nxsched_process_timer();
  return 0;
}

/****************************************************************************
 * Public Functions
 ****************************************************************************/

void up_timer_initialize(void)
{
  /* Attach timer interrupt handler */

  irq_attach(RISCV_IRQ_MTIMER, kcore_timerisr, NULL);

  /* Enable timer interrupt */

  up_enable_irq(RISCV_IRQ_MTIMER);

  /* Set initial timer */

  volatile uint64_t *mtime = (uint64_t *)KCORE_CLINT_MTIME;
  volatile uint64_t *mtimecmp = (uint64_t *)KCORE_CLINT_MTIMECMP;
  *mtimecmp = *mtime + TICK_COUNT;
}
