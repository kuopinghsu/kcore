# NuttX Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    NuttX Applications                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Hello World  │  │  NuttShell   │  │ Custom Apps  │       │
│  │   (hello)    │  │    (NSH)     │  │              │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    NuttX RTOS Kernel                        │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐             │
│  │  Scheduler │  │   Memory   │  │    IPC     │             │
│  │            │  │ Management │  │            │             │
│  └────────────┘  └────────────┘  └────────────┘             │
│                                                             │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐             │
│  │   VFS      │  │   Timers   │  │  Signals   │             │
│  │            │  │            │  │            │             │
│  └────────────┘  └────────────┘  └────────────┘             │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Device Drivers                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │             Serial Driver (uart_kcore.c)             │   │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────┐              │   │
│  │  │  TX/RX  │  │  Buffers│  │Interrupts│              │   │
│  │  └─────────┘  └─────────┘  └──────────┘              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 Board Support Package                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │        kcore-board BSP (boards/.../kcore-board/)     │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐               │   │
│  │  │  Init   │  │ Memory  │  │ Config  │               │   │
│  │  │  Code   │  │   Map   │  │ Files   │               │   │
│  │  └─────────┘  └─────────┘  └─────────┘               │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Hardware (kcore SoC)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   RISC-V     │  │     UART0    │  │    CLINT     │       │
│  │   RV32IMA    │  │  0x10000000  │  │  0x200bff8   │       │
│  │   Pipeline   │  │              │  │   (Timer)    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              2MB RAM @ 0x80000000                    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Build Flow

```
┌──────────────┐
│ Make Target  │
│ nuttx-hello  │
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 1. Check NuttX Installation          │
│    - Verify NUTTX_BASE exists        │
│    - Verify NUTTX_APPS exists        │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 2. Copy Board Files                  │
│    - kcore-board → NuttX tree        │
│    - Kconfig, defconfig, scripts     │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 3. Copy Driver Files                 │
│    - uart_kcore.c → drivers/serial   │
│    - Update Make.defs                │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 4. Copy Application                  │
│    - hello_main.c → apps/examples    │
│    - Makefile                        │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 5. Configure NuttX                   │
│    - Run configure.sh kcore-board:nsh│
│    - Apply defconfig                 │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 6. Build NuttX                       │
│    - make -j$(nproc)                 │
│    - Link with apps                  │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 7. Generate Output Files             │
│    - test.elf (executable)           │
│    - test.dump (disassembly)         │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────┐
│ Build        │
│ Complete     │
└──────────────┘
```

## Execution Flow

```
┌───────────────┐
│ Make Target   │
│nuttx-rtl-hello│
└──────┬────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 1. Build NuttX (if needed)           │
│    make nuttx-hello                  │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 2. Build Verilator RTL Sim           │
│    rtl-verilator-build               │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 3. Run Verilator Simulation          │
│    Vtb_soc test.elf ...              │
│    - Load binary to memory           │
│    - Execute instructions            │
│    - Capture UART output             │
│    - Generate traces (optional)      │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 4. Display Results                   │
│    - Console output from UART        │
│    - Execution statistics            │
│    - Waveform location (if enabled)  │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────┐
│ Simulation   │
│ Complete     │
└──────────────┘
```

## Memory Layout

```
0x80000000  ┌──────────────────────────────┐
            │        .text (code)          │  Program code
            │                              │  Startup code
            │                              │  NuttX kernel
            │                              │  Applications
            ├──────────────────────────────┤
            │      .rodata (const)         │  Read-only data
            │                              │  String literals
            │                              │  Const arrays
            ├──────────────────────────────┤
            │      .data (initialized)     │  Initialized data
            │                              │  Global variables
            │                              │  Static variables
            ├──────────────────────────────┤
            │      .bss (zero-init)        │  Zero-initialized
            │                              │  Uninitialized globals
            ├──────────────────────────────┤
            │         Heap                 │  Dynamic allocation
            │          ↓                   │  (grows downward)
            │                              │
            │          ...                 │
            │                              │
            │          ↑                   │
            │         Stack                │  Call stack
            │                              │  (grows upward)
0x801FFFFF  └──────────────────────────────┘
            
            Total: 2 MB RAM
```

## UART Register Interface

```
Base: 0x10000000

┌─────────────┬────────┬─────────────────────────────┐
│   Offset    │  Name  │        Description          │
├─────────────┼────────┼─────────────────────────────┤
│ 0x00        │ TXDATA │ Transmit Data Register      │
│             │        │ Write: Send byte            │
├─────────────┼────────┼─────────────────────────────┤
│ 0x04        │ RXDATA │ Receive Data Register       │
│             │        │ Read: Get received byte     │
├─────────────┼────────┼─────────────────────────────┤
│ 0x08        │ STATUS │ Status Register             │
│             │        │ Bit 0: TX Full              │
│             │        │ Bit 1: RX Empty             │
├─────────────┼────────┼─────────────────────────────┤
│ 0x0C        │CONTROL │ Control Register            │
│             │        │ Bit 0: TX Enable            │
│             │        │ Bit 1: RX Enable            │
│             │        │ Bit 2: TX Interrupt Enable  │
│             │        │ Bit 3: RX Interrupt Enable  │
└─────────────┴────────┴─────────────────────────────┘
```

## Files Created

### Board Support Package
```
boards/risc-v/kcore/kcore-board/
├── Kconfig                      # Kconfig options
├── configs/nsh/defconfig        # Default configuration
├── include/
│   ├── board.h                  # Board definitions
│   └── board_memorymap.h        # Memory layout
├── scripts/ld.script            # Linker script
└── src/
    ├── Makefile                 # Build rules
    ├── kcore_boot.c             # Boot initialization
    └── kcore_appinit.c          # App initialization
```

### Drivers
```
drivers/serial/
├── Make.defs                    # Makefile fragment
└── uart_kcore.c                 # UART driver (~600 lines)
```

### Applications
```
samples/
├── hello/
│   ├── Makefile
│   └── hello_main.c             # Hello world app
└── nsh/
    └── README.md                # NSH documentation
```

### Documentation
```
docs/
└── nuttx_integration.md         # Comprehensive guide

rtos/nuttx/
├── README.md                    # Main README
├── QUICKSTART.md                # Quick start guide
└── ARCHITECTURE.md              # This file
```
