# NuttX RTOS Porting for kcore

This directory contains NuttX RTOS integration for the kcore RISC-V processor.

## Directory Structure

- **boards/**: Board support package for kcore
  - `risc-v/kcore/kcore-board/`: Board-specific configuration and drivers
  - `risc-v/kcore/kcore-board/configs/`: Pre-configured board configurations (nsh, etc.)
  
- **drivers/**: Custom drivers for kcore hardware
  - `serial/`: UART serial driver implementation

- **samples/**: Example applications
  - `hello/`: Simple hello world application
  - `nsh/`: NuttShell (command shell) application

## Prerequisites

1. Install NuttX:
   ```bash
   mkdir -p ~/NuttX
   cd ~/NuttX
   git clone https://github.com/apache/nuttx.git nuttx
   git clone https://github.com/apache/nuttx-apps.git apps
   ```

2. Install RISC-V toolchain (already in env.config):
   - Use xpack-riscv-none-elf-gcc or similar

3. Install kconfig-frontends:
   ```bash
   # macOS
   brew install kconfig-frontends
   ```

## Building NuttX Applications

From the kcore project root:

```bash
# Build hello world sample
make nuttx-hello

# Build NuttShell
make nuttx-nsh

# Run in RTL simulation
make nuttx-rtl-hello
make nuttx-rtl-nsh

# Run in C++ simulation
make nuttx-sim-hello
make nuttx-sim-nsh

# Compare RTL vs C++ simulation
make nuttx-compare-hello
make nuttx-compare-nsh

# Clean NuttX builds
make nuttx-clean
```

## Configuration

The board configuration is based on:
- Architecture: RV32IMA with Zicsr and Zifencei
- Memory: 64KB at 0x80000000
- Peripherals:
  - UART0 at 0x10000000 (115200 8N1)
  - CLINT timer at 0x200bff8
  - PLIC (future)

## Development Workflow

1. Modify board configuration:
   ```bash
   cd rtos/nuttx/boards/risc-v/kcore/kcore-board/configs/nsh
   make menuconfig  # After initial build
   ```

2. Add custom drivers in `rtos/nuttx/drivers/`

3. Create new samples in `rtos/nuttx/samples/`

4. Update Makefile targets for new samples

## Notes

- NuttX is configured as an external tree overlay on top of the official NuttX repository
- Board and driver files are maintained in this repository
- Samples are standalone applications that link against NuttX
