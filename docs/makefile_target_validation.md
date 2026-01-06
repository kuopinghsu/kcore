# Makefile Target Validation

**Date**: January 3, 2026  
**Status**: ✅ Complete

## Overview

Added validation to all pattern-based Makefile targets to check if requested tests/samples exist before attempting to build. This prevents confusing build failures and provides helpful error messages listing available options.

## Problem

When users typed incorrect test or sample names, the Makefile would attempt to build non-existent files, resulting in cryptic error messages:

```bash
$ make zephyr-rtl-aa
# ... (Verilator build completes) ...
=== Building Zephyr Sample: aa ===
Error: /path/to/samples/aa not found
# (Error buried in Zephyr build output)
```

Users had to:
1. Read through build output to find the error
2. Guess the correct test/sample name
3. No list of available options provided

## Solution

Added validation checks at the beginning of each pattern rule to:
1. Verify the requested test/sample exists
2. Show clear error message with expected path
3. List all available options
4. Exit immediately before expensive build steps

## Implementation

### Bare Metal Tests

**Target**: `rtl-%`, `verify-%`

```makefile
.PHONY: rtl-%
rtl-%:
	@if [ ! -d $(SW_DIR)/$* ] && [ ! -f $(SW_DIR)/$*.c ]; then \
		echo "Error: Test '$*' not found"; \
		echo "Expected: $(SW_DIR)/$*/ (directory) or $(SW_DIR)/$*.c (file)"; \
		echo "Available tests:"; \
		find $(SW_DIR) -mindepth 1 -maxdepth 1 -type d ! -name "common" ! -name "include" -exec basename {} \; | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) TEST=$* rtl
```

**Example Error**:
```bash
$ make rtl-aa
Error: Test 'aa' not found
Expected: sw/aa/ (directory) or sw/aa.c (file)
Available tests:
  coremark
  dhry
  embench
  full
  hello
  interrupt
  mibench
  simple
  uart
  whetstone
make: *** [Makefile:373: rtl-aa] Error 1
```

### FreeRTOS Samples

**Targets**: `freertos-rtl-%`, `freertos-sim-%`, `freertos-compare-%`

```makefile
.PHONY: freertos-rtl-%
freertos-rtl-%: build-verilator-only
	@if [ ! -f $(FREERTOS_SAMPLES)/$*.c ]; then \
		echo "Error: FreeRTOS sample '$*' not found"; \
		echo "Expected file: $(FREERTOS_SAMPLES)/$*.c"; \
		echo "Available samples:"; \
		ls -1 $(FREERTOS_SAMPLES)/*.c 2>/dev/null | xargs -n1 basename | sed 's/\.c$$//' | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) freertos-$*
	@echo "=== Running FreeRTOS Test: $* ==="
```

**Example Error**:
```bash
$ make freertos-rtl-aa
Error: FreeRTOS sample 'aa' not found
Expected file: rtos/freertos/samples/aa.c
Available samples:
  perf
  simple
make: *** [Makefile:331: freertos-rtl-aa] Error 1
```

### Zephyr Samples

**Targets**: `zephyr-rtl-%`, `zephyr-sim-%`, `zephyr-compare-%`

```makefile
.PHONY: zephyr-rtl-%
zephyr-rtl-%: build-verilator-only
	@if [ ! -d $(ZEPHYR_SAMPLES)/$* ]; then \
		echo "Error: Zephyr sample '$*' not found"; \
		echo "Expected directory: $(ZEPHYR_SAMPLES)/$*"; \
		echo "Available samples:"; \
		ls -1d $(ZEPHYR_SAMPLES)/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /' || echo "  (none found)"; \
		exit 1; \
	fi
	@$(MAKE) zephyr-$*
	@echo "=== Running Zephyr Sample: $* ==="
```

**Example Error**:
```bash
$ make zephyr-rtl-aa
Error: Zephyr sample 'aa' not found
Expected directory: rtos/zephyr/samples/aa
Available samples:
  hello
  threads_sync
  uart_echo
make: *** [Makefile:927: zephyr-rtl-aa] Error 1
```

## Targets Updated

All pattern-based targets now have validation:

### Bare Metal
- ✅ `make rtl-<test>` - RTL simulation
- ✅ `make verify-<test>` - Full verification

### FreeRTOS
- ✅ `make freertos-rtl-<sample>` - RTL simulation
- ✅ `make freertos-sim-<sample>` - ISS simulation
- ✅ `make freertos-compare-<sample>` - Trace comparison

### Zephyr
- ✅ `make zephyr-rtl-<sample>` - RTL simulation
- ✅ `make zephyr-sim-<sample>` - ISS simulation
- ✅ `make zephyr-compare-<sample>` - Trace comparison

## Benefits

1. **Immediate Feedback**: Error shown before expensive build steps
2. **Clear Messages**: Explicit about what path was expected
3. **Discovery**: Lists all available tests/samples
4. **Time Savings**: Avoids wasting time on failed builds
5. **User-Friendly**: Helps users find correct test names

## Implementation Details

### Check Logic

**Bare Metal Tests**:
- Tests can be directories (`sw/uart/`) OR single files (`sw/uart.c`)
- Check both: `[ ! -d $(SW_DIR)/$* ] && [ ! -f $(SW_DIR)/$*.c ]`
- Excludes `common` and `include` directories

**FreeRTOS Samples**:
- Samples are always `.c` files in `rtos/freertos/samples/`
- Check: `[ ! -f $(FREERTOS_SAMPLES)/$*.c ]`
- List with: `ls -1 $(FREERTOS_SAMPLES)/*.c | xargs -n1 basename | sed 's/\.c$$//'`

**Zephyr Samples**:
- Samples are always directories in `rtos/zephyr/samples/`
- Check: `[ ! -d $(ZEPHYR_SAMPLES)/$* ]`
- List with: `ls -1d $(ZEPHYR_SAMPLES)/*/ | xargs -n1 basename`

### Listing Available Options

Uses shell commands to enumerate and format available tests:

```bash
# Bare metal - find directories, exclude common/include
find $(SW_DIR) -mindepth 1 -maxdepth 1 -type d ! -name "common" ! -name "include" -exec basename {} \; | sed 's/^/  /'

# FreeRTOS - list .c files, strip extension, indent
ls -1 $(FREERTOS_SAMPLES)/*.c 2>/dev/null | xargs -n1 basename | sed 's/\.c$$//' | sed 's/^/  /'

# Zephyr - list directories, indent
ls -1d $(ZEPHYR_SAMPLES)/*/ 2>/dev/null | xargs -n1 basename | sed 's/^/  /'
```

Error suppression (`2>/dev/null`) prevents errors if directories are empty.

## Testing

All validation tested with non-existent names:

```bash
# Tested and working
make rtl-aa                    # ✅ Shows available bare metal tests
make verify-aa                 # ✅ Shows available bare metal tests
make freertos-rtl-aa          # ✅ Shows available FreeRTOS samples
make freertos-sim-aa          # ✅ Shows available FreeRTOS samples
make freertos-compare-aa      # ✅ Shows available FreeRTOS samples
make zephyr-rtl-aa            # ✅ Shows available Zephyr samples
make zephyr-sim-aa            # ✅ Shows available Zephyr samples
make zephyr-compare-aa        # ✅ Shows available Zephyr samples

# Valid tests still work
make rtl-simple               # ✅ Runs successfully
make zephyr-rtl-hello   # ✅ Runs successfully
```

## Files Modified

- **Makefile**: Added validation to 8 pattern rules:
  - `rtl-%` (line ~373)
  - `verify-%` (line ~490)
  - `freertos-rtl-%` (line ~331)
  - `freertos-sim-%` (line ~356)
  - `freertos-compare-%` (line ~371)
  - `zephyr-rtl-%` (line ~927)
  - `zephyr-sim-%` (line ~980)
  - `zephyr-compare-%` (line ~995)

## Future Enhancements

Possible improvements:
- Fuzzy matching to suggest similar test names (e.g., "Did you mean 'simple'?")
- Categorize tests by type (basic, benchmarks, peripherals)
- Add descriptions from README files
- Color-coded output for better visibility
- Tab completion support for bash/zsh
