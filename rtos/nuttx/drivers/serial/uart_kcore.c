/****************************************************************************
 * drivers/serial/uart_kcore.c
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

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <nuttx/config.h>

#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <debug.h>

#include <nuttx/irq.h>
#include <nuttx/arch.h>
#include <nuttx/serial/serial.h>
#include <arch/board/board.h>

#ifdef CONFIG_KCORE_UART0

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

/* UART register offsets */

#define UART_TXDATA_OFFSET  0x00
#define UART_RXDATA_OFFSET  0x04
#define UART_STATUS_OFFSET  0x08
#define UART_CONTROL_OFFSET 0x0C

/* UART status bits */

#define UART_STATUS_TXFULL  (1 << 0)
#define UART_STATUS_RXEMPTY (1 << 1)

/* UART control bits */

#define UART_CONTROL_TXEN   (1 << 0)
#define UART_CONTROL_RXEN   (1 << 1)
#define UART_CONTROL_TXIE   (1 << 2)
#define UART_CONTROL_RXIE   (1 << 3)

/****************************************************************************
 * Private Types
 ****************************************************************************/

struct kcore_uart_s
{
  uint32_t uartbase;    /* Base address of UART registers */
  uint32_t baud;        /* Configured baud rate */
  uint8_t  irq;         /* IRQ associated with this UART */
  uint8_t  parity;      /* 0=none, 1=odd, 2=even */
  uint8_t  bits;        /* Number of bits (7 or 8) */
  bool     stopbits2;   /* true: 2 stop bits, false: 1 stop bit */
};

/****************************************************************************
 * Private Function Prototypes
 ****************************************************************************/

static int  kcore_uart_setup(struct uart_dev_s *dev);
static void kcore_uart_shutdown(struct uart_dev_s *dev);
static int  kcore_uart_attach(struct uart_dev_s *dev);
static void kcore_uart_detach(struct uart_dev_s *dev);
static int  kcore_uart_interrupt(int irq, void *context, void *arg);
static int  kcore_uart_ioctl(struct file *filep, int cmd, unsigned long arg);
static int  kcore_uart_receive(struct uart_dev_s *dev, unsigned int *status);
static void kcore_uart_rxint(struct uart_dev_s *dev, bool enable);
static bool kcore_uart_rxavailable(struct uart_dev_s *dev);
static void kcore_uart_send(struct uart_dev_s *dev, int ch);
static void kcore_uart_txint(struct uart_dev_s *dev, bool enable);
static bool kcore_uart_txready(struct uart_dev_s *dev);
static bool kcore_uart_txempty(struct uart_dev_s *dev);

/****************************************************************************
 * Private Data
 ****************************************************************************/

static const struct uart_ops_s g_uart_ops =
{
  .setup          = kcore_uart_setup,
  .shutdown       = kcore_uart_shutdown,
  .attach         = kcore_uart_attach,
  .detach         = kcore_uart_detach,
  .ioctl          = kcore_uart_ioctl,
  .receive        = kcore_uart_receive,
  .rxint          = kcore_uart_rxint,
  .rxavailable    = kcore_uart_rxavailable,
#ifdef CONFIG_SERIAL_IFLOWCONTROL
  .rxflowcontrol  = NULL,
#endif
  .send           = kcore_uart_send,
  .txint          = kcore_uart_txint,
  .txready        = kcore_uart_txready,
  .txempty        = kcore_uart_txempty,
};

/* UART0 device structure */

static struct kcore_uart_s g_uart0priv =
{
  .uartbase = KCORE_UART0_BASE,
  .baud     = KCORE_UART0_BAUD,
  .irq      = KCORE_UART0_IRQ,
  .parity   = 0,
  .bits     = 8,
  .stopbits2 = false,
};

static uart_dev_t g_uart0port =
{
  .recv =
  {
    .size   = CONFIG_UART0_RXBUFSIZE,
    .buffer = g_uart0rxbuffer,
  },
  .xmit =
  {
    .size   = CONFIG_UART0_TXBUFSIZE,
    .buffer = g_uart0txbuffer,
  },
  .ops  = &g_uart_ops,
  .priv = &g_uart0priv,
};

/* Receive and transmit buffers */

static char g_uart0rxbuffer[CONFIG_UART0_RXBUFSIZE];
static char g_uart0txbuffer[CONFIG_UART0_TXBUFSIZE];

/****************************************************************************
 * Private Functions
 ****************************************************************************/

/****************************************************************************
 * Name: kcore_uart_getreg
 ****************************************************************************/

static inline uint32_t kcore_uart_getreg(struct kcore_uart_s *priv,
                                          uint32_t offset)
{
  return *(volatile uint32_t *)(priv->uartbase + offset);
}

/****************************************************************************
 * Name: kcore_uart_putreg
 ****************************************************************************/

static inline void kcore_uart_putreg(struct kcore_uart_s *priv,
                                      uint32_t offset, uint32_t value)
{
  *(volatile uint32_t *)(priv->uartbase + offset) = value;
}

/****************************************************************************
 * Name: kcore_uart_setup
 ****************************************************************************/

static int kcore_uart_setup(struct uart_dev_s *dev)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;

  /* Enable TX and RX */

  kcore_uart_putreg(priv, UART_CONTROL_OFFSET,
                    UART_CONTROL_TXEN | UART_CONTROL_RXEN);

  return OK;
}

/****************************************************************************
 * Name: kcore_uart_shutdown
 ****************************************************************************/

static void kcore_uart_shutdown(struct uart_dev_s *dev)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;

  /* Disable TX and RX */

  kcore_uart_putreg(priv, UART_CONTROL_OFFSET, 0);
}

/****************************************************************************
 * Name: kcore_uart_attach
 ****************************************************************************/

static int kcore_uart_attach(struct uart_dev_s *dev)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  int ret;

  /* Attach the IRQ */

  ret = irq_attach(priv->irq, kcore_uart_interrupt, dev);
  if (ret == OK)
    {
      /* Enable the interrupt */

      up_enable_irq(priv->irq);
    }

  return ret;
}

/****************************************************************************
 * Name: kcore_uart_detach
 ****************************************************************************/

static void kcore_uart_detach(struct uart_dev_s *dev)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;

  /* Disable the interrupt */

  up_disable_irq(priv->irq);

  /* Detach the IRQ */

  irq_detach(priv->irq);
}

/****************************************************************************
 * Name: kcore_uart_interrupt
 ****************************************************************************/

static int kcore_uart_interrupt(int irq, void *context, void *arg)
{
  struct uart_dev_s *dev = (struct uart_dev_s *)arg;
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  uint32_t status;

  /* Get UART status */

  status = kcore_uart_getreg(priv, UART_STATUS_OFFSET);

  /* Check for received data */

  if ((status & UART_STATUS_RXEMPTY) == 0)
    {
      uart_recvchars(dev);
    }

  /* Check for transmit ready */

  if ((status & UART_STATUS_TXFULL) == 0)
    {
      uart_xmitchars(dev);
    }

  return OK;
}

/****************************************************************************
 * Name: kcore_uart_ioctl
 ****************************************************************************/

static int kcore_uart_ioctl(struct file *filep, int cmd, unsigned long arg)
{
  return -ENOTTY;
}

/****************************************************************************
 * Name: kcore_uart_receive
 ****************************************************************************/

static int kcore_uart_receive(struct uart_dev_s *dev, unsigned int *status)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  uint32_t rxdata;

  /* Read receive data register */

  rxdata = kcore_uart_getreg(priv, UART_RXDATA_OFFSET);

  /* Return status (no errors for now) */

  *status = 0;

  /* Return received character */

  return (int)(rxdata & 0xff);
}

/****************************************************************************
 * Name: kcore_uart_rxint
 ****************************************************************************/

static void kcore_uart_rxint(struct uart_dev_s *dev, bool enable)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  uint32_t ctrl;

  ctrl = kcore_uart_getreg(priv, UART_CONTROL_OFFSET);

  if (enable)
    {
      ctrl |= UART_CONTROL_RXIE;
    }
  else
    {
      ctrl &= ~UART_CONTROL_RXIE;
    }

  kcore_uart_putreg(priv, UART_CONTROL_OFFSET, ctrl);
}

/****************************************************************************
 * Name: kcore_uart_rxavailable
 ****************************************************************************/

static bool kcore_uart_rxavailable(struct uart_dev_s *dev)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  uint32_t status;

  status = kcore_uart_getreg(priv, UART_STATUS_OFFSET);

  return (status & UART_STATUS_RXEMPTY) == 0;
}

/****************************************************************************
 * Name: kcore_uart_send
 ****************************************************************************/

static void kcore_uart_send(struct uart_dev_s *dev, int ch)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;

  /* Write to transmit data register */

  kcore_uart_putreg(priv, UART_TXDATA_OFFSET, (uint32_t)ch);
}

/****************************************************************************
 * Name: kcore_uart_txint
 ****************************************************************************/

static void kcore_uart_txint(struct uart_dev_s *dev, bool enable)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  uint32_t ctrl;

  ctrl = kcore_uart_getreg(priv, UART_CONTROL_OFFSET);

  if (enable)
    {
      ctrl |= UART_CONTROL_TXIE;
    }
  else
    {
      ctrl &= ~UART_CONTROL_TXIE;
    }

  kcore_uart_putreg(priv, UART_CONTROL_OFFSET, ctrl);
}

/****************************************************************************
 * Name: kcore_uart_txready
 ****************************************************************************/

static bool kcore_uart_txready(struct uart_dev_s *dev)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  uint32_t status;

  status = kcore_uart_getreg(priv, UART_STATUS_OFFSET);

  return (status & UART_STATUS_TXFULL) == 0;
}

/****************************************************************************
 * Name: kcore_uart_txempty
 ****************************************************************************/

static bool kcore_uart_txempty(struct uart_dev_s *dev)
{
  struct kcore_uart_s *priv = (struct kcore_uart_s *)dev->priv;
  uint32_t status;

  status = kcore_uart_getreg(priv, UART_STATUS_OFFSET);

  return (status & UART_STATUS_TXFULL) == 0;
}

/****************************************************************************
 * Public Functions
 ****************************************************************************/

/****************************************************************************
 * Name: riscv_earlyserialinit
 *
 * Description:
 *   Performs the low level UART initialization early in debug so that the
 *   serial console will be available during bootup.  This must be called
 *   before riscv_serialinit.
 *
 ****************************************************************************/

void riscv_earlyserialinit(void)
{
  /* Configure UART0 */

  kcore_uart_setup(&g_uart0port);

  /* Register the console */

#ifdef CONFIG_UART0_SERIAL_CONSOLE
  uart_register("/dev/console", &g_uart0port);
#endif
}

/****************************************************************************
 * Name: riscv_serialinit
 *
 * Description:
 *   Register serial console and serial ports.  This assumes that
 *   riscv_earlyserialinit was called previously.
 *
 ****************************************************************************/

void riscv_serialinit(void)
{
  /* Register UART0 as /dev/ttyS0 */

  uart_register("/dev/ttyS0", &g_uart0port);
}

/****************************************************************************
 * Name: up_putc
 *
 * Description:
 *   Provide priority, low-level access to support OS debug writes
 *
 ****************************************************************************/

int up_putc(int ch)
{
  struct kcore_uart_s *priv = &g_uart0priv;
  uint32_t status;

  /* Wait for TX not full */

  do
    {
      status = kcore_uart_getreg(priv, UART_STATUS_OFFSET);
    }
  while (status & UART_STATUS_TXFULL);

  /* Send character */

  kcore_uart_putreg(priv, UART_TXDATA_OFFSET, (uint32_t)ch);

  return ch;
}

#endif /* CONFIG_KCORE_UART0 */
