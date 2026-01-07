# NuttX Porting Guide for KCORE

This guide explains how to port NuttX to a custom RISC-V processor (KCORE) and integrate it with your project repository.

## Overview

Porting NuttX to a custom RISC-V processor requires:
1. Patching the upstream NuttX Kconfig to add your chip
2. Creating board support files
3. Creating chip architecture files
4. Implementing minimal chip-specific functions
5. Configuring the build system

## Architecture

```
Your Project Repository (kcore/)
├── rtos/nuttx/                      # Porting files maintained in your repo
│   ├── boards/                      # Board support package
│   ├── arch/                        # Chip architecture files
│   ├── scripts/                     # Build/patch scripts
│   └── samples/                     # Sample configurations
│
Upstream NuttX Repository (~/NuttX/nuttx/)
└── (files synced from your repo during build)
```

## Required Files in Your Repository

### 1. Board Support Package

Location: `rtos/nuttx/boards/risc-v/kcore/kcore-board/`

#### Board Configuration Files

**`boards/risc-v/kcore/kcore-board/configs/nsh/defconfig`**
- Default configuration for your board
- Key settings:
  ```makefile
  CONFIG_ARCH="risc-v"
  CONFIG_ARCH_CHIP="kcore"
  CONFIG_ARCH_CHIP_KCORE=y
  CONFIG_ARCH_RV32=y
  CONFIG_ARCH_BOARD_CUSTOM=y
  CONFIG_ARCH_BOARD_CUSTOM_DIR="boards/risc-v/kcore/kcore-board"
  CONFIG_ARCH_BOARD_CUSTOM_DIR_RELPATH=y
  CONFIG_ARCH_BOARD="kcore-board"
  CONFIG_RAM_START=0x80000000
  CONFIG_RAM_SIZE=2097152            # 2MB
  CONFIG_RISCV_TOOLCHAIN_GNU_RV32=y
  CONFIG_INIT_ENTRYPOINT="hello_main"
  CONFIG_EXAMPLES_HELLO=y
  ```

**`boards/risc-v/kcore/kcore-board/include/board.h`**
- Board-level definitions
- Memory configuration:
  ```c
  #define KCORE_MEM_BASE    0x80000000
  #define KCORE_MEM_SIZE    0x200000   /* 2MB */
  ```

**`boards/risc-v/kcore/kcore-board/scripts/ld.script`**
- Linker script defining memory layout
- Must include:
  ```ld
  ENTRY(__start)
  MEMORY {
    kflash (rx)  : ORIGIN = 0x80000000, LENGTH = 2M
    ksram  (rwx) : ORIGIN = 0x80000000, LENGTH = 2M
  }
  PROVIDE(__global_pointer$ = _sdata + ((_edata - _sdata) / 2));
  ```

**`boards/risc-v/kcore/kcore-board/scripts/Make.defs`**
- Build flags and toolchain configuration:
  ```makefile
  ARCHSCRIPT = $(BOARD_DIR)/scripts/ld.script
  ARCHCPUFLAGS = -march=rv32ima_zicsr_zifencei -mabi=ilp32
  ```

**`boards/risc-v/kcore/kcore-board/src/`**
- `Makefile` - Board source build configuration
- `Make.defs` - Additional board-level definitions
- `kcore_appinit.c` - Application initialization (returns 0)

**`boards/risc-v/kcore/Kconfig`**
- Board selection Kconfig:
  ```kconfig
  config ARCH_BOARD_KCORE
    bool "KCORE Custom Board"
    depends on ARCH_CHIP_KCORE
  ```

### 2. Chip Architecture Files

#### Chip Include Files

Location: `rtos/nuttx/arch/risc-v/include/kcore/`

**`arch/risc-v/include/kcore/chip.h`**
- Empty or minimal chip-specific definitions

**`arch/risc-v/include/kcore/irq.h`**
- IRQ definitions:
  ```c
  #define NR_IRQS          16
  #define KCORE_IRQ_UART0  10
  ```

#### Chip Source Files

Location: `rtos/nuttx/arch/risc-v/src/kcore/`

**`arch/risc-v/src/kcore/Make.defs`**
- Lists chip sources:
  ```makefile
  include $(TOPDIR)/arch/risc-v/src/common/Make.defs
  
  HEAD_ASRC = kcore_head.S
  
  CHIP_CSRCS  = kcore_start.c
  CHIP_CSRCS += kcore_irq.c
  CHIP_CSRCS += kcore_irq_dispatch.c
  CHIP_CSRCS += kcore_timerisr.c
  CHIP_CSRCS += kcore_allocateheap.c
  CHIP_CSRCS += kcore_lowputc.c
  ```

**`arch/risc-v/src/kcore/chip.h`**
- Chip memory map and peripheral base addresses:
  ```c
  #define KCORE_CLINT_BASE  0x0200bff8
  #define KCORE_UART0_BASE  0x10000000
  #define KCORE_MEM_START   0x80000000
  #define KCORE_MEM_SIZE    0x200000
  ```

**`arch/risc-v/src/kcore/Makefile`**
- Minimal chip Makefile

### 3. Minimal Required Implementations

**`kcore_head.S`** - Assembly startup code
- Provides `__start` entry point
- Sets up stack pointer and global pointer
- Clears BSS section
- Calls `kcore_start()`

**`kcore_start.c`** - C initialization
- Copies `.data` from flash to RAM
- Clears `.bss` section
- Calls `nx_start()` to enter NuttX

**`kcore_irq.c`** - Interrupt control
- `up_irqinitialize()` - Initialize IRQ subsystem
- `up_irq_enable()` - Enable global interrupts (returns irqstate_t)
- `up_enable_irq(int irq)` - Enable specific IRQ
- `up_disable_irq(int irq)` - Disable specific IRQ

**`kcore_irq_dispatch.c`** - Interrupt dispatcher
- `riscv_dispatch_irq()` - Route interrupts to handlers

**`kcore_timerisr.c`** - System timer
- `up_timer_initialize()` - Configure CLINT timer
- Timer interrupt handler for tick generation

**`kcore_allocateheap.c`** - Memory management
- `up_allocate_heap()` - Define heap start/size
- Typically starts after BSS: `&_ebss`

**`kcore_lowputc.c`** - Console output
- `up_putc(int ch)` - Output one character to UART
- `riscv_earlyserialinit()` - Early serial init (can be stub)
- `riscv_serialinit()` - Full serial init (can be stub)

### 4. Kconfig Integration

**`rtos/nuttx/scripts/patch_kconfig.py`**
- Python script to patch upstream `arch/risc-v/Kconfig`
- Adds your chip configuration:
  ```python
  kcore_config = '''
  config ARCH_CHIP_KCORE
  \tbool "KCORE RISC-V Core"
  \tselect ARCH_RV32
  \tselect ARCH_RV_ISA_M
  \tselect ARCH_RV_ISA_A
  \tselect ARCH_RV_ISA_ZICSR
  \tselect ARCH_RV_ISA_ZIFENCEI
  \t---help---
  \t\tKCORE custom RISC-V processor
  '''
  ```
- Inserts after BL602 chip definition
- Adds default and source statements

## Build System Integration

### Makefile Targets

In your top-level `Makefile`, add NuttX build targets following a pattern-based approach similar to Zephyr:

```makefile
# NuttX configuration
NUTTX_DIR = rtos/nuttx
NUTTX_BASE ?= $(HOME)/NuttX/nuttx
NUTTX_APPS ?= $(HOME)/NuttX/apps
NUTTX_SAMPLES = $(NUTTX_DIR)/samples

# Pattern rule for NuttX tests: nuttx-<sample>
# Builds any sample from rtos/nuttx/samples/<sample>
.PHONY: nuttx-%
nuttx-%: check-nuttx
	@echo "=== Building NuttX Sample: $* ==="
	@if [ ! -d $(NUTTX_SAMPLES)/$* ]; then \
		echo "Error: $(NUTTX_SAMPLES)/$* not found"; \
		exit 1; \
	fi
	# Sync board files to NuttX tree
	mkdir -p $(NUTTX_BASE)/boards/risc-v/kcore
	cp -r $(NUTTX_DIR)/boards/risc-v/kcore/* $(NUTTX_BASE)/boards/risc-v/kcore/
	
	# Sync chip files to NuttX tree
	mkdir -p $(NUTTX_BASE)/arch/risc-v/src/kcore
	mkdir -p $(NUTTX_BASE)/arch/risc-v/include/kcore
	cp -r $(NUTTX_DIR)/arch/risc-v/src/kcore/* $(NUTTX_BASE)/arch/risc-v/src/kcore/
	cp -r $(NUTTX_DIR)/arch/risc-v/include/kcore/* $(NUTTX_BASE)/arch/risc-v/include/kcore/
	
	# Patch Kconfig to add KCORE chip
	python3 $(NUTTX_DIR)/scripts/patch_kconfig.py $(NUTTX_BASE)/arch/risc-v/Kconfig
	
	# Copy sample to apps directory
	mkdir -p $(NUTTX_APPS)/examples/$*
	cp -r $(NUTTX_SAMPLES)/$*/* $(NUTTX_APPS)/examples/$*/
	
	# Configure and build
	cd $(NUTTX_BASE) && \
		./tools/configure.sh kcore-board:nsh && \
		make -j$(shell nproc)
	
	# Copy outputs
	cp $(NUTTX_BASE)/nuttx build/test.elf
	$(OBJDUMP) -D build/test.elf > build/test.dump
	# Note: ELF files are used directly, no binary conversion needed

# Pattern rule for RTL simulation
.PHONY: nuttx-rtl-%
nuttx-rtl-%: nuttx-% rtl-verilator-build
	@echo "=== Running NuttX sample in RTL: $* ==="
	$(VLT_BUILD_DIR)/kcore_vsim $(SW_BIN) 100000 $(BUILD_DIR)/rtl_trace.txt

# Pattern rule for C++ simulation
.PHONY: nuttx-sim-%
nuttx-sim-%: nuttx-% $(SIM_EXEC)
	@echo "=== Running NuttX sample in C++ sim: $* ==="
	$(SIM_EXEC) $(SW_BIN) $(BUILD_DIR)/sim_trace.txt

# Pattern rule for trace comparison
.PHONY: nuttx-compare-%
nuttx-compare-%: nuttx-rtl-% nuttx-sim-%
	@echo "=== Comparing traces: $* ==="
	python3 $(SIM_DIR)/trace_compare.py $(BUILD_DIR)/rtl_trace.txt $(BUILD_DIR)/sim_trace.txt
```

**Usage Examples:**
```bash
make nuttx-hello              # Build hello world sample
make nuttx-rtl-hello          # Run hello in RTL simulation
make nuttx-sim-hello          # Run hello in C++ simulation
make nuttx-compare-hello      # Compare RTL vs C++ traces
```

## Step-by-Step Porting Process

### 1. Initial Setup

1. Clone upstream NuttX and apps repositories:
   ```bash
   mkdir -p ~/NuttX
   cd ~/NuttX
   git clone https://github.com/apache/nuttx.git
   git clone https://github.com/apache/nuttx-apps.git apps
   ```

2. Install kconfig-frontends tools (if not already installed):
   ```bash
   # On macOS/Linux
   cd /tmp
   git clone https://github.com/jameswalmsley/kconfig-frontends.git
   cd kconfig-frontends
   ./bootstrap
   ./configure --prefix=$HOME/.local
   make
   make install
   ```

3. Add kconfig tools to PATH in your `env.config`:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   export NUTTX_BASE="$HOME/NuttX/nuttx"
   ```

### 2. Create Board Support

1. Create directory structure:
   ```bash
   mkdir -p rtos/nuttx/boards/risc-v/kcore/kcore-board/{configs/nsh,include,scripts,src}
   ```

2. Create minimal board files (see "Required Files" section above)

3. Key considerations:
   - Memory layout must match your processor's memory map
   - Stack size in linker script must be adequate (typically 2KB+)
   - Entry point must be `__start` to match your assembly code

### 3. Create Chip Support

1. Create directory structure:
   ```bash
   mkdir -p rtos/nuttx/arch/risc-v/{src/kcore,include/kcore}
   ```

2. Implement minimal required functions (see section 3 above)

3. Critical implementation notes:
   - `up_irq_enable()` must return `irqstate_t`, not `void`
   - Use inline assembly for CSR operations:
     ```c
     __asm__ __volatile__("csrrsi %0, mstatus, 8\n" 
                          : "=r" (oldstat) : : "memory");
     ```
   - All linker symbols (`_ebss`, `_sdata`, etc.) must be referenced as `extern char` 
     and used with `&` operator
   - Timer must use your actual CLINT base address

### 4. Create Kconfig Patch Script

Create `rtos/nuttx/scripts/patch_kconfig.py` that:
1. Reads upstream `arch/risc-v/Kconfig`
2. Checks if already patched (to avoid duplicate patches)
3. Inserts chip configuration after existing chips (e.g., BL602)
4. Adds to chip list and source statement

### 5. Configure Build

1. Update defconfig with correct settings:
   - Architecture (RV32/RV64, ISA extensions)
   - Toolchain selection
   - Memory configuration
   - Entry point application

2. For simple hello world:
   - Set `CONFIG_INIT_ENTRYPOINT="hello_main"`
   - Enable `CONFIG_EXAMPLES_HELLO=y`
   - Can disable NSH for minimal build

### 6. Test Build

1. Run your Makefile target:
   ```bash
   make nuttx-hello
   ```

2. Verify output:
   ```bash
   riscv-none-elf-size build/test.elf
   riscv-none-elf-objdump -h build/test.elf
   ```

3. Expected sections should have non-zero sizes:
   - `.text` - Program code (typically 60KB+)
   - `.data` - Initialized data (typically <1KB)
   - `.bss` - Uninitialized data (typically 5-10KB)

## Common Issues and Solutions

### Issue: Zero-Size Binary

**Symptom:** `test.elf` is very small (< 1KB), sections are all zero

**Cause:** Chip source files not included in build

**Solution:** 
- Verify `CHIP_CSRCS` in `arch/risc-v/src/kcore/Make.defs` lists all source files
- Ensure `Make.defs` includes `common/Make.defs`
- Check that chip Makefile exists

### Issue: Undefined Reference to __global_pointer$

**Symptom:** Linker error about missing `__global_pointer$`

**Cause:** RISC-V requires global pointer for efficient global variable access

**Solution:** Add to linker script after `.data` section:
```ld
PROVIDE(__global_pointer$ = _sdata + ((_edata - _sdata) / 2));
```

### Issue: Wrong GCC Flags

**Symptom:** Compiler errors about unsupported instructions or ABI mismatch

**Cause:** Incorrect `-march` or `-mabi` flags

**Solution:** Match your processor architecture:
- RV32IMA: `-march=rv32ima_zicsr_zifencei -mabi=ilp32`
- RV64IMA: `-march=rv64ima_zicsr_zifencei -mabi=lp64`

### Issue: Conflicting Types for IRQ Functions

**Symptom:** Error about conflicting types for `up_irq_enable` or similar

**Cause:** Function signature doesn't match NuttX expectations

**Solution:** 
- `up_irq_enable()` must return `irqstate_t` (old interrupt state)
- `up_irq_save()` returns `irqstate_t`
- `up_irq_restore(irqstate_t)` takes previous state

### Issue: Board Symlink Error

**Symptom:** Build fails with error about board symlink not found

**Cause:** Board path configuration incorrect

**Solution:** Use custom board directory with:
```makefile
CONFIG_ARCH_BOARD_CUSTOM=y
CONFIG_ARCH_BOARD_CUSTOM_DIR="boards/risc-v/kcore/kcore-board"
CONFIG_ARCH_BOARD_CUSTOM_DIR_RELPATH=y
```

## Maintenance

### Updating to New NuttX Version

1. Update upstream NuttX repository:
   ```bash
   cd ~/NuttX/nuttx
   git pull
   ```

2. Re-run your sync and patch:
   ```bash
   make nuttx-hello
   ```

3. The patch script checks if already patched, so it's safe to re-run

### Adding New Features

To add more functionality (serial driver, SPI, etc.):

1. Add driver files to `rtos/nuttx/arch/risc-v/src/kcore/`
2. Update `Make.defs` to include new files
3. Add Kconfig options if needed
4. Update defconfig to enable new features

### Testing

Test your port with:
1. Simple hello world application
2. Timer interrupts (verify tick generation)
3. UART output (console messages)
4. Memory allocation (heap operations)

## Reference Implementation

For a complete working example, see the kcore implementation in this repository:
- Board files: `rtos/nuttx/boards/risc-v/kcore/kcore-board/`
- Chip files: `rtos/nuttx/arch/risc-v/src/kcore/`
- Patch script: `rtos/nuttx/scripts/patch_kconfig.py`
- Build integration: `Makefile` (nuttx-hello target)

## Resources

- [NuttX Documentation](https://nuttx.apache.org/docs/latest/)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
- [NuttX Porting Guide](https://nuttx.apache.org/docs/latest/guides/porting.html)
- [RISC-V Assembly Reference](https://github.com/riscv-non-isa/riscv-asm-manual)
