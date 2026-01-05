# NuttX Quick Start Guide

## Prerequisites

```bash
# Install NuttX
mkdir -p ~/NuttX && cd ~/NuttX
git clone https://github.com/apache/nuttx.git nuttx
git clone https://github.com/apache/nuttx-apps.git apps

# Install kconfig-frontends (macOS)
brew install kconfig-frontends

# Verify RISC-V toolchain (should already be configured)
make info  # Check RISCV_PREFIX
```

## Build and Run

### Hello World

```bash
# Build
make nuttx-hello

# Run in RTL simulation
make nuttx-rtl-hello

# Expected output:
# Hello, World from NuttX on kcore!
# RISC-V RV32IMA processor
# NuttX RTOS successfully running
```

### NuttShell

```bash
# Build (same as hello)
make nuttx-nsh

# Run in RTL simulation
make nuttx-rtl-nsh

# Try NSH commands interactively
```

## Common Commands

```bash
# Build options
make nuttx-hello TRACE=1          # Enable trace
make nuttx-rtl-hello WAVE=fst     # Capture waveform

# Compare simulations
make nuttx-compare-hello          # RTL vs C++ verification

# Clean
make nuttx-clean                  # Clean builds
```

## Verification

```bash
# Full verification workflow
make nuttx-hello                  # Build
make nuttx-rtl-hello             # Run RTL sim
make nuttx-sim-hello             # Run C++ sim  
make nuttx-compare-hello         # Compare traces
```

## Help

```bash
make nuttx-help                   # NuttX-specific help
make help                         # All targets
```

## File Locations

- **Source**: `rtos/nuttx/`
- **Build output**: `build/test.elf`, `build/test.bin`
- **Traces**: `build/rtl_trace.txt`, `build/sim_trace.txt`
- **Waveform**: `build/test.fst` (if WAVE=fst)

## Next Steps

- Read [docs/nuttx_integration.md](../docs/nuttx_integration.md) for detailed documentation
- Customize board configuration with `make menuconfig`
- Add custom applications in `rtos/nuttx/samples/`
- Develop additional drivers in `rtos/nuttx/drivers/`
