# NuttX RTOS Integration for kcore

## Overview

NuttX RTOS has been successfully integrated into the kcore RISC-V processor project with full support for:
- Custom board support package (BSP) for kcore-board
- UART serial driver for console I/O
- Hello World sample application
- NuttShell (NSH) command-line interface
- RTL simulation, C++ simulation, and trace comparison

## Directory Structure

```
rtos/nuttx/
├── README.md                           # Main documentation
├── module.yml                          # NuttX module configuration
├── boards/                             # Board support
│   └── risc-v/kcore/kcore-board/
│       ├── Kconfig                     # Board Kconfig options
│       ├── include/
│       │   ├── board.h                 # Board definitions
│       │   └── board_memorymap.h       # Memory map
│       ├── scripts/
│       │   └── ld.script               # Linker script
│       ├── src/
│       │   ├── Makefile                # Board source makefile
│       │   ├── kcore_boot.c            # Board initialization
│       │   └── kcore_appinit.c         # Application initialization
│       └── configs/
│           └── nsh/
│               └── defconfig           # NSH default configuration
├── drivers/                            # Custom drivers
│   └── serial/
│       ├── Make.defs                   # Driver makefile fragment
│       └── uart_kcore.c                # UART driver implementation
└── samples/                            # Sample applications
    ├── hello/
    │   ├── Makefile                    # Hello sample makefile
    │   └── hello_main.c                # Hello world application
    └── nsh/
        └── README.md                   # NSH documentation
```

## Hardware Configuration

### Memory Map
- **RAM**: 0x80000000 - 0x8000FFFF (64 KB)
- **UART0**: 0x10000000
- **CLINT**: 0x200BFF8 (timer)

### Processor
- **Architecture**: RV32IMA with Zicsr and Zifencei extensions
- **Frequency**: 50 MHz
- **ABI**: ilp32

### UART Configuration
- **Base Address**: 0x10000000
- **Baud Rate**: 115200
- **Data Bits**: 8
- **Parity**: None
- **Stop Bits**: 1
- **IRQ**: 10

## Installation

### 1. Install NuttX

```bash
# Create NuttX directory
mkdir -p ~/NuttX
cd ~/NuttX

# Clone NuttX and apps repositories
git clone https://github.com/apache/nuttx.git nuttx
git clone https://github.com/apache/nuttx-apps.git apps
```

### 2. Set Environment Variables (Optional)

If NuttX is installed in a different location:

```bash
export NUTTX_BASE=/path/to/nuttx
export NUTTX_APPS=/path/to/nuttx-apps
```

### 3. Install kconfig-frontends (macOS)

```bash
brew install kconfig-frontends
```

## Building Applications

### Hello World

```bash
# Build NuttX with hello world
make nuttx-hello

# Run in RTL simulation
make nuttx-rtl-hello

# Run in C++ simulation
make nuttx-sim-hello

# Compare RTL vs C++ traces
make nuttx-compare-hello
```

### NuttShell (NSH)

```bash
# Build NuttX with NSH (uses same build as hello)
make nuttx-nsh

# Run in RTL simulation
make nuttx-rtl-nsh

# Run in C++ simulation
make nuttx-sim-nsh

# Compare traces
make nuttx-compare-nsh
```

### With Debug Options

```bash
# Enable instruction tracing
make nuttx-rtl-hello TRACE=1

# Enable waveform dump (FST format)
make nuttx-rtl-hello WAVE=fst

# Enable memory transaction logging
make nuttx-rtl-hello MEMTRACE=1

# Combine options
make nuttx-rtl-hello TRACE=1 WAVE=fst MEMTRACE=1
```

## Build Process

The build process performs these steps:

1. **Check NuttX Installation**: Verifies NUTTX_BASE and NUTTX_APPS exist
2. **Copy Board Files**: Copies kcore-board BSP to NuttX tree
3. **Copy Drivers**: Copies UART driver to NuttX drivers directory
4. **Copy Samples**: Copies hello sample to NuttX apps
5. **Configure**: Runs `./tools/configure.sh kcore-board:nsh`
6. **Build**: Compiles NuttX with `make -j$(nproc)`
7. **Convert**: Creates binary, hex, and dump files
8. **Report**: Shows memory usage with `size`

## Driver Implementation

### UART Driver (uart_kcore.c)

The UART driver implements the NuttX serial driver interface:

**Features:**
- Memory-mapped register access
- Interrupt-driven I/O
- Transmit and receive buffers (configurable)
- Status checking (TX full, RX empty)
- Early console support for boot messages

**Register Map:**
- `0x00`: TXDATA - Transmit data register
- `0x04`: RXDATA - Receive data register
- `0x08`: STATUS - Status register (TXFULL, RXEMPTY)
- `0x0C`: CONTROL - Control register (TXEN, RXEN, TXIE, RXIE)

**Functions Implemented:**
- `kcore_uart_setup()` - Initialize UART
- `kcore_uart_send()` - Send character
- `kcore_uart_receive()` - Receive character
- `kcore_uart_rxavailable()` - Check if data available
- `kcore_uart_txready()` - Check if TX ready
- `up_putc()` - Low-level character output for debugging

## Board Configuration

### defconfig Options

Key configuration options in [configs/nsh/defconfig](rtos/nuttx/boards/risc-v/kcore/kcore-board/configs/nsh/defconfig):

```
CONFIG_ARCH_RISCV=y
CONFIG_ARCH_RV32=y
CONFIG_ARCH_RV_ISA_A=y
CONFIG_ARCH_RV_ISA_M=y
CONFIG_RAM_START=0x80000000
CONFIG_RAM_SIZE=65536
CONFIG_SERIAL=y
CONFIG_UART0_SERIAL_CONSOLE=y
CONFIG_UART0_BAUD=115200
CONFIG_KCORE_UART0=y
CONFIG_NSH_LIBRARY=y
CONFIG_EXAMPLES_HELLO=y
```

### Customizing Configuration

After initial build, you can customize:

```bash
cd ~/NuttX/nuttx
make menuconfig
make savedefconfig
```

Copy the new defconfig to preserve changes:
```bash
cp defconfig ~/Projects/kcore/rtos/nuttx/boards/risc-v/kcore/kcore-board/configs/nsh/
```

## Sample Applications

### Hello World

Simple application that prints greetings and system information:

```c
int main(int argc, FAR char *argv[])
{
  printf("Hello, World from NuttX on kcore!\n");
  printf("RISC-V RV32IMA processor\n");
  printf("NuttX RTOS successfully running\n");
  return 0;
}
```

### NuttShell (NSH)

Interactive command shell with built-in commands:
- `help` - Show available commands
- `ls` - List directory contents
- `free` - Show memory usage
- `ps` - Show processes
- `uname` - System information
- And many more...

## Simulation Results

After running `make nuttx-rtl-hello`, you should see output like:

```
=== Running NuttX hello in RTL simulation ===
Hello, World from NuttX on kcore!
RISC-V RV32IMA processor
NuttX RTOS successfully running
=== NuttX RTL simulation completed ===
```

## Trace Comparison

The `nuttx-compare-hello` target compares RTL and C++ simulation traces to verify correct execution:

```bash
make nuttx-compare-hello
```

This ensures both simulations produce identical results.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `nuttx-hello` | Build NuttX with hello world |
| `nuttx-nsh` | Build NuttX with NuttShell |
| `nuttx-rtl-hello` | Run hello in RTL simulation |
| `nuttx-rtl-nsh` | Run NSH in RTL simulation |
| `nuttx-sim-hello` | Run hello in C++ simulation |
| `nuttx-sim-nsh` | Run NSH in C++ simulation |
| `nuttx-compare-hello` | Compare hello traces |
| `nuttx-compare-nsh` | Compare NSH traces |
| `nuttx-clean` | Clean NuttX builds |
| `nuttx-help` | Show NuttX help |

## Parameters

| Parameter | Values | Description |
|-----------|--------|-------------|
| `TRACE` | 0, 1 | Enable instruction trace logging |
| `MEMTRACE` | 0, 1 | Enable memory transaction logging |
| `WAVE` | fst, vcd | Enable waveform capture |
| `MAX_CYCLES` | number | Maximum simulation cycles (0=unlimited) |

## Troubleshooting

### NuttX Not Found

```
Error: NuttX not found at /Users/kuoping/NuttX/nuttx
```

**Solution**: Install NuttX or set `NUTTX_BASE`:
```bash
export NUTTX_BASE=/path/to/your/nuttx
export NUTTX_APPS=/path/to/your/apps
```

### Build Errors

If you encounter build errors, try:

```bash
# Clean and rebuild
make nuttx-clean
make nuttx-hello

# Clean NuttX completely
cd ~/NuttX/nuttx
make distclean
cd ~/Projects/kcore
make nuttx-hello
```

### Serial Output Not Working

Check UART configuration in board files:
- Verify UART base address: 0x10000000
- Check baud rate: 115200
- Ensure CONFIG_KCORE_UART0=y in defconfig

## Comparison with Zephyr

| Feature | NuttX | Zephyr |
|---------|-------|--------|
| Build System | GNU Make + Kconfig | CMake + West |
| Configuration | defconfig files | .conf overlay files |
| Shell | NSH (NuttShell) | Zephyr shell |
| Driver Model | POSIX-like | Zephyr device model |
| UART Driver | uart_kcore.c | uart_kcore.c (different API) |
| Board Files | boards/risc-v/kcore | boards/riscv/kcore_board |

## Adding New Samples

1. Create sample directory:
```bash
mkdir -p rtos/nuttx/samples/mysample
```

2. Create application source:
```c
// mysample_main.c
#include <stdio.h>

int main(int argc, char *argv[])
{
  printf("My custom sample!\n");
  return 0;
}
```

3. Create Makefile (copy from hello/Makefile and modify)

4. Add Makefile targets (copy hello targets and modify for mysample)

## Next Steps

1. **Add More Samples**: Create additional test applications
2. **Implement More Drivers**: Add GPIO, SPI, I2C drivers
3. **Enable Networking**: Configure NuttX networking stack
4. **File System Support**: Add file system drivers
5. **Performance Testing**: Run benchmarks (Dhrystone, CoreMark)
6. **Multi-tasking**: Test RTOS scheduling and IPC

## References

- [NuttX Documentation](https://nuttx.apache.org/docs/latest/)
- [NuttX GitHub](https://github.com/apache/nuttx)
- [RISC-V NuttX Porting Guide](https://nuttx.apache.org/docs/latest/platforms/risc-v/index.html)
- [kcore Project README](../../README.md)
- [Zephyr Integration](../zephyr/README.md)

## License

NuttX is licensed under Apache License 2.0.
kcore board support and drivers follow the same license.
