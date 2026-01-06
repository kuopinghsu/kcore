/****************************************************************************
 * arch/risc-v/src/kcore/kcore_lowputc.c
 *
 ****************************************************************************/

#include <nuttx/config.h>
#include "chip.h"

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

#define UART_THR  0x00
#define UART_LSR  0x05
#define LSR_THRE  0x20

/****************************************************************************
 * Public Functions
 ****************************************************************************/

void up_putc(int ch)
{
#ifdef CONFIG_KCORE_UART0
  volatile uint8_t *uart = (uint8_t *)KCORE_UART0_BASE;
  
  /* Wait until THR is empty */
  while ((uart[UART_LSR] & LSR_THRE) == 0);
  
  /* Send character */
  uart[UART_THR] = ch;
#endif
}

void riscv_earlyserialinit(void)
{
  /* Early serial initialization - stub for now */
}

void riscv_serialinit(void)
{
  /* Serial initialization - stub for now */
}
