# Makefile for RISC-V SoC Project
# Builds software, runs RTL simulation, and compares traces

# Load environment configuration (must define RISCV_PREFIX and VERILATOR)
-include env.config

# Append additional paths to PATH if specified
ifdef PATH_APPEND
export PATH := $(PATH_APPEND):$(PATH)
endif

ifdef RISCV_FORMAL
export RISCV_FORMAL := $(RISCV_FORMAL)
endif

# Toolchain commands
CC = $(RISCV_PREFIX)gcc
CXX = $(RISCV_PREFIX)g++
OBJDUMP = $(RISCV_PREFIX)objdump
SIZE = $(RISCV_PREFIX)size
CROSS_COMPILE = $(RISCV_PREFIX)
export CROSS_COMPILE

# Get the directory containing the RISC-V toolchain binaries
RISCV_PREFIX_DIR = $(dir $(shell which $(CC)))

# Directories
RTL_DIR = rtl
TB_DIR = testbench
SW_DIR = sw
SW_COMMON_DIR = $(SW_DIR)/common
SIM_DIR = sim
FORMAL_DIR = verif/formal_configs
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj
VLT_DIR = $(BUILD_DIR)/verilator
VLT_VCD_DIR = $(BUILD_DIR)/verilator_vcd

# Test selection (can be overridden: make TEST=hello verify)
TEST ?= simple

# Test exclusion list for -all targets (directories in sw/ to skip)
TEST_EXCLUDE_DIRS = common include

# Get all test directories (subdirectories in sw/ that are not excluded)
ALL_TESTS = $(filter-out $(TEST_EXCLUDE_DIRS), $(notdir $(shell find $(SW_DIR) -mindepth 1 -maxdepth 1 -type d)))

# Software flags
ARCH = rv32ima_zicsr
ABI = ilp32
CFLAGS = -march=$(ARCH) -mabi=$(ABI) -O2 -g -Wall -Werror
CFLAGS += -ffreestanding -nostartfiles
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -I$(SW_DIR)/include
LDFLAGS = -T $(SW_COMMON_DIR)/link.ld -Wl,--gc-sections -Wl,-Map=$(BUILD_DIR)/test.map
LDFLAGS += -Wl,--wrap=fflush
LDFLAGS += -lc -lgcc

# Determine test source files
# Tests can be in sw/<test>/ directory (with multiple .c files) or sw/<test>.c (single file)
TEST_DIR = $(SW_DIR)/$(TEST)
TEST_FILE = $(SW_DIR)/$(TEST).c

# Check if test is in a subdirectory or a single file
ifneq ($(wildcard $(TEST_DIR)/*.c),)
    # Test directory exists with .c files
    TEST_C_SOURCES = $(wildcard $(TEST_DIR)/*.c)
    SW_SOURCES = $(SW_COMMON_DIR)/start.S $(SW_COMMON_DIR)/trap.c $(SW_COMMON_DIR)/syscall.c $(TEST_C_SOURCES)
else ifneq ($(wildcard $(TEST_DIR)/*.cpp),)
    # Test directory exists with .cpp files (C++ test)
    TEST_CPP_SOURCES = $(wildcard $(TEST_DIR)/*.cpp)
    SW_SOURCES = $(SW_COMMON_DIR)/start.S $(SW_COMMON_DIR)/trap.c $(SW_COMMON_DIR)/syscall.c $(TEST_CPP_SOURCES)
    # Use C++ compiler and add C++ flags
    CC = $(CXX)
    CFLAGS += -fno-exceptions -fno-rtti
    LDFLAGS += -lstdc++
else ifneq ($(wildcard $(TEST_FILE)),)
    # Single test file exists
    SW_SOURCES = $(SW_COMMON_DIR)/start.S $(SW_COMMON_DIR)/trap.c $(SW_COMMON_DIR)/syscall.c $(TEST_FILE)
else
    # Fallback for backward compatibility
    SW_SOURCES = $(SW_COMMON_DIR)/start.S $(SW_COMMON_DIR)/trap.c $(SW_COMMON_DIR)/syscall.c $(SW_DIR)/$(TEST)_test.c
endif

# Build artifacts
SW_ELF = $(BUILD_DIR)/test.elf
SW_DUMP = $(BUILD_DIR)/test.dump

# Marker file to track which TEST was last built
TEST_MARKER = $(BUILD_DIR)/.test_marker

# RTL sources
RTL_SOURCES = $(RTL_DIR)/kcore.sv $(RTL_DIR)/csr.sv $(RTL_DIR)/clint.sv $(RTL_DIR)/uart.sv $(RTL_DIR)/soc_top.sv
TB_SOURCES = $(TB_DIR)/axi_memory.sv $(TB_DIR)/tb_soc.sv

# Memory configuration parameters (can be overridden from command line)
MEM_READ_LATENCY ?= 1
MEM_WRITE_LATENCY ?= 1
MEM_DUAL_PORT ?= 1

# Verilator flags (common)
VLT_FLAGS_COMMON = -Wall -Wno-fatal --cc --exe --build --top-module tb_soc -o kcore_vsim
VLT_FLAGS_COMMON += -Wno-UNOPTFLAT -Wno-WIDTH -Wno-UNUSED -Wno-TIMESCALEMOD
VLT_FLAGS_COMMON += -GMEM_READ_LATENCY=$(MEM_READ_LATENCY) -GMEM_WRITE_LATENCY=$(MEM_WRITE_LATENCY) -GMEM_DUAL_PORT=$(MEM_DUAL_PORT)
VLT_FLAGS_COMMON += -CFLAGS "-DMEM_READ_LATENCY=$(MEM_READ_LATENCY) -DMEM_WRITE_LATENCY=$(MEM_WRITE_LATENCY) -DMEM_DUAL_PORT=$(MEM_DUAL_PORT)"
VLT_FLAGS_COMMON += --public

# Waveform control: WAVE parameter (default: none)
# WAVE=fst - FST waveform
# WAVE=vcd - VCD waveform
# WAVE= or unset - no waveform (fastest)
WAVE ?=

# Build directory selection based on WAVE parameter
ifeq ($(WAVE),fst)
VLT_BUILD_DIR = $(BUILD_DIR)/verilator_fst
else ifeq ($(WAVE),vcd)
VLT_BUILD_DIR = $(BUILD_DIR)/verilator_vcd
else
VLT_BUILD_DIR = $(BUILD_DIR)/verilator
endif

# Build flags based on WAVE parameter
ifeq ($(WAVE),fst)
VLT_FLAGS = $(VLT_FLAGS_COMMON) --trace-fst --trace-structs
VLT_FLAGS += -CFLAGS "-std=c++14 -DTRACE_FST"
VLT_WAVE_ARG = +WAVE
DUMP_FILE = dump.fst
else ifeq ($(WAVE),vcd)
VLT_FLAGS = $(VLT_FLAGS_COMMON) --trace --trace-structs
VLT_FLAGS += -CFLAGS "-std=c++14 -DTRACE_VCD"
VLT_WAVE_ARG = +WAVE
DUMP_FILE = dump.vcd
else
VLT_FLAGS = $(VLT_FLAGS_COMMON)
VLT_FLAGS += -CFLAGS "-std=c++14"
VLT_WAVE_ARG =
DUMP_FILE =
endif

# RTL trace control: TRACE parameter (default: 0)
# TRACE=1 - Enable RTL trace logging to rtl_trace.txt
TRACE ?= 0
VLT_TRACE_ARG = $(if $(filter 1,$(TRACE)),+TRACE,)

# Memory trace control: MEMTRACE parameter (default: 0)
# MEMTRACE=1 - Enable detailed memory transaction logging
MEMTRACE ?= 0
ifeq ($(MEMTRACE),1)
VLT_FLAGS += -GENABLE_MEM_TRACE=1
# Force FST waveform if MEMTRACE enabled but no WAVE set
ifeq ($(WAVE),)
override WAVE := fst
VLT_FLAGS = $(VLT_FLAGS_COMMON) --trace-fst --trace-structs
VLT_FLAGS += -CFLAGS "-std=c++14 -DTRACE_FST"
VLT_FLAGS += -GENABLE_MEM_TRACE=1
VLT_WAVE_ARG = +WAVE
DUMP_FILE = dump.fst
endif
endif

# Software simulator
SIM_BIN = $(BUILD_DIR)/rv32sim

# Scripts directory
SCRIPTS_DIR = scripts

# Trace comparison script
TRACE_CMP = $(SCRIPTS_DIR)/trace_compare.py

# Memory trace verification script
MEM_TRACE_VERIFY = $(SCRIPTS_DIR)/analyze_mem_trace.py

# Software simulator selection: USE_SPIKE (default: 1)
# USE_SPIKE=0 - Use rv32sim
# USE_SPIKE=1 - Use Spike ISA simulator (default)
USE_SPIKE ?= 0
ifeq ($(USE_SPIKE),1)
SW_SIM = $(SPIKE)
else
SW_SIM = $(BUILD_DIR)/rv32sim
endif

# ============================================================================
# Default target - show help
# ============================================================================

.PHONY: help
help:
	@echo "RISC-V SoC Project Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make [TARGET] [PARAMETERS]"
	@echo ""
	@echo "Targets:"
	@echo "  all              - Build software, RTL sim, and software sim"
	@echo "  sw[-<test>]      - Compile software test program (default or specific test)"
	@echo "  build-<test>     - Build Verilator RTL simulation for specific test"
	@echo "  rtl[-<test>]     - Run RTL simulation (default or specific test)"
	@echo "  sim[-<test>]     - Run software simulator for default or specific test"
	@echo "  compare[-<test>] - Compare RTL and simulator traces"
	@echo "  verify[-<test>]  - Complete verification: clean, build, run, compare"
	@echo "  wave             - View waveform with GTKWave"
	@echo "  clean            - Remove build artifacts"
	@echo "  info             - Show tool configuration"
	@echo ""
	@echo "Help for Subsystems:"
	@echo "  formal / formal-info     - Show detailed help for formal verification"
	@echo "  syn / syn-info           - Show detailed help for synthesis"
	@echo "  freertos / freertos-info - Show detailed help for FreeRTOS integration"
	@echo "  zephyr / zephyr-info     - Show detailed help for Zephyr RTOS"
	@echo "  nuttx / nuttx-info       - Show detailed help for NuttX RTOS"
	@echo "  arch-test / arch-test-info - Show detailed help for architectural tests"
	@echo ""
	@echo "Note: Use <test>=all to run for all tests in sw/ directory"
	@echo "      (excludes: $(TEST_EXCLUDE_DIRS))"
	@echo "      Examples: make rtl-all, make compare-all, make verify-all"
	@echo ""
	@echo "FreeRTOS Targets:"
	@echo "  freertos-<test>        - Build FreeRTOS test (e.g., freertos-simple)"
	@echo "  freertos-rtl-<test>    - Run FreeRTOS test in RTL simulation"
	@echo "  freertos-sim-<test>    - Run FreeRTOS test in ISS simulator"
	@echo "  freertos-compare-<test> - Compare FreeRTOS RTL vs Spike traces"
	@echo "  Example: make freertos-rtl-simple TRACE=1 MAX_CYCLES=0"
	@echo "  (Use 'make freertos-info' for detailed help)"
	@echo ""
	@echo "Zephyr RTOS Targets:"
	@echo "  zephyr-venv-setup      - Set up Python virtual environment for Zephyr"
	@echo "  zephyr-<sample>        - Build Zephyr sample (e.g., zephyr-hello)"
	@echo "  zephyr-rtl-<sample>    - Run Zephyr sample in RTL simulation"
	@echo "  zephyr-sim-<sample>    - Run Zephyr sample in ISS simulator"
	@echo "  zephyr-compare-<sample> - Compare Zephyr RTL vs Spike traces"
	@echo "  zephyr-clean           - Clean Zephyr build directory"
	@echo "  zephyr-clean-all       - Clean Zephyr build and virtual environment"
	@echo "  Example: make zephyr-rtl-hello TRACE=1 MAX_CYCLES=0"
	@echo "  (Use 'make zephyr-info' for detailed help)"
	@echo ""
	@echo "NuttX RTOS Targets:"
	@echo "  nuttx-<sample>          - Build NuttX sample (e.g., nuttx-hello)"
	@echo "  nuttx-rtl-<sample>      - Run NuttX sample in RTL simulation"
	@echo "  nuttx-sim-<sample>      - Run NuttX sample in Spike ISS simulator"
	@echo "  nuttx-compare-<sample>  - Compare NuttX RTL vs Spike traces"
	@echo "  nuttx-clean             - Clean NuttX builds"
	@echo "  Example: make nuttx-rtl-hello TRACE=1 MAX_CYCLES=0"
	@echo "  (Use 'make nuttx-info' for detailed help)"
	@echo ""
	@echo "Formal Verification:"
	@echo "  formal-info      - Show formal verification setup and info"
	@echo "  formal-check     - Run formal verification checks (requires SymbiYosys)"
	@echo "  formal-clean     - Clean formal verification results"
	@echo "  (Use 'make formal-info' for detailed help)"
	@echo ""
	@echo "Synthesis (Yosys):"
	@echo "  syn / syn-info   - Show synthesis setup and info"
	@echo "  syn-check        - Check tool availability and configuration"
	@echo "  syn-check-pdk    - Check and extract PDK Liberty files if needed"
	@echo "  syn-synth        - Run synthesis (RTL to gate-level netlist)"
	@echo "  syn-formal       - Run formal equivalence checking"
	@echo "  syn-reports      - Display synthesis reports (area, timing, cells)"
	@echo "  syn-clean        - Clean synthesis results"
	@echo "  (Use 'make syn-info' for detailed help)"
	@echo ""
	@echo "Architectural Compliance Tests (RISCOF):"
	@echo "  arch-test-setup       - Set up RISCOF environment (Python venv + install)"
	@echo "  arch-test-validate    - Validate RISCOF configuration files"
	@echo "  arch-test-rv32i       - Run RV32I base instruction tests"
	@echo "  arch-test-rv32m       - Run RV32M multiply/divide tests"
	@echo "  arch-test-rv32a       - Run RV32A atomic instruction tests"
	@echo "  arch-test-rv32zicsr   - Run Zicsr CSR instruction tests"
	@echo "  arch-test-all         - Run all architectural tests (I+M+A+Zicsr)"
	@echo "  arch-test-sim         - Test rv32sim (DUT) vs spike (REF) - all ISAs"
	@echo "  arch-test-report      - Open test report in browser"
	@echo "  arch-test-clean       - Clean RISCOF work directory"
	@echo "  arch-test-clean-all   - Clean RISCOF work directory and virtual environment"
	@echo "  (Use 'make arch-test-info' for detailed help)"
	@echo ""
	@echo "Parameters:"
	@echo "  TEST=<name>       - Select test program (default: simple)"
	@echo "                      Examples: simple, full, hello, interrupt, uart, dhry"
	@echo "  WAVE=<fst|vcd>    - Enable waveform dump (default: none for speed)"
	@echo "                      fst: Fast Signal Trace (compact, recommended)"
	@echo "                      vcd: Value Change Dump (universal format)"
	@echo "  TRACE=<0|1>       - Enable RTL trace logging to rtl_trace.txt (default: 0)"
	@echo "  MEMTRACE=<0|1>    - Enable memory transaction logging (default: 0)"
	@echo "                      Auto-enables FST waveform if WAVE not set"
	@echo "                      Generates build/mem_trace.txt and runs verification"
	@echo "                      Note: Some AXI fetches may not match CPU reads due to"
	@echo "                      pipeline flushes (branches/interrupts) - this is correct"
	@echo "  MAX_CYCLES=<n>    - Set simulation cycle limit (default: 10M)"
	@echo "                      Use 0 for unlimited cycles"
	@echo "  USE_SPIKE=<0|1>   - Select software simulator (default: 0)"
	@echo "                      0: Use rv32sim (built-in simulator)"
	@echo "                      1: Use Spike ISA simulator"
	@echo ""
	@echo "Quick Examples:"
	@echo "  make rtl                              # Fast: no waveform, default test"
	@echo "  make rtl-all                          # Run all tests (simple, hello, uart, etc.)"
	@echo "  make compare-all                      # Compare all tests against Spike"
	@echo "  make rtl-interrupt                    # Fast: interrupt test, no waveform"
	@echo "  make rtl-interrupt WAVE=fst           # Debug: interrupt with FST waveform"
	@echo "  make rtl WAVE=vcd TRACE=1             # Full debug: VCD + RTL trace"
	@echo "  make TEST=hello rtl WAVE=fst          # Hello test with FST waveform"
	@echo "  make rtl-fst-dhry MAX_CYCLES=0        # Dhrystone with FST, unlimited"
	@echo "  make memtrace-simple                  # Memory trace for simple test"
	@echo "  make verify-full                      # Full verification suite"
	@echo ""
	@echo "Performance Tips:"
	@echo "  - No waveform is ~2x faster (use for regression, quick tests)"
	@echo "  - FST is 15x smaller than VCD (22KB vs 330KB for simple test)"
	@echo "  - TRACE=1 adds instruction trace overhead, use only when needed"
	@echo "  - MEMTRACE=1 adds significant logging, use for memory debugging only"
	@echo ""
	@echo "Build Directories:"
	@echo "  build/verilator/      - Default (no waveform) builds"
	@echo "  build/verilator_fst/  - FST waveform builds"
	@echo "  build/verilator_vcd/  - VCD waveform builds"
	@echo "  (Separate dirs allow switching modes without full rebuild)"

# ============================================================================
# Build Targets
# ============================================================================

.PHONY: all
all: sw rtl sim

# Create build directories
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(OBJ_DIR)
	@mkdir -p $(VLT_DIR)

# ============================================================================
# Software Compilation
# ============================================================================

.PHONY: sw
sw: $(BUILD_DIR) $(SW_ELF) $(SW_DUMP)
	@echo "=== Software built successfully (TEST=$(TEST)) ==="
	@$(SIZE) $(SW_ELF)

# Check if TEST has changed and force rebuild if needed
$(TEST_MARKER): $(BUILD_DIR)
	@if [ ! -f $(TEST_MARKER) ] || [ "$$(cat $(TEST_MARKER) 2>/dev/null)" != "$(TEST)" ]; then \
		echo "TEST changed to $(TEST), forcing software rebuild..."; \
		rm -f $(SW_ELF) $(SW_DUMP); \
		echo "$(TEST)" > $(TEST_MARKER); \
	fi

$(SW_ELF): $(TEST_MARKER) $(SW_SOURCES) $(SW_COMMON_DIR)/link.ld
	@echo "Building software for TEST=$(TEST)..."
	$(CC) $(CFLAGS) $(LDFLAGS) $(SW_SOURCES) -o $@

$(SW_DUMP): $(SW_ELF)
	$(OBJDUMP) -D $< > $@

# Pattern rule for software shortcuts
.PHONY: sw-%
sw-%:
	@$(MAKE) TEST=$* sw

# ============================================================================
# RTL Simulation with Verilator
# ============================================================================

# MAX_CYCLES: Set to 0 for unlimited cycles, or specify a number (default: 10M)
MAX_CYCLES ?=

.PHONY: build-verilator
build-verilator: $(BUILD_DIR) $(RTL_SOURCES) $(TB_SOURCES)
	@echo "=== Building RTL simulation with Verilator ==="
	@if [ "$(WAVE)" = "fst" ]; then \
		echo "    Waveform: FST"; \
	elif [ "$(WAVE)" = "vcd" ]; then \
		echo "    Waveform: VCD"; \
	else \
		echo "    Waveform: None (fastest)"; \
	fi
	@if [ "$(TRACE)" = "1" ]; then \
		echo "    RTL trace: Enabled"; \
	else \
		echo "    RTL trace: Disabled"; \
	fi
	$(VERILATOR) $(VLT_FLAGS) \
		--Mdir $(VLT_BUILD_DIR) \
		$(RTL_SOURCES) $(TB_SOURCES) $(shell pwd)/$(TB_DIR)/tb_main.cpp $(shell pwd)/$(TB_DIR)/elfloader.cpp
	@echo "=== RTL simulation binary built ==="

.PHONY: rtl
rtl: sw build-verilator
	@echo "=== Running RTL simulation ==="
	$(VLT_BUILD_DIR)/kcore_vsim +PROGRAM=$(SW_ELF) $(VLT_WAVE_ARG) $(VLT_TRACE_ARG) $(if $(MAX_CYCLES),+MAX_CYCLES=$(MAX_CYCLES)) | tee $(BUILD_DIR)/rtl_output.log
	@echo "=== RTL simulation complete ==="
	@if [ -f rtl_trace.txt ]; then mv rtl_trace.txt $(BUILD_DIR)/; fi
	@if [ -n "$(DUMP_FILE)" ] && [ -f $(DUMP_FILE) ]; then \
		mv $(DUMP_FILE) $(BUILD_DIR)/; \
		echo "Waveform saved to $(BUILD_DIR)/$(DUMP_FILE)"; \
	fi
	@if [ "$(TRACE)" = "1" ] && [ -f $(BUILD_DIR)/rtl_trace.txt ]; then \
		echo "=== Parsing call trace ==="; \
		python3 $(SCRIPTS_DIR)/parse_call_trace.py $(BUILD_DIR)/rtl_trace.txt $(SW_ELF) $(RISCV_PREFIX) $(BUILD_DIR)/call_trace_report.txt; \
		echo "Call trace report: $(BUILD_DIR)/call_trace_report.txt"; \
	fi
ifeq ($(MEMTRACE),1)
	@echo "=== Extracting memory trace ==="
	@grep -E "\[(CPU_IMEM|CPU_DMEM|AXI_MEM)" $(BUILD_DIR)/rtl_output.log > $(BUILD_DIR)/mem_trace.txt || true
	@if [ -s $(BUILD_DIR)/mem_trace.txt ]; then \
		echo "Memory trace saved to $(BUILD_DIR)/mem_trace.txt"; \
		echo "=== Verifying memory transactions ==="; \
		python3 $(MEM_TRACE_VERIFY) $(BUILD_DIR)/mem_trace.txt; \
	else \
		echo "Warning: No memory trace data found (ENABLE_MEM_TRACE may not be set)"; \
	fi
endif

# Pattern rule for building RTL with specific test
.PHONY: build-%
build-%:
	@$(MAKE) TEST=$* build-verilator

# Build RTL for all tests
.PHONY: build-all
build-all:
	@echo "=== Building RTL for all tests ==="
	@for test in $(ALL_TESTS); do \
		echo "" ; \
		echo "======================================" ; \
		echo "Building RTL for test: $$test" ; \
		echo "======================================" ; \
		$(MAKE) TEST=$$test sw build-verilator || exit 1 ; \
	done
	@echo ""
	@echo "======================================"
	@echo "All RTL builds completed successfully"
	@echo "======================================"

# Convenience target for dhrystone benchmark (unlimited cycles)
.PHONY: rtl-dhry
rtl-dhry:
	@$(MAKE) TEST=dhry rtl MAX_CYCLES=0

# FreeRTOS targets - use freertos-rtl-<test>, freertos-sim-<test>, etc.
# FreeRTOS targets - validate, build, then run (skip sw dependency)
.PHONY: freertos-rtl-%
freertos-rtl-%: build-verilator
	@if [ ! -f $(FREERTOS_SAMPLES)/$*.c ]; then \
		echo "Error: FreeRTOS sample '$*' not found"; \
		echo "Expected file: $(FREERTOS_SAMPLES)/$*.c"; \
		echo "Available samples:"; \
		ls -1 $(FREERTOS_SAMPLES)/*.c 2>/dev/null | xargs -n1 basename | sed 's/\.c$$//' | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) freertos-$*
	@echo "=== Running FreeRTOS Test: $* ==="
	$(VLT_BUILD_DIR)/kcore_vsim +PROGRAM=$(SW_ELF) $(VLT_WAVE_ARG) $(VLT_TRACE_ARG) $(if $(MAX_CYCLES),+MAX_CYCLES=$(MAX_CYCLES)) | tee $(BUILD_DIR)/rtl_output.log
	@if [ -f rtl_trace.txt ]; then mv rtl_trace.txt $(BUILD_DIR)/; fi
	@if [ -n "$(DUMP_FILE)" ] && [ -f $(DUMP_FILE) ]; then \
		mv $(DUMP_FILE) $(BUILD_DIR)/; \
		echo "Waveform saved to $(BUILD_DIR)/$(DUMP_FILE)"; \
	fi
	@if [ "$(TRACE)" = "1" ] && [ -f $(BUILD_DIR)/rtl_trace.txt ]; then \
		echo "=== Parsing call trace ==="; \
		python3 $(SCRIPTS_DIR)/parse_call_trace.py $(BUILD_DIR)/rtl_trace.txt $(SW_ELF) $(RISCV_PREFIX) $(BUILD_DIR)/call_trace_report.txt; \
		echo "Call trace report: $(BUILD_DIR)/call_trace_report.txt"; \
	fi
	@echo "=== FreeRTOS test complete ==="

.PHONY: freertos-sim-%
freertos-sim-%: build-sim
	@if [ ! -f $(FREERTOS_SAMPLES)/$*.c ]; then \
		echo "Error: FreeRTOS sample '$*' not found"; \
		echo "Expected file: $(FREERTOS_SAMPLES)/$*.c"; \
		echo "Available samples:"; \
		ls -1 $(FREERTOS_SAMPLES)/*.c 2>/dev/null | xargs -n1 basename | sed 's/\.c$$//' | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) freertos-$*
	@echo "=== Running FreeRTOS Test in Simulator: $* ==="
	@if [ "$(MAX_CYCLES)" != "" ] && [ "$(MAX_CYCLES)" != "0" ]; then \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt --instructions=$(MAX_CYCLES) -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	else \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	fi

.PHONY: freertos-compare-%
freertos-compare-%:
	@if [ ! -f $(FREERTOS_SAMPLES)/$*.c ]; then \
		echo "Error: FreeRTOS sample '$*' not found"; \
		echo "Expected file: $(FREERTOS_SAMPLES)/$*.c"; \
		echo "Available samples:"; \
		ls -1 $(FREERTOS_SAMPLES)/*.c 2>/dev/null | xargs -n1 basename | sed 's/\.c$$//' | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) freertos-$*
	@echo "=== Running and comparing FreeRTOS test: $* ==="
	@$(MAKE) freertos-rtl-$* TRACE=1
	@if [ "$(MAX_CYCLES)" != "" ] && [ "$(MAX_CYCLES)" != "0" ]; then \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt --instructions=$(MAX_CYCLES) -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	else \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	fi
	@python3 $(TRACE_COMPARE) $(BUILD_DIR)/rtl_trace.txt $(BUILD_DIR)/sim_trace.txt

# Pattern rule for test shortcuts
.PHONY: rtl-%
rtl-%: sw
	@if [ ! -d $(SW_DIR)/$* ] && [ ! -f $(SW_DIR)/$*.c ]; then \
		echo "Error: Test '$*' not found"; \
		echo "Expected: $(SW_DIR)/$*/ (directory) or $(SW_DIR)/$*.c (file)"; \
		echo "Available tests:"; \
		find $(SW_DIR) -mindepth 1 -maxdepth 1 -type d ! -name "common" ! -name "include" -exec basename {} \; | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) TEST=$* build-verilator
	@$(MAKE) TEST=$* rtl

# Run all tests
.PHONY: rtl-all
rtl-all:
	@echo "=== Running all RTL tests ==="
	@for test in $(ALL_TESTS); do \
		echo "" ; \
		echo "======================================" ; \
		echo "Running RTL test: $$test" ; \
		echo "======================================" ; \
		$(MAKE) TEST=$$test rtl || exit 1 ; \
	done
	@echo ""
	@echo "======================================"
	@echo "All RTL tests completed successfully"
	@echo "======================================"

# ============================================================================
# Software Simulator
# ============================================================================

.PHONY: build-sim
build-sim: $(BUILD_DIR) $(SIM_BIN)

$(SIM_BIN):
	@echo "Building software simulator..."
	$(MAKE) -C $(SIM_DIR)

.PHONY: sim
sim: build-sim sw
	@echo "=== Running software simulator ==="
	@if [ "$(MAX_CYCLES)" != "" ] && [ "$(MAX_CYCLES)" != "0" ]; then \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt --instructions=$(MAX_CYCLES) -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	else \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	fi
	@echo "=== Software simulation complete ==="

# Pattern rule: sim-<test_name>
.PHONY: sim-%
sim-%:
	@$(MAKE) TEST=$* sim

# ============================================================================
# Trace Comparison
# ============================================================================

.PHONY: compare
compare: $(TRACE_CMP)
	@$(MAKE) TRACE=1 rtl
	@$(MAKE) TRACE=1 sim
	@echo "=== Comparing traces ==="
	@python3 $(TRACE_CMP) $(BUILD_DIR)/rtl_trace.txt $(BUILD_DIR)/sim_trace.txt

# Pattern rule: compare-<test_name>
.PHONY: compare-%
compare-%:
	@$(MAKE) TEST=$* compare

# Compare all tests
.PHONY: compare-all
compare-all:
	@echo "=== Comparing all tests ==="
	@for test in $(ALL_TESTS); do \
		echo "" ; \
		echo "======================================" ; \
		echo "Comparing test: $$test" ; \
		echo "======================================" ; \
		$(MAKE) TEST=$$test compare || exit 1 ; \
	done
	@echo ""
	@echo "======================================"
	@echo "All tests compared successfully"
	@echo "======================================"

# ============================================================================
# Memory Trace Verification
# ============================================================================

.PHONY: memtrace
memtrace:
	@$(MAKE) MEMTRACE=1 rtl

# Pattern rule: memtrace-<test_name>
.PHONY: memtrace-%
memtrace-%:
	@$(MAKE) TEST=$* MEMTRACE=1 rtl

# ============================================================================
# Verification Flow
# ============================================================================

.PHONY: verify
verify: clean all sim rtl compare
	@echo ""
	@echo "========================================"
	@echo "Verification Complete (TEST=$(TEST))"
	@echo "========================================"
	@echo "RTL output: $(BUILD_DIR)/rtl_output.log"
	@echo "SIM output: $(BUILD_DIR)/sim_output.log"
	@echo "Waveform:   $(BUILD_DIR)/dump.fst"
	@echo "========================================"

# Pattern-based verification targets: verify-<test_name>
# Examples: make verify-simple, make verify-full, make verify-hello
.PHONY: verify-%
verify-%:
	@if [ ! -d $(SW_DIR)/$* ] && [ ! -f $(SW_DIR)/$*.c ]; then \
		echo "Error: Test '$*' not found"; \
		echo "Expected: $(SW_DIR)/$*/ (directory) or $(SW_DIR)/$*.c (file)"; \
		echo "Available tests:"; \
		find $(SW_DIR) -mindepth 1 -maxdepth 1 -type d ! -name "common" ! -name "include" -exec basename {} \; | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) TEST=$* verify

# Verify all tests
.PHONY: verify-all
verify-all:
	@echo "=== Verifying all tests ==="
	@for test in $(ALL_TESTS); do \
		echo "" ; \
		echo "======================================" ; \
		echo "Verifying test: $$test" ; \
		echo "======================================" ; \
		$(MAKE) TEST=$$test verify || exit 1 ; \
	done
	@echo ""
	@echo "======================================"
	@echo "All tests verified successfully"
	@echo "======================================"

# ============================================================================
# Waveform Viewing
# ============================================================================

.PHONY: wave
wave:
	@if [ -f $(BUILD_DIR)/dump.fst ]; then \
		gtkwave $(BUILD_DIR)/dump.fst &; \
	else \
		echo "Error: Waveform file not found. Run 'make rtl' first."; \
	fi

# ============================================================================
# Clean
# ============================================================================

.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -f rtl_trace.txt sim_trace.txt dump.fst dump.vcd
	@$(MAKE) -C $(FORMAL_DIR) clean 2>/dev/null || true

.PHONY: clean-all
clean-all: clean zephyr-clean-all arch-test-clean-all syn-cleanall
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@echo "Deep clean complete."

# ============================================================================
# RISC-V Architectural Compliance Testing (RISCOF)
# ============================================================================

# Directories for RISCOF
RISCOF_DIR = verif/riscof_targets
RISCOF_VENV = $(RISCOF_DIR)/.venv
RISCOF_ACTIVATE = . .venv/bin/activate
RISCOF_CONFIG = $(RISCOF_DIR)/config.ini
ARCH_TEST_SUITE = verif/riscv-arch-test/riscv-test-suite
ARCH_TEST_ENV = $(ARCH_TEST_SUITE)/env
RISCOF_WORK = $(RISCOF_DIR)/riscof_work
# Remove debug flag for faster execution
RISCOF_DEBUG = #--verbose debug

# RISCOF environment variables
export LC_ALL = C.UTF-8
export LANG = C.UTF-8

.PHONY: arch-test arch-test-info

arch-test: arch-test-info

arch-test-info:
	@echo ""
	@echo "=========================================="
	@echo "RISC-V Architectural Compliance Testing"
	@echo "=========================================="
	@echo ""
	@echo "RISCOF (RISC-V Architectural Test Framework) verifies that the CPU"
	@echo "core correctly implements the RISC-V ISA specification by running"
	@echo "the official RISC-V architectural test suite."
	@echo ""
	@echo "Available Test Suites:"
	@echo "  RV32I    - Base integer instruction set (32-bit)"
	@echo "  RV32M    - Integer multiplication and division extension"
	@echo "  RV32A    - Atomic instruction extension"
	@echo "  RV32Zicsr - Control and Status Register (CSR) instructions"
	@echo ""
	@echo "Reference Models:"
	@echo "  spike (default) - Official RISC-V ISA simulator"
	@echo "  rv32sim        - kcore custom RV32IMAC software simulator"
	@echo ""
	@echo "Available Commands:"
	@echo "  make arch-test-setup       - Set up RISCOF environment (Python venv + install)"
	@echo "  make arch-test-validate    - Validate RISCOF configuration files"
	@echo "  make arch-test-rv32i       - Run RV32I base instruction tests"
	@echo "  make arch-test-rv32m       - Run RV32M multiply/divide tests"
	@echo "  make arch-test-rv32a       - Run RV32A atomic instruction tests"
	@echo "  make arch-test-rv32zicsr   - Run Zicsr CSR instruction tests"
	@echo "  make arch-test-all         - Run all architectural tests (I+M+A+Zicsr)"
	@echo "  make arch-test-sim         - Test rv32sim software simulator"
	@echo "  make arch-test-report      - Open test report in browser"
	@echo "  make arch-test-clean       - Clean RISCOF work directory"
	@echo "  make arch-test-clean-all   - Clean work directory and virtual environment"
	@echo ""
	@echo "Examples:"
	@echo "  make arch-test-setup       # First time setup"
	@echo "  make arch-test-rv32i       # Run base instruction tests on RTL"
	@echo "  make arch-test-all         # Run all test suites on RTL"
	@echo "  make arch-test-sim         # Test software simulator"
	@echo "  make arch-test-report      # View results"
	@echo ""
	@echo "Configuration:"
	@echo "  RISCOF directory: $(RISCOF_DIR)"
	@echo "  Virtual env:      $(RISCOF_VENV)"
	@echo "  Test suite:       $(ARCH_TEST_SUITE)"
	@echo "  Work directory:   $(RISCOF_WORK)"
	@echo "  RTL config:       config_rtl.ini"
	@echo "  Sim config:       config_sim.ini"
	@echo ""
	@if [ -d "$(RISCOF_VENV)" ]; then \
		echo "Status: RISCOF environment is set up"; \
	else \
		echo "Status: RISCOF environment not set up (run 'make arch-test-setup')"; \
	fi
	@if [ -f "$(BUILD_DIR)/rv32sim" ]; then \
		echo "Status: rv32sim built and available"; \
	else \
		echo "Status: rv32sim not built (run 'make arch-test-setup')"; \
	fi
	@echo ""
	@echo "For detailed instructions, see: $(RISCOF_DIR)/README.md"
	@echo ""

.PHONY: arch-test-setup
arch-test-setup:
	@echo "=== Setting up RISCOF environment ==="
	@if [ ! -d "$(RISCOF_VENV)" ]; then \
		echo "Creating Python virtual environment..."; \
		python3 -m venv $(RISCOF_VENV); \
		echo "Installing RISCOF..."; \
		bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && PIP_USER=false pip3 install --quiet --upgrade pip setuptools wheel"; \
		bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && PIP_USER=false pip3 install --quiet git+https://github.com/riscv/riscof.git@d38859f85fe407bcacddd2efcd355ada4683aee4"; \
		echo "RISCOF setup complete."; \
	else \
		echo "RISCOF virtual environment already exists."; \
	fi
	@echo "=== Building rv32sim reference simulator ==="
	@$(MAKE) -C sim clean
	@$(MAKE) -C sim
	@if [ -f "$(BUILD_DIR)/rv32sim" ]; then \
		echo "rv32sim built successfully: $(BUILD_DIR)/rv32sim"; \
	else \
		echo "Warning: rv32sim build failed"; \
	fi
	@echo "=== RISCOF version: ==="
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof --version"
	@echo ""
	@echo "Setup complete! Reference models available:"
	@echo "  - spike (default): Official RISC-V ISA simulator"
	@echo "  - rv32sim: kcore software simulator (built)"
	@echo ""
	@echo "See $(RISCOF_DIR)/README.md for details"

.PHONY: arch-test-validate
arch-test-validate: arch-test-setup
	@echo "=== Validating RISCOF configuration ==="
	cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof validateyaml --config=config_rtl.ini

.PHONY: arch-test-build
arch-test-build: build-verilator
	@echo "=== Verilator simulation binary ready for architectural tests ==="

.PHONY: arch-test-rv32i
arch-test-rv32i: arch-test-setup arch-test-build
	@echo "=== Running RV32I architectural tests ==="
	@mkdir -p $(RISCOF_WORK)
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof $(RISCOF_DEBUG) run --config=config_rtl.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/I --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32I tests complete. Report: $(RISCOF_WORK)/report.html ==="

.PHONY: arch-test-rv32m
arch-test-rv32m: arch-test-setup arch-test-build
	@echo "=== Running RV32M (Multiply/Divide) architectural tests ==="
	@mkdir -p $(RISCOF_WORK)
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof $(RISCOF_DEBUG) run --config=config_rtl.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/M --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32M tests complete. Report: $(RISCOF_WORK)/report.html ==="

.PHONY: arch-test-rv32a
arch-test-rv32a: arch-test-setup arch-test-build
	@echo "=== Running RV32A (Atomics) architectural tests ==="
	@mkdir -p $(RISCOF_WORK)
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof $(RISCOF_DEBUG) run --config=config_rtl.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/A --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32A tests complete. Report: $(RISCOF_WORK)/report.html ==="

.PHONY: arch-test-rv32zicsr
arch-test-rv32zicsr: arch-test-setup arch-test-build
	@echo "=== Running RV32 Zicsr (CSR) architectural tests ==="
	@mkdir -p $(RISCOF_WORK)
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof $(RISCOF_DEBUG) run --config=config_rtl.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/privilege --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32 Zicsr tests complete. Report: $(RISCOF_WORK)/report.html ==="

.PHONY: arch-test-all
arch-test-all: arch-test-rv32i arch-test-rv32m arch-test-rv32a arch-test-rv32zicsr arch-test-sim
	@echo "=== All architectural tests complete ==="
	@echo "View report: firefox $(RISCOF_WORK)/report.html"
# ============================================================================
# rv32sim Validation Tests (DUT=rv32sim, REF=spike)
# ============================================================================

.PHONY: arch-test-sim
arch-test-sim: arch-test-setup
	@echo "========================================================================"
	@echo "rv32sim Architectural Validation (DUT=rv32sim, REF=spike)"
	@echo "========================================================================"
	@if [ ! -f "$(BUILD_DIR)/rv32sim" ]; then \
		echo "Building rv32sim..."; \
		$(MAKE) -C sim || { echo "Error: Failed to build rv32sim"; exit 1; }; \
	fi
	@if [ ! -f "$(RISCOF_DIR)/config_sim.ini" ]; then \
		echo "Error: config_sim.ini not found"; \
		exit 1; \
	fi
	@echo ""
	@echo "=== Running RV32I tests with rv32sim ==="
	@mkdir -p $(RISCOF_WORK)
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof run --config=config_sim.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/I --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32I tests complete ==="
	@echo ""
	@echo "=== Running RV32M tests with rv32sim ==="
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof run --config=config_sim.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/M --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32M tests complete ==="
	@echo ""
	@echo "=== Running RV32A tests with rv32sim ==="
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof run --config=config_sim.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/A --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32A tests complete ==="
	@echo ""
	@echo "=== Running RV32 Zicsr tests with rv32sim ==="
	@bash -c "cd $(RISCOF_DIR) && $(RISCOF_ACTIVATE) && riscof run --config=config_sim.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/privilege --env=../riscv-arch-test/riscv-test-suite/env --work-dir=riscof_work --no-browser"
	@echo "=== RV32 Zicsr tests complete ==="
	@echo ""
	@echo "========================================================================"
	@echo "rv32sim Validation Complete"
	@echo "========================================================================"
	@echo "Report: $(RISCOF_WORK)/report.html"
	@echo ""
	@if [ -f "$(RISCOF_WORK)/report.html" ]; then \
		grep -E "(Passed|Failed)" $(RISCOF_WORK)/report.html | head -5 || true; \
	fi

.PHONY: arch-test-report
arch-test-report:
	@if [ -f "$(RISCOF_WORK)/report.html" ]; then \
		echo "Opening test report..."; \
		xdg-open $(RISCOF_WORK)/report.html 2>/dev/null || \
		firefox $(RISCOF_WORK)/report.html 2>/dev/null || \
		echo "Please open $(RISCOF_WORK)/report.html in a browser"; \
	else \
		echo "Error: No report found. Run 'make arch-test-all' first."; \
	fi

.PHONY: arch-test-clean
arch-test-clean:
	@echo "Cleaning RISCOF work directory and test artifacts..."
	rm -rf $(RISCOF_WORK)
	find verif/riscv-arch-test/riscv-test-suite -name "*.elf" -type f -delete 2>/dev/null || true
	find verif/riscv-arch-test/riscv-test-suite -name "*.signature" -type f -delete 2>/dev/null || true
	@echo "RISCOF work directory cleaned."

.PHONY: arch-test-clean-all
arch-test-clean-all: arch-test-clean
	@echo "Removing RISCOF virtual environment..."
	rm -rf $(RISCOF_VENV)
	@echo "RISCOF environment cleaned."

# ============================================================================
# Help
# ============================================================================

# Help target moved to top of file as default target

.PHONY: info
info:
	@echo "Project Configuration:"
	@echo "  Toolchain:  $(RISCV_PREFIX)"
	@echo "  Verilator:  $(VERILATOR)"
	@echo "  Spike:      $(SPIKE)"
	@echo "  SW Sim:     $(SW_SIM) (USE_SPIKE=$(USE_SPIKE))"
	@echo "  RISC-V ISA: $(ARCH)"
	@echo "  ABI:        $(ABI)"
	@echo ""
	@echo "Directories:"
	@echo "  RTL:        $(RTL_DIR)"
	@echo "  Testbench:  $(TB_DIR)"
	@echo "  Software:   $(SW_DIR)"
	@echo "  Simulator:  $(SIM_DIR)"
	@echo "  Formal:     $(FORMAL_DIR)"
	@echo "  Arch Test:  $(ARCH_TEST_SUITE)"
	@echo "  Build:      $(BUILD_DIR)"

# ========================================================================
# Formal Verification
# ========================================================================

.PHONY: formal formal-info formal-check formal-clean

formal: formal-info

formal-info:
	@echo ""
	@echo "=========================================="
	@echo "RISC-V Formal Verification"
	@echo "=========================================="
	@echo ""
	@echo "Formal verification uses the riscv-formal framework to verify"
	@echo "the CPU core against the RISC-V ISA specification."
	@echo ""
	@echo "Prerequisites:"
	@echo "  1. Install SymbiYosys (sby)"
	@echo "  2. Install Yosys"
	@echo "  3. Install a formal solver (Yices, Z3, Boolector, or ABC)"
	@echo "  4. Clone riscv-formal: git clone https://github.com/SymbioticEDA/riscv-formal.git"
	@echo "  5. Set RISCV_FORMAL environment variable: export RISCV_FORMAL=/path/to/riscv-formal"
	@echo ""
	@echo "Commands:"
	@echo "  make formal-check     - Run formal verification checks"
	@echo "  make formal-info      - Show formal verification information"
	@echo "  make formal-clean     - Clean formal verification results"
	@echo ""
	@echo "For detailed instructions, see: $(FORMAL_DIR)/README.md"
	@echo ""

formal-check:
	@echo "Running formal verification..."
	@$(MAKE) -C $(FORMAL_DIR) check

formal-clean:
	@echo "Cleaning formal verification results..."
	@$(MAKE) -C $(FORMAL_DIR) clean

# ========================================================================
# Synthesis
# ========================================================================

SYN_DIR = syn

.PHONY: syn syn-info

# syn and syn-info show help
syn: syn-info

syn-info:
	@$(MAKE) -C $(SYN_DIR) help

# syn-<target> pattern rule - forwards any target to syn/Makefile
syn-%:
	@$(MAKE) -C $(SYN_DIR) $*

# ========================================================================
# FreeRTOS Builds
# ========================================================================

FREERTOS_DIR = rtos/freertos
FREERTOS_SAMPLES = $(FREERTOS_DIR)/samples
FREERTOS_SYS = $(FREERTOS_DIR)/sys
FREERTOS_PORT = $(FREERTOS_DIR)/portable/RISC-V
FREERTOS_INCLUDE = $(FREERTOS_DIR)/include

.PHONY: freertos freertos-info

freertos: freertos-info

freertos-info:
	@echo ""
	@echo "=========================================="
	@echo "FreeRTOS Integration"
	@echo "=========================================="
	@echo ""
	@echo "FreeRTOS is a real-time operating system kernel for embedded systems."
	@echo "This project includes FreeRTOS with RISC-V port and sample applications."
	@echo ""
	@echo "Available FreeRTOS Commands:"
	@echo "  make freertos-<test>        - Build FreeRTOS test sample"
	@echo "  make freertos-rtl-<test>    - Run FreeRTOS test in RTL simulation"
	@echo "  make freertos-sim-<test>    - Run FreeRTOS test in ISS simulator"
	@echo "  make freertos-compare-<test> - Compare FreeRTOS RTL vs Spike traces"
	@echo ""
	@echo "Examples:"
	@echo "  make freertos-rtl-simple TRACE=1 MAX_CYCLES=0"
	@echo "  make freertos-sim-simple"
	@echo "  make freertos-compare-simple"
	@echo ""
	@echo "Available FreeRTOS Samples:"
	@ls -1 $(FREERTOS_SAMPLES)/*.c 2>/dev/null | xargs -n1 basename | sed 's/\.c$$//' | sed 's/^/  /' || echo "  (none found)"
	@echo ""
	@echo "FreeRTOS Directory Structure:"
	@echo "  Source:   $(FREERTOS_DIR)"
	@echo "  Samples:  $(FREERTOS_SAMPLES)"
	@echo "  Port:     $(FREERTOS_PORT)"
	@echo "  System:   $(FREERTOS_SYS)"
	@echo ""
	@echo "For more information, see: $(FREERTOS_DIR)/README.md"
	@echo ""

# ========================================================================
# Zephyr RTOS Builds
# ========================================================================

ZEPHYR_DIR = rtos/zephyr
ZEPHYR_VENV = $(ZEPHYR_DIR)/.venv
ZEPHYR_SAMPLES = $(ZEPHYR_DIR)/samples
# ZEPHYR_BASE is defined in env.config
# Use cross-compile toolchain variant to use RISC-V toolchain from env.config
ZEPHYR_TOOLCHAIN_VARIANT = cross-compile

# Zephyr build output directories
ZEPHYR_BUILD_DIR = $(BUILD_DIR)/zephyr

.PHONY: zephyr zephyr-info

zephyr: zephyr-info

zephyr-info:
	@echo ""
	@echo "=========================================="
	@echo "Zephyr RTOS Integration"
	@echo "=========================================="
	@echo ""
	@echo "Zephyr is a scalable real-time operating system (RTOS) supporting"
	@echo "multiple hardware architectures, optimized for resource constrained"
	@echo "and embedded systems."
	@echo ""
	@echo "Prerequisites:"
	@echo "  1. Set ZEPHYR_BASE environment variable (in env.config)"
	@echo "  2. Install Zephyr SDK or configure cross-compile toolchain"
	@echo "  3. Run 'make zephyr-venv-setup' to create Python virtual environment"
	@echo ""
	@echo "Available Zephyr Commands:"
	@echo "  make zephyr-venv-setup      - Set up Python virtual environment"
	@echo "  make zephyr-<sample>        - Build Zephyr sample application"
	@echo "  make zephyr-rtl-<sample>    - Run Zephyr sample in RTL simulation"
	@echo "  make zephyr-sim-<sample>    - Run Zephyr sample in ISS simulator"
	@echo "  make zephyr-compare-<sample> - Compare Zephyr RTL vs Spike traces"
	@echo "  make zephyr-clean           - Clean Zephyr build directories"
	@echo "  make zephyr-clean-all       - Clean build and virtual environment"
	@echo ""
	@echo "Examples:"
	@echo "  make zephyr-rtl-hello TRACE=1 MAX_CYCLES=0"
	@echo "  make zephyr-sim-hello"
	@echo "  make zephyr-compare-philosophers"
	@echo ""
	@echo "Available Zephyr Samples:"
	@ls -1d $(ZEPHYR_SAMPLES)/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /' || echo "  (none found)"
	@echo ""
	@echo "Configuration:"
	@echo "  ZEPHYR_BASE:      $(ZEPHYR_BASE)"
	@echo "  Toolchain:        $(ZEPHYR_TOOLCHAIN_VARIANT)"
	@echo "  Cross-compile:    $(CROSS_COMPILE)"
	@echo "  Virtual env:      $(ZEPHYR_VENV)"
	@echo ""
	@echo "For more information, see: $(ZEPHYR_DIR)/README.md"
	@echo ""

# FreeRTOS source files
FREERTOS_SOURCES = \
	$(FREERTOS_DIR)/tasks.c \
	$(FREERTOS_DIR)/queue.c \
	$(FREERTOS_DIR)/list.c \
	$(FREERTOS_DIR)/timers.c \
	$(FREERTOS_DIR)/event_groups.c \
	$(FREERTOS_DIR)/stream_buffer.c \
	$(FREERTOS_PORT)/port.c \
	$(FREERTOS_PORT)/portASM.S

# FreeRTOS heap implementation (heap_3 uses malloc/free)
FREERTOS_HEAP = $(FREERTOS_DIR)/portable/MemMang/heap_3.c

# Check if heap_4.c exists, if not we'll need to create it
ifneq ($(wildcard $(FREERTOS_HEAP)),)
FREERTOS_SOURCES += $(FREERTOS_HEAP)
endif

# FreeRTOS compiler flags
FREERTOS_CFLAGS = -march=$(ARCH) -mabi=$(ABI) -O2 -g -Wall
FREERTOS_CFLAGS += -ffreestanding -nostartfiles
FREERTOS_CFLAGS += -ffunction-sections -fdata-sections
FREERTOS_CFLAGS += -I$(FREERTOS_INCLUDE)
FREERTOS_CFLAGS += -I$(FREERTOS_PORT)
FREERTOS_CFLAGS += -I$(FREERTOS_SYS)
FREERTOS_CFLAGS += -I$(SW_DIR)/include

FREERTOS_LDFLAGS = -T $(FREERTOS_SYS)/freertos_link.ld
FREERTOS_LDFLAGS += -Wl,--gc-sections
FREERTOS_LDFLAGS += -Wl,-Map=$(BUILD_DIR)/test.map
FREERTOS_LDFLAGS += -lc -lgcc

# Pattern rule for FreeRTOS tests: freertos-<test> builds rtos/freertos/samples/<test>.c
# Output to standard test.elf files for consistency
.PHONY: freertos-%
freertos-%: $(BUILD_DIR)
	@echo "=== Building FreeRTOS Test: $* ==="
	@if [ ! -f $(FREERTOS_SAMPLES)/$*.c ]; then \
		echo "Error: $(FREERTOS_SAMPLES)/$*.c not found"; \
		exit 1; \
	fi
	@echo "freertos-$*" > $(TEST_MARKER)
	$(CC) $(FREERTOS_CFLAGS) $(FREERTOS_LDFLAGS) \
		$(FREERTOS_SYS)/freertos_start.S \
		$(FREERTOS_SYS)/freertos_syscall.c \
		$(FREERTOS_SAMPLES)/$*.c \
		$(FREERTOS_SOURCES) \
		-o $(SW_ELF)
	$(OBJDUMP) -D $(SW_ELF) > $(SW_DUMP)
	@echo "=== FreeRTOS test built successfully ==="
	@$(SIZE) $(SW_ELF)

# ========================================================================
# Zephyr RTOS Targets
# ========================================================================

# Setup Zephyr Python virtual environment
.PHONY: zephyr-venv-setup
zephyr-venv-setup:
	@echo "=== Setting up Zephyr Python virtual environment ==="
	@if [ ! -d $(ZEPHYR_VENV) ]; then \
		python3 -m venv $(ZEPHYR_VENV); \
		echo "Virtual environment created at $(ZEPHYR_VENV)"; \
	else \
		echo "Virtual environment already exists at $(ZEPHYR_VENV)"; \
	fi
	@echo "Installing Python dependencies..."
	@. $(ZEPHYR_VENV)/bin/activate && pip install --upgrade pip
	@. $(ZEPHYR_VENV)/bin/activate && pip install west cmake ninja jsonschema pyelftools
	@echo "=== Zephyr virtual environment ready ==="
	@echo "To activate: source $(ZEPHYR_VENV)/bin/activate"

# Pattern rule for running Zephyr tests in RTL simulation
# Zephyr targets - validate, build, then run (skip sw dependency)
.PHONY: zephyr-rtl-%
zephyr-rtl-%: build-verilator
	@if [ ! -d $(ZEPHYR_SAMPLES)/$* ]; then \
		echo "Error: Zephyr sample '$*' not found"; \
		echo "Expected directory: $(ZEPHYR_SAMPLES)/$*"; \
		echo "Available samples:"; \
		ls -1d $(ZEPHYR_SAMPLES)/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) zephyr-$*
	@echo "=== Running Zephyr Test: $* ==="
	$(VLT_BUILD_DIR)/kcore_vsim +PROGRAM=$(SW_ELF) $(VLT_WAVE_ARG) $(VLT_TRACE_ARG) $(if $(MAX_CYCLES),+MAX_CYCLES=$(MAX_CYCLES)) | tee $(BUILD_DIR)/rtl_output.log
	@if [ -f rtl_trace.txt ]; then mv rtl_trace.txt $(BUILD_DIR)/; fi
	@if [ -n "$(DUMP_FILE)" ] && [ -f $(DUMP_FILE) ]; then \
		mv $(DUMP_FILE) $(BUILD_DIR)/; \
		echo "Waveform saved to $(BUILD_DIR)/$(DUMP_FILE)"; \
	fi
	@if [ "$(TRACE)" = "1" ] && [ -f $(BUILD_DIR)/rtl_trace.txt ]; then \
		echo "=== Parsing call trace ==="; \
		python3 $(SCRIPTS_DIR)/parse_call_trace.py $(BUILD_DIR)/rtl_trace.txt $(SW_ELF) $(RISCV_PREFIX) $(BUILD_DIR)/call_trace_report.txt; \
		echo "Call trace report: $(BUILD_DIR)/call_trace_report.txt"; \
	fi
	@echo "=== Zephyr test complete ==="

.PHONY: zephyr-sim-%
zephyr-sim-%: build-sim
	@if [ ! -d $(ZEPHYR_SAMPLES)/$* ]; then \
		echo "Error: Zephyr sample '$*' not found"; \
		echo "Expected directory: $(ZEPHYR_SAMPLES)/$*"; \
		echo "Available samples:"; \
		ls -1d $(ZEPHYR_SAMPLES)/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) zephyr-$*
	@echo "=== Running Zephyr Test in Simulator: $* ==="
	@if [ "$(MAX_CYCLES)" != "" ] && [ "$(MAX_CYCLES)" != "0" ]; then \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt --instructions=$(MAX_CYCLES) -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	else \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	fi

.PHONY: zephyr-compare-%
zephyr-compare-%:
	@if [ ! -d $(ZEPHYR_SAMPLES)/$* ]; then \
		echo "Error: Zephyr sample '$*' not found"; \
		echo "Expected directory: $(ZEPHYR_SAMPLES)/$*"; \
		echo "Available samples:"; \
		ls -1d $(ZEPHYR_SAMPLES)/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) zephyr-$*
	@echo "=== Running and comparing Zephyr test: $* ==="
	@$(MAKE) zephyr-rtl-$* TRACE=1
	@if [ "$(MAX_CYCLES)" != "" ] && [ "$(MAX_CYCLES)" != "0" ]; then \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt --instructions=$(MAX_CYCLES) -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	else \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	fi
	@python3 $(TRACE_COMPARE) $(BUILD_DIR)/rtl_trace.txt $(BUILD_DIR)/sim_trace.txt

# Pattern rule for Zephyr tests: zephyr-<sample> builds rtos/zephyr/samples/<sample>
# Output to standard test.elf files for consistency
.PHONY: zephyr-%
zephyr-%: $(BUILD_DIR) zephyr-venv-setup
	@echo "=== Building Zephyr Sample: $* ==="
	@if [ ! -d $(ZEPHYR_SAMPLES)/$* ]; then \
		echo "Error: $(ZEPHYR_SAMPLES)/$* not found"; \
		exit 1; \
	fi
	@echo "zephyr-$*" > $(TEST_MARKER)
	@echo "Setting up Zephyr build environment..."
	@echo "Using RISC-V toolchain: $(RISCV_PREFIX)"
	@if [ ! -d "$(ZEPHYR_BASE)" ]; then \
		echo "Error: ZEPHYR_BASE directory not found: $(ZEPHYR_BASE)"; \
		echo "Please set ZEPHYR_BASE to point to your Zephyr installation"; \
		echo "or install Zephyr with: west init ~/zephyrproject && cd ~/zephyrproject && west update"; \
		exit 1; \
	fi
	@# Auto-patch Zephyr kconfig.py to allow warnings from upstream SoCs
	@if [ -f "$(ZEPHYR_BASE)/scripts/kconfig/kconfig.py" ] && \
	   ! grep -q "# PATCHED: Skip error on warnings" "$(ZEPHYR_BASE)/scripts/kconfig/kconfig.py"; then \
		echo "Note: Patching Zephyr kconfig.py to allow warnings from upstream SoCs..."; \
		export ZEPHYR_BASE=$(ZEPHYR_BASE) && bash $(ZEPHYR_DIR)/patch_kconfig.sh || \
		(echo "Warning: Could not patch kconfig.py. Build may fail due to upstream Zephyr warnings."; true); \
	fi
	@. $(ZEPHYR_VENV)/bin/activate && \
		export ZEPHYR_BASE=$(ZEPHYR_BASE) && \
		export ZEPHYR_TOOLCHAIN_VARIANT=$(ZEPHYR_TOOLCHAIN_VARIANT) && \
		export ZEPHYR_MODULES=$(shell pwd)/$(ZEPHYR_DIR) && \
		rm -rf $(ZEPHYR_DIR)/build.$* && \
		cd $(ZEPHYR_SAMPLES)/$* && \
		west build -p -b kcore_board -d $(shell pwd)/$(ZEPHYR_DIR)/build.$* -- \
			-DZEPHYR_BASE=$(ZEPHYR_BASE) \
			-DZEPHYR_TOOLCHAIN_VARIANT=$(ZEPHYR_TOOLCHAIN_VARIANT) \
			-DCROSS_COMPILE=$(CROSS_COMPILE) \
			-DZEPHYR_MODULES=$(shell pwd)/$(ZEPHYR_DIR) \
			-DKCONFIG_ERROR_ON_WARNINGS=OFF

	@echo "Copying ELF file..."
	@cp $(ZEPHYR_DIR)/build.$*/zephyr/zephyr.elf $(SW_ELF)
	$(OBJDUMP) -D $(SW_ELF) > $(SW_DUMP)
	@echo "=== Zephyr sample built successfully ==="
	@$(SIZE) $(SW_ELF)

# Clean Zephyr build directories
.PHONY: zephyr-clean
zephyr-clean:
	@echo "Cleaning Zephyr build directories..."
	@rm -rf $(ZEPHYR_DIR)/build.*
	@echo "Zephyr build directories cleaned"

# Clean Zephyr build and virtual environment
.PHONY: zephyr-clean-all
zephyr-clean-all:
	@echo "Cleaning Zephyr build and virtual environment..."
	@rm -rf $(ZEPHYR_DIR)/build.*
	@rm -rf $(ZEPHYR_VENV)
	@echo "Zephyr build and virtual environment removed"

################################################################################
# NuttX RTOS targets
################################################################################

# NuttX configuration
NUTTX_DIR = rtos/nuttx
NUTTX_BASE ?= $(HOME)/NuttX/nuttx
NUTTX_APPS ?= $(HOME)/NuttX/apps
NUTTX_BOARD = kcore-board
NUTTX_CONFIG = nsh
NUTTX_SAMPLES = $(NUTTX_DIR)/samples

# Check if NuttX is installed
check-nuttx:
	@if [ ! -d "$(NUTTX_BASE)" ]; then \
		echo "Error: NuttX not found at $(NUTTX_BASE)"; \
		echo "Please install NuttX:"; \
		echo "  mkdir -p ~/NuttX && cd ~/NuttX"; \
		echo "  git clone https://github.com/apache/nuttx.git nuttx"; \
		echo "  git clone https://github.com/apache/nuttx-apps.git apps"; \
		echo "Or set NUTTX_BASE to your NuttX installation"; \
		exit 1; \
	fi
	@if [ ! -d "$(NUTTX_APPS)" ]; then \
		echo "Error: NuttX apps not found at $(NUTTX_APPS)"; \
		echo "Please install NuttX apps:"; \
		echo "  cd ~/NuttX"; \
		echo "  git clone https://github.com/apache/nuttx-apps.git apps"; \
		echo "Or set NUTTX_APPS to your NuttX apps installation"; \
		exit 1; \
	fi

# NuttX targets - build, then run (skip sw dependency)
.PHONY: nuttx-rtl-%
nuttx-rtl-%: build-verilator
	@$(MAKE) nuttx-$*
	@echo "=== Running NuttX sample in RTL simulation: $* ==="
	$(VLT_BUILD_DIR)/kcore_vsim +PROGRAM=$(SW_ELF) $(VLT_WAVE_ARG) $(VLT_TRACE_ARG) $(if $(MAX_CYCLES),+MAX_CYCLES=$(MAX_CYCLES)) | tee $(BUILD_DIR)/rtl_output.log
	@if [ -f rtl_trace.txt ]; then mv rtl_trace.txt $(BUILD_DIR)/; fi
	@if [ -n "$(DUMP_FILE)" ] && [ -f $(DUMP_FILE) ]; then \
		mv $(DUMP_FILE) $(BUILD_DIR)/; \
		echo "Waveform saved to $(BUILD_DIR)/$(DUMP_FILE)"; \
	fi
	@echo "=== NuttX RTL simulation completed ==="

.PHONY: nuttx-sim-%
nuttx-sim-%: build-sim
	@$(MAKE) nuttx-$*
	@echo "=== Running NuttX Test: $* ==="
	@if [ "$(MAX_CYCLES)" != "" ] && [ "$(MAX_CYCLES)" != "0" ]; then \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt --instructions=$(MAX_CYCLES) -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	else \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	fi

.PHONY: nuttx-compare-%
nuttx-compare-%:
	@$(MAKE) nuttx-$*
	@echo "=== Comparing NuttX test execution: RTL vs Spike ==="
	@echo "Building and running RTL simulation with trace..."
	@$(MAKE) nuttx-rtl-$* TRACE=1
	@echo ""
	@echo "Running Spike ISA simulator with the same binary..."
	@if [ "$(MAX_CYCLES)" != "" ] && [ "$(MAX_CYCLES)" != "0" ]; then \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt --instructions=$(MAX_CYCLES) -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	else \
		$(SW_SIM) --isa=rv32ima --log-commits --log=$(BUILD_DIR)/sim_trace.txt -m0x80000000:0x200000 $(SW_ELF) | tee $(BUILD_DIR)/sim_output.log; \
	fi
	@echo ""
	@echo "=== Comparing traces: RTL vs Spike ==="
	@if [ -f $(SCRIPTS_DIR)/trace_compare.py ]; then \
		python3 $(SCRIPTS_DIR)/trace_compare.py $(BUILD_DIR)/rtl_trace.txt $(BUILD_DIR)/sim_trace.txt; \
	else \
		echo "Note: trace_compare.py not found. Manual comparison:"; \
		echo "RTL trace:   $(BUILD_DIR)/rtl_trace.txt"; \
		echo "Spike trace: $(BUILD_DIR)/sim_trace.txt"; \
	fi
	@echo "=== NuttX comparison completed ==="

# Pattern rule for NuttX tests: nuttx-<sample> builds rtos/nuttx/samples/<sample>
# Output to standard test.elf files for consistency
.PHONY: nuttx-%
nuttx-%: $(BUILD_DIR) check-nuttx
	@echo "=== Building NuttX Sample: $* ==="
	@if [ ! -d $(NUTTX_SAMPLES)/$* ]; then \
		echo "Error: $(NUTTX_SAMPLES)/$* not found"; \
		exit 1; \
	fi
	@echo "nuttx-$*" > $(TEST_MARKER)
	@mkdir -p $(NUTTX_BASE)/../build-$*
	@# Copy board files to NuttX tree (always update to pick up changes)
	@echo "Syncing kcore board files..."
	@mkdir -p $(NUTTX_BASE)/boards/risc-v/kcore
	@cp -r $(NUTTX_DIR)/boards/risc-v/kcore/kcore-board $(NUTTX_BASE)/boards/risc-v/kcore/
	@cp $(NUTTX_DIR)/boards/risc-v/kcore/Kconfig $(NUTTX_BASE)/boards/risc-v/kcore/Kconfig
	@# Copy chip files to NuttX tree (always update to pick up changes)
	@echo "Syncing kcore chip files..."
	@mkdir -p $(NUTTX_BASE)/arch/risc-v/src/kcore
	@mkdir -p $(NUTTX_BASE)/arch/risc-v/include/kcore
	@cp -r $(NUTTX_DIR)/arch/risc-v/src/kcore/* $(NUTTX_BASE)/arch/risc-v/src/kcore/
	@cp -r $(NUTTX_DIR)/arch/risc-v/include/kcore/* $(NUTTX_BASE)/arch/risc-v/include/kcore/
	@# Patch arch Kconfig to add kcore (always update to pick up changes)
	@echo "Patching arch Kconfig..."
	@cd $(NUTTX_BASE) && git checkout arch/risc-v/Kconfig 2>/dev/null || true
	@python3 $(NUTTX_DIR)/scripts/patch_kconfig.py $(NUTTX_BASE)/arch/risc-v/Kconfig
	@# Copy driver files if they exist (always update to pick up changes)
	@if [ -d $(NUTTX_DIR)/drivers ]; then \
		echo "Syncing kcore drivers..."; \
		if [ -f $(NUTTX_DIR)/drivers/serial/uart_kcore.c ]; then \
			mkdir -p $(NUTTX_BASE)/drivers/serial; \
			cp $(NUTTX_DIR)/drivers/serial/uart_kcore.c $(NUTTX_BASE)/drivers/serial/; \
			if [ ! -f $(NUTTX_BASE)/drivers/serial/Make.defs.orig ]; then \
				cp $(NUTTX_BASE)/drivers/serial/Make.defs $(NUTTX_BASE)/drivers/serial/Make.defs.orig; \
			fi; \
			cat $(NUTTX_BASE)/drivers/serial/Make.defs.orig $(NUTTX_DIR)/drivers/serial/Make.defs > $(NUTTX_BASE)/drivers/serial/Make.defs; \
		fi; \
	fi
	@# Copy sample to apps if it's a custom sample (skip standard NuttX samples like hello)
	@echo "Checking for custom $* sample..."
	@if [ "$*" != "hello" ] && [ -d $(NUTTX_SAMPLES)/$* ] && [ -f $(NUTTX_SAMPLES)/$*/Makefile ]; then \
		echo "Syncing custom $* sample..."; \
		SAMPLE_APP_NAME=$$(grep -h 'default "' $(NUTTX_SAMPLES)/$*/Kconfig 2>/dev/null | head -1 | sed 's/.*default "\([^"]*\)".*/\1/' || echo "$*"); \
		mkdir -p $(NUTTX_APPS)/examples/$${SAMPLE_APP_NAME}; \
		cp -r $(NUTTX_SAMPLES)/$*/* $(NUTTX_APPS)/examples/$${SAMPLE_APP_NAME}/; \
	else \
		echo "Using standard NuttX $* sample"; \
	fi
	@# Configure and build
	@cd $(NUTTX_BASE) && \
		export PATH="$(RISCV_PREFIX_DIR):$$PATH" && \
		(PATH="$(RISCV_PREFIX_DIR):$$PATH" make distclean 2>/dev/null || true) && \
		rm -f .config .config.old && \
		PATH="$(RISCV_PREFIX_DIR):$$PATH" ./tools/configure.sh kcore-board:nsh && \
		PATH="$(RISCV_PREFIX_DIR):$$PATH" make -j$(shell nproc)
	@# Copy output files
	@mkdir -p $(BUILD_DIR)
	@cp $(NUTTX_BASE)/nuttx $(SW_ELF)
	@$(OBJDUMP) -D $(SW_ELF) > $(SW_DUMP)
	@echo "=== NuttX sample built successfully ==="
	@$(SIZE) $(SW_ELF)

# Clean NuttX builds
.PHONY: nuttx-clean
nuttx-clean:
	@echo "Cleaning NuttX builds..."
	@if [ -d "$(NUTTX_BASE)" ]; then \
		cd $(NUTTX_BASE) && \
		PATH="$(RISCV_PREFIX_DIR):$$PATH" make distclean 2>/dev/null || true; \
	fi
	@rm -rf $(NUTTX_BASE)/../build-*
	@echo "NuttX builds cleaned"

# Help for NuttX targets
nuttx: nuttx-info

.PHONY: nuttx-info
nuttx-info:
	@echo "NuttX RTOS targets:"
	@echo "  nuttx-<sample>         - Build NuttX with specified sample from $(NUTTX_SAMPLES)"
	@echo "  nuttx-rtl-<sample>     - Run sample in RTL simulation"
	@echo "  nuttx-sim-<sample>     - Run sample in Spike ISS simulator"
	@echo "  nuttx-compare-<sample> - Compare sample RTL vs Spike traces"
	@echo "  nuttx-clean            - Clean NuttX builds"
	@echo ""
	@echo "Available NuttX samples:"
	@if [ -d $(NUTTX_SAMPLES) ]; then \
		for sample in $$(ls -1 $(NUTTX_SAMPLES) 2>/dev/null || true); do \
			if [ -d $(NUTTX_SAMPLES)/$$sample ]; then \
				echo "  - $$sample"; \
			fi; \
		done; \
	fi
	@echo ""
	@echo "Examples:"
	@echo "  make nuttx-hello           - Build hello world sample"
	@echo "  make nuttx-rtl-hello       - Run hello in RTL simulation"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - NuttX must be installed at $(NUTTX_BASE)"
	@echo "  - NuttX apps at $(NUTTX_APPS)"
	@echo "  - Or set NUTTX_BASE and NUTTX_APPS environment variables"

