/****************************************************************************
 * arch/risc-v/src/kcore/kcore_allocateheap.c
 *
 ****************************************************************************/

#include <nuttx/config.h>
#include <nuttx/arch.h>
#include <nuttx/kmalloc.h>

#include "riscv_internal.h"

/****************************************************************************
 * Public Functions
 ****************************************************************************/

void up_allocate_heap(void **heap_start, size_t *heap_size)
{
  extern uint8_t _end[];   /* End of BSS and HTIF section */
  
  /* Use the entire RAM after BSS and HTIF as heap */

  *heap_start = (void *)_end;
  *heap_size  = (size_t)CONFIG_RAM_SIZE - ((size_t)_end - CONFIG_RAM_START);
}

#ifdef CONFIG_MM_KERNEL_HEAP
void up_allocate_kheap(void **heap_start, size_t *heap_size)
{
  /* For now, kernel heap is same as user heap */

  up_allocate_heap(heap_start, heap_size);
}
#endif
