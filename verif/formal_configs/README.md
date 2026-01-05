# RISC-V Formal Verification

This directory contains formal verification setup for the RISC-V CPU core.

> **📁 Repository Structure Note**  
> The riscv-formal framework is included as a git submodule. Integration files are maintained
> separately in `verif/formal_configs/riscv-formal-integration/` to avoid modifying the submodule.  
> See [`RISCV_FORMAL_SETUP.md`](RISCV_FORMAL_SETUP.md) for details.

## Quick Links

- **Setup Instructions**: [RISCV_FORMAL_SETUP.md](RISCV_FORMAL_SETUP.md) - How to set up the symlink structure
- **Implementation Report**: [RVFI_IMPLEMENTATION_REPORT.md](RVFI_IMPLEMENTATION_REPORT.md) - Comprehensive documentation
- **Integration Files**: [riscv-formal-integration/](riscv-formal-integration/) - Core integration directory

## Overview

RISC-V Formal is a formal verification framework that checks RISC-V processor implementations against the ISA specification using formal methods (bounded model checking). It verifies:

- **Instruction Consistency**: Each instruction behaves according to RISC-V spec
- **Register File**: Register writes/reads are consistent
- **PC Updates**: Program counter updates correctly
- **Memory Interface**: Load/store operations are coherent
- **CSR Operations**: Control and status registers work correctly

## Prerequisites

1. **SymbiYosys** (sby): Formal verification front-end
   ```bash
   # Install from https://github.com/YosysHQ/SymbiYosys
   ```

2. **Yosys**: Open synthesis suite
   ```bash
   # Install from https://github.com/YosysHQ/yosys
   ```

3. **Formal Verification Solvers**: At least one of:
   - **Yices 2**: SMT solver (recommended)
   - **Z3**: SMT solver
   - **Boolector**: SMT solver
   - **ABC**: SAT-based solver

4. **riscv-formal**: The framework is included as a git submodule
   ```bash
   # Initialize submodule if not already done
   git submodule update --init --recursive verif/riscv-formal
   
   # The Makefile uses relative path: RISCV_FORMAL ?= ../riscv-formal
   # No environment variable needed
   ```

## Quick Start

### 1. Install Prerequisites

```bash
# Install Yosys, SymbiYosys, and solvers
# See https://symbiyosys.readthedocs.io/en/latest/install.html

# Initialize riscv-formal submodule (if not already done)
cd /path/to/riscv/project
git submodule update --init --recursive verif/riscv-formal

# The Makefile will automatically use: RISCV_FORMAL=../riscv-formal
# No environment variable setup needed
```

### 2. Prepare Core Wrapper

The CPU core needs a wrapper that implements the riscv-formal RVFI (RISC-V Formal Interface):

```bash
# Wrapper is provided in verif/formal_configs/rvfi_wrapper.sv
# It adapts kcore.sv to the RVFI interface
```

### 3. Run Verification

```bash
cd verif/formal_configs
make check          # Run all formal checks
make check-insn     # Check instruction consistency
make check-reg      # Check register file
make check-pc       # Check PC updates
make check-mem      # Check memory interface
```

## RVFI Interface

The RISC-V Formal Interface (RVFI) is a standardized interface for formal verification:

### Required Signals (per instruction retired)

```systemverilog
output        rvfi_valid      // Instruction retired
output [63:0] rvfi_order      // Instruction order (increasing)
output [31:0] rvfi_insn       // Instruction word
output        rvfi_trap       // Trap occurred
output        rvfi_halt       // Halt requested
output        rvfi_intr       // Interrupt taken
output [1:0]  rvfi_mode       // Privilege mode
output [1:0]  rvfi_ixl        // XLEN mode

// PC values
output [31:0] rvfi_pc_rdata   // PC before instruction
output [31:0] rvfi_pc_wdata   // PC after instruction

// Register file
output [4:0]  rvfi_rs1_addr   // RS1 address
output [4:0]  rvfi_rs2_addr   // RS2 address
output [31:0] rvfi_rs1_rdata  // RS1 read data
output [31:0] rvfi_rs2_rdata  // RS2 read data
output [4:0]  rvfi_rd_addr    // RD address
output [31:0] rvfi_rd_wdata   // RD write data

// Memory interface
output [31:0] rvfi_mem_addr   // Memory address
output [3:0]  rvfi_mem_rmask  // Read mask
output [3:0]  rvfi_mem_wmask  // Write mask
output [31:0] rvfi_mem_rdata  // Read data
output [31:0] rvfi_mem_wdata  // Write data
```

## Configuration

The `config.sv` file defines verification parameters:

```systemverilog
parameter XLEN = 32;                    // Data width
parameter ILEN = 32;                    // Instruction width
parameter RISCV_FORMAL_NRET = 1;        // Instructions retired per cycle
parameter RISCV_FORMAL_CHANNEL_IDX = 0; // Channel index
```

## Verification Checks

### 1. Instruction Checks (check-insn)
Verifies each instruction type:
- ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
- ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU
- LUI, AUIPC
- BEQ, BNE, BLT, BGE, BLTU, BGEU
- JAL, JALR
- LB, LH, LW, LBU, LHU
- SB, SH, SW
- MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU (M-extension)
- CSR instructions

### 2. Register File Checks (check-reg)
- Register x0 is always zero
- Registers are written only by instructions that should write them
- Register values match expected values

### 3. PC Checks (check-pc)
- PC updates correctly for sequential instructions
- PC updates correctly for branches (taken/not taken)
- PC updates correctly for jumps (JAL, JALR)
- PC updates correctly for exceptions/interrupts

### 4. Memory Checks (check-mem)
- Memory addresses are correctly aligned
- Load/store byte enables are correct
- Memory data is consistent

## Results

Formal verification results are stored in:
- `verif/formal_configs/results/` - Verification logs and traces
- `verif/formal_configs/results/*.log` - Solver output
- `verif/formal_configs/results/*.vcd` - Counterexample waveforms (if failures found)

### Interpreting Results

- **PASS**: Check completed successfully, no violations found
- **FAIL**: Violation found, check counterexample trace
- **UNKNOWN**: Solver timeout or resource limit reached

## Known Limitations

1. **Bounded Verification**: Checks are bounded (typically 10-20 cycles)
   - Does not prove correctness for all possible executions
   - May miss bugs that require longer sequences

2. **State Space**: Complex cores may hit resource limits
   - Consider reducing verification depth
   - Use abstractions for peripherals

3. **Interrupts**: Interrupt timing is non-deterministic
   - May require additional assumptions/constraints

## Customization

### Modify Verification Depth

Edit `.sby` files to adjust verification depth:
```ini
[options]
depth 15  # Increase for more thorough verification
```

### Add Custom Checks

Create custom `.sby` configuration files in `verif/formal_configs/checks/`:
```ini
[tasks]
cover        # Coverage check
bmc          # Bounded model checking
prove        # Unbounded proof (if possible)

[options]
mode bmc
depth 20

[engines]
smtbmc yices

[script]
read -formal rvfi_wrapper.sv
read -formal ../rtl/kcore.sv
prep -top rvfi_wrapper

[files]
rvfi_wrapper.sv
../rtl/kcore.sv
```

## Troubleshooting

### Solver Errors
```bash
# Try different solver
sby -f config.sby smtbmc z3  # Use Z3 instead of Yices
```

### Memory Issues
```bash
# Reduce depth or add resource limits
ulimit -v 8000000  # Limit to 8GB virtual memory
```

### Synthesis Errors
```bash
# Check Yosys can synthesize the design
yosys -p "read_verilog -sv rvfi_wrapper.sv; hierarchy -check"
```

## References

- [riscv-formal GitHub](https://github.com/SymbioticEDA/riscv-formal)
- [RVFI Specification](https://github.com/SymbioticEDA/riscv-formal/blob/master/docs/rvfi.md)
- [SymbiYosys Documentation](https://symbiyosys.readthedocs.io/)
- [RISC-V Formal Verification Paper](https://zipcpu.com/formal/2019/11/18/genuctrlr.html)

## Future Enhancements

1. Add formal verification to CI/CD pipeline
2. Verify interrupt handling formally
3. Add formal properties for pipeline hazards
4. Verify atomic operations (A-extension)
5. Add temporal properties (liveness, fairness)
