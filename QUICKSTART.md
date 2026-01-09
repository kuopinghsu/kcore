# RISC-V Processor - Quick Start Guide

Get started with the RV32IMA processor in 5 minutes.

> **📚 Documentation**: See [README.md](README.md) for complete details | [PROJECT_STATUS.md](PROJECT_STATUS.md) for status

## Prerequisites

**Required Tools**: RISC-V GCC toolchain, Verilator v5.0+, Python 3

**Optional Tools**: 
- Spike ISA simulator (default software simulator, `USE_SPIKE=1`)
- Built-in rv32sim can be used instead (`USE_SPIKE=0`)

**Setup**: Edit `env.config` to configure tool paths, then run:
```bash
make info    # Verify configuration
```

## Quick Start

### 1. Build
```bash
make all     # Build everything
```

### 2. Run Tests
```bash
make verify-simple    # Verify simple test (recommended first run)
make verify-full      # Verify comprehensive test suite
```

### 3. View Results
```bash
cat build/rtl_trace.txt    # RTL execution trace
cat build/test.dump        # Disassembly
```

## Common Commands

```bash
make help              # Show all available commands
make clean             # Clean build artifacts
make rtl-<test>        # Run specific test (simple, hello, full, interrupt, uart, dhry)
make rtl WAVE=fst      # Run with waveform (FST format)
make wave              # View waveforms in GTKWave
make compare           # Compare RTL vs software simulator (default: Spike)
make compare USE_SPIKE=0  # Compare using rv32sim instead
make arch-test-rv32i   # Run architectural tests (RV32I: 38/38 pass)
make arch-test-rv32m   # Run architectural tests (RV32M: 8/8 pass)
```

## Available Tests

- `simple` - Minimal smoke test (476B)
- `hello` - Console output with printf (68KB)
- `full` - Comprehensive suite (11 tests)
- `interrupt` - Timer interrupt validation
- `uart` - Full-duplex TX/RX test
- `dhry` - Dhrystone benchmark (8.13 DMIPS)

Details: [PROJECT_STATUS.md](PROJECT_STATUS.md)

## Debugging

**Interactive GDB Debugging** (rv32sim):
```bash
# Terminal 1
./build/rv32sim --gdb --gdb-port=3333 build/test.elf

# Terminal 2
riscv32-unknown-elf-gdb build/test.elf
(gdb) target remote localhost:3333
(gdb) break main
(gdb) watch myvar    # Breakpoint on write
(gdb) continue
```

**Enable waveforms**:
```bash
make rtl-<test> WAVE=fst    # FST format (compact)
make wave                    # View with GTKWave
```

**Common issues**: See [README.md](README.md) Debugging section

## More Information

- **Architecture & Features**: [README.md](README.md)
- **Test Results & Status**: [PROJECT_STATUS.md](PROJECT_STATUS.md)  
- **Software Tests**: [sw/README.md](sw/README.md)
- **Verification**: [verif/riscof_targets/README.md](verif/riscof_targets/README.md)

---
✅ **Status**: All systems operational | **ISA**: RV32IMA | **Performance**: 8.13 DMIPS @ 50 MHz
