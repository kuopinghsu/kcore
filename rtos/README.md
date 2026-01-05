# RTOS Support for kcore

This directory contains Real-Time Operating System (RTOS) ports for the RV32IM kcore processor.

## Available RTOS Ports

### 1. FreeRTOS V11.2.0 ✅
- **Status**: Complete and verified
- **Location**: [`freertos/`](freertos/)
- **Features**: Full RISC-V port with task scheduling, synchronization, and memory management
- **Documentation**: See [freertos/README.md](freertos/README.md)
- **Samples**: Simple task demo, performance test
- **Make targets**: `make freertos-simple`, `make freertos-rtl-simple`

### 2. Zephyr RTOS 4.3.99 ✅
- **Status**: Complete with timer and threading support
- **Location**: [`zephyr/`](zephyr/)
- **Features**: Full SoC/board port with console, UART, timer drivers, and multi-threading
- **Documentation**: See [zephyr/README.md](zephyr/README.md)
- **Samples**: hello_world, uart_echo, threads_sync
- **Make targets**: `make zephyr-hello_world`, `make zephyr-threads_sync`

## Quick Start

### FreeRTOS
```bash
# Build and run simple FreeRTOS demo
make freertos-rtl-simple

# Build only
make freertos-simple
```

### Zephyr
```bash
# Build and run threading demo
make zephyr-rtl-threads_sync

# Build and run hello world
make zephyr-rtl-hello_world

# Build and run UART echo
make zephyr-rtl-uart_echo
```

## Comparison

| Feature | FreeRTOS | Zephyr |
|---------|----------|--------|
| **Kernel Version** | V11.2.0 | 4.3.99 |
| **License** | MIT | Apache 2.0 |
| **Footprint** | Small (~8KB) | Medium (~20KB+) |
| **Threading** | ✅ Tasks | ✅ Threads |
| **Timers** | ✅ Software timers | ✅ Hardware timer (CLINT) |
| **Synchronization** | ✅ Semaphores, Mutexes, Queues | ✅ Semaphores, Mutexes |
| **Memory Management** | ✅ heap_3 (malloc/free) | ✅ Minimal C library |
| **Interrupts** | ✅ Timer interrupts | ✅ Timer interrupts |
| **Preemption** | ✅ Configurable | ✅ Time-slicing |
| **Priority Levels** | 8 | 256 |
| **Stack Management** | Static allocation | Dynamic per-thread |
| **Console Driver** | printf to magic address | Magic address + UART |
| **Development Style** | Low-level control | Framework-based |
| **Best For** | Simple embedded apps | Complex multi-threaded apps |

## Hardware Support

Both RTOS ports support:

- **CPU**: RV32IM (32-bit RISC-V with multiply/divide)
- **Memory**: 2MB RAM @ 0x80000000
- **Timer**: CLINT machine timer @ 0x02000000
- **Console**: Magic address @ 0xFFFFFFF4
- **UART**: Optional hardware UART @ 0x10000000
- **Clock**: 50 MHz system clock

## Performance

### Memory Usage

| RTOS | Text (Code) | Data | BSS | Total |
|------|-------------|------|-----|-------|
| **FreeRTOS simple** | ~8 KB | ~500 B | ~66 KB | ~74 KB |
| **Zephyr hello_world** | ~7 KB | ~100 B | ~1 KB | ~8 KB |
| **Zephyr threads_sync** | ~20 KB | ~100 B | ~6 KB | ~26 KB |

### Simulation Performance

| Sample | Cycles | Instructions | CPI | Sim Time |
|--------|--------|--------------|-----|----------|
| **FreeRTOS simple** | 2.6M | 348K | 7.43 | 52ms |
| **Zephyr hello_world** | 1K | 150 | 6.67 | <1ms |
| **Zephyr threads_sync** | 79M | 10.6M | 7.45 | 790ms |

## Configuration

### FreeRTOS
- Configure via `freertos/include/FreeRTOSConfig.h`
- Heap size: 64KB (configurable)
- Tick rate: 1000 Hz (1ms tick)
- Priority levels: 8

### Zephyr
- Configure via `prj.conf` in each sample
- Heap: Minimal C library heap
- Tick rate: 100 Hz (10ms tick) - configurable
- Priority levels: 256 (cooperative or preemptive)

## Documentation

- **FreeRTOS**: See [freertos/README.md](freertos/README.md) for detailed porting guide
- **Zephyr**: See [zephyr/README.md](zephyr/README.md) for comprehensive documentation
- **Project Status**: See [../PROJECT_STATUS.md](../PROJECT_STATUS.md) for verification results

## Adding New RTOS

To port a new RTOS to kcore:

1. **Create directory**: `rtos/your_rtos/`
2. **Port requirements**:
   - RISC-V RV32IM support
   - Machine mode only (no supervisor mode)
   - Custom timer setup (CLINT @ 0x02000000)
   - Console output (magic address @ 0xFFFFFFF4)
3. **Required files**:
   - Startup code (reset vector, stack setup)
   - Linker script (2MB RAM @ 0x80000000)
   - Syscalls (_write, _exit, _sbrk)
   - Configuration headers
4. **Makefile integration**:
   - Add build target: `make your_rtos-<sample>`
   - Add run target: `make your_rtos-rtl-<sample>`
5. **Documentation**:
   - Create `your_rtos/README.md`
   - Update this file
   - Update PROJECT_STATUS.md

## Troubleshooting

### Common Issues

1. **"Illegal instruction"**: Check that binary is compiled for RV32IM (not RV32IMAC)
2. **No console output**: Verify magic address (0xFFFFFFF4) writes in testbench
3. **Crashes/hangs**: Increase stack sizes in configuration
4. **Timer not working**: Check CLINT configuration and interrupt enable
5. **Memory errors**: Verify RAM size (2MB) and address (0x80000000)

### Debug Tips

- **Enable verbose output**: Add `-DDEBUG` to compilation flags
- **Check stack usage**: Use `-fstack-usage` compiler flag
- **Analyze traces**: Use `sim/parse_call_trace.py` for call profiling
- **Memory traces**: Use `make memtrace-<test>` to verify memory accesses
- **RTL waveforms**: Run with `make rtl-wave` to generate VCD files

## Testing

Both RTOS ports are verified with:
- ✅ RTL simulation (Verilator)
- ✅ Instruction-level verification (Spike ISA simulator)
- ✅ Memory transaction verification
- ✅ Timer interrupt verification
- ✅ Multi-threading verification
- ✅ Synchronization primitives verification

## License

- **FreeRTOS**: MIT License (see FreeRTOS source files)
- **Zephyr**: Apache 2.0 License (see Zephyr source files)
- **kcore RTOS Ports**: Same license as respective RTOS

## References

- [FreeRTOS Official Documentation](https://www.freertos.org/)
- [Zephyr Project Documentation](https://docs.zephyrproject.org/)
- [RISC-V Privileged Spec](https://riscv.org/specifications/privileged-isa/)
- [kcore Project Status](../PROJECT_STATUS.md)
