# Atomic Instructions Status

## Issue Summary
Atomic instructions (RV32A extension) have bugs in the RTL implementation and testbench trace generation.

## Bugs Found and Fixed

### 1. Testbench Trace Bug (FIXED)
**File:** `testbench/tb_soc.sv`

**Problem:** The testbench trace generation only checked for `OP_LOAD` (0x03) when deciding whether to use `mem_data` or `alu_result` for register write values. It didn't handle `OP_AMO` (0x2f), causing LR.W instructions to show the address instead of the loaded value in traces.

**Fix:** Added OP_AMO check:
```systemverilog
assign wb_rd_data = (wb_opcode == 7'b0000011 || wb_opcode == 7'b0101111) ?  // OP_LOAD or OP_AMO
                     u_soc.u_cpu.mem_wb_reg.mem_data :
                     u_soc.u_cpu.mem_wb_reg.alu_result;
```

### 2. SC.W Reservation Tracking (NOT FIXED)
RTL and Spike handle LR.W/SC.W reservation differently, leading to divergent execution paths. SC.W may succeed in one simulator and fail in the other.

## Workaround: Disable Atomic Instructions

Atomic instructions have been disabled in NuttX configuration until fully verified.

**Files Modified:**
1. `rtos/nuttx/arch/risc-v/Kconfig` - Removed `select ARCH_RV_ISA_A` from ARCH_CHIP_KCORE
2. NuttX builds with `-march=rv32im` instead of `-march=rv32ima`

## Test Results

### With Atomics Enabled
- RTL and Spike diverge at instruction 15278 (first LR.W/SC.W sequence)
- Different execution paths due to reservation tracking differences

### With Atomics Disabled  
- ✅ RTL and Spike match perfectly for all 15,276 instructions
- Both simulators execute identically until Spike stops (likely waiting for I/O)
- RTL continues for 9,547 more instructions before hitting unrelated NULL pointer bug

## Recommendations

1. Keep atomic instructions disabled in NuttX until:
   - SC.W reservation tracking is fully verified against RISC-V spec
   - riscv-arch-test atomic tests pass
   
2. For applications requiring atomics:
   - Use software mutexes/critical sections instead
   - Or verify atomic instruction behavior matches hardware requirements

## Related Files
- `testbench/tb_soc.sv` - Trace generation (FIXED)
- `rtl/kcore.sv` - AMO implementation (needs verification)
- `rtos/nuttx/arch/risc-v/Kconfig` - ISA configuration
