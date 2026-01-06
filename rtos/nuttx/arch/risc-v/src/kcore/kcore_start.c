/****************************************************************************
 * arch/risc-v/src/kcore/kcore_start.c
 *
 ****************************************************************************/

#include <nuttx/config.h>
#include <nuttx/init.h>
#include <arch/board/board.h>

#include "riscv_internal.h"

/****************************************************************************
 * Public Functions
 ****************************************************************************/

void kcore_start(void)
{
  /* Copy .data from flash to RAM */

  const uint32_t *src = (const uint32_t *)&_eronly;
  uint32_t *dest = (uint32_t *)&_sdata;

  /* Copy .data from flash to RAM */

  while (dest < (uint32_t *)&_edata)
    {
      *dest++ = *src++;
    }

  /* Clear .bss */

  dest = (uint32_t *)&_sbss;
  while (dest < (uint32_t *)&_ebss)
    {
      *dest++ = 0;
    }

  /* Configure the UART before we do anything else */

#ifdef USE_EARLYSERIALINIT
  riscv_earlyserialinit();
#endif

  /* Perform board initialization */

  nx_start();
}
