# kcore - riscv-formal Integration

**Location**: `verif/formal_configs/riscv-formal-integration/` (in main repo)  
**Symlink**: `riscv-formal/cores/kcore` → `verif/formal_configs/riscv-formal-integration/`

This directory contains the riscv-formal framework integration for the kcore RISC-V processor.

> **Note**: This integration is maintained in the main repository under `verif/formal_configs/riscv-formal-integration/` 
> and symlinked into the riscv-formal submodule. This keeps the integration separate from the submodule
> and ensures it's properly version controlled in your project.

## Setup

The integration uses a symlink approach to avoid modifying the riscv-formal submodule:

```bash
# Run the setup script to create the symlink
./verif/formal_configs/setup-riscv-formal.sh
```

This creates: `riscv-formal/cores/kcore` → `verif/formal_configs/riscv-formal-integration/`

## Status: Partial Integration

The RVFI interface is fully implemented and basic formal verification works (PC alignment, x0 register assertions pass at BMC depth 10). However, full riscv-formal ISA verification has implementation challenges.

## Files

- **checks.cfg**: Configuration for riscv-formal check generation (RV32IM ISA, 1 retirement channel)
- **wrapper.sv**: Wrapper module instantiating kcore with RVFI enabled for formal verification
- **checks/**: Generated verification checks (53 checks for RV32IM instructions and properties)
- **README.md**: This file

## Directory Structure

```
verif/formal_configs/
├── riscv-formal-integration/     # Integration files (in main repo)
│   ├── checks.cfg                # riscv-formal configuration
│   ├── wrapper.sv                # RVFI wrapper for riscv-formal
│   ├── README.md                 # This file
│   ├── .gitignore                # Excludes generated checks/
│   └── checks/                   # Generated checks (gitignored)
├── setup-riscv-formal.sh         # Setup script to create symlink
├── config.mk                     # Configuration parameters
├── Makefile                      # Formal verification build system
├── rvfi_wrapper.sv               # Basic SymbiYosys wrapper
├── formal_basic.sby              # Basic formal verification config
├── README.md                     # Formal verification overview
├── RISCV_FORMAL_SETUP.md         # Setup documentation
└── RVFI_IMPLEMENTATION_REPORT.md # Comprehensive documentation

verif/riscv-formal/               # Submodule (not modified)
├── checks/                       # Check generators
├── cores/                        # Core integration directory
│   └── kcore/                  # → symlink to verif/formal_configs/riscv-formal-integration/
└── [other framework files]        # Framework infrastructure
```

## Current Limitations

### Issue: Instruction Retirement Latency

The kcore design cannot retire instructions within the timeframe expected by riscv-formal checks:

1. **Pipeline Characteristics**:
   - 5-stage pipeline with significant stall cycles
   - CPI (Cycles Per Instruction) ~= 8.8 in typical operation
   - First instruction retirement requires ~9+ cycles after reset

2. **riscv-formal Framework Expectations**:
   - BMC depth 20-80 cycles
   - Expects multiple instruction retirements
   - Standard cores (PicoRV32) retire instructions more quickly

3. **Observed Behavior**:
   - Cover checks fail: Cannot reach even 1 instruction retirement in 50 cycles
   - Instruction checks return PREUNSAT: Assumptions unsatisfiable at check cycle
   - Indicates CPU state doesn't progress to instruction retirement during formal verification

### Root Causes

Possible issues preventing instruction retirement in formal:

1. **Reset/Initialization**: CPU may require specific initialization sequence not captured in formal
2. **Memory Interface**: Even with always-ready memory, CPU may not progress through fetch/decode
3. **Pipeline Stalls**: Formal verification may hit worst-case stall conditions
4. **State Machine**: CPU control flow may have unreachable states in BMC timeframe

## What Works

✅ **RVFI Interface**: Fully functional, all 21 signals properly implemented
✅ **Basic Formal Verification**: PC alignment and x0 register assertions verified with SymbiYosys BMC
✅ **Synthesis**: Design synthesizes correctly for formal verification
✅ **Framework Integration**: Properly integrated with riscv-formal structure

## Recommendations for Full Integration

To enable full riscv-formal ISA verification, the kcore design would need:

1. **Reduce Pipeline Latency**:
   - Optimize stall conditions to reduce CPI
   - Simplify early pipeline stages
   - Target CPI closer to 2-3 for single-issue pipeline

2. **Initialization Optimization**:
   - Ensure CPU can begin fetching immediately after reset
   - Remove unnecessary reset cycles or initialization delays

3. **Alternative Approach**:
   - Use unbounded model checking (prove mode) instead of BMC
   - Increase BMC depth to 200+ cycles (computationally expensive)
   - Create custom checks with larger CHECK_CYCLE values

4. **Design Modifications**:
   - Add fast-path for instruction fetch
   - Reduce dependency on memory latency
   - Simplify branch prediction/hazard detection

## Running the Checks

While the checks don't currently pass, you can attempt to run them:

```bash
# First-time setup: Create symlink from project root
./formal/setup-riscv-formal.sh

# Navigate to the integration directory (via symlink)
cd riscv-formal/cores/kcore

# Generate checks
python3 ../../checks/genchecks.py

# Run a single instruction check (will fail with PREUNSAT)
cd checks
sby -f insn_add_ch0.sby

# Run cover check (will fail - cannot reach cover target)
sby -f cover.sby

# Run all checks in parallel (not recommended - all will fail)
make -j$(nproc)
```

## Repository Structure

Since `riscv-formal/` is a git submodule, the integration files are maintained separately:

- **Integration files**: `verif/formal_configs/riscv-formal-integration/` (version controlled in main repo)
- **Symlink**: `riscv-formal/cores/kcore` → `verif/formal_configs/riscv-formal-integration/`  
- **Setup script**: `verif/formal_configs/setup-riscv-formal.sh` creates the symlink
- **Gitignore**: `riscv-formal/.gitignore` excludes `cores/kcore` from submodule

This approach keeps the riscv-formal submodule clean while maintaining the integration in your project.

## Cleaning Generated Files

The `checks/` directory contains generated verification files (`.sby` configs and execution results).
To clean these temporary files:

```bash
# Clean all formal verification results (from project root)
cd formal
make formal-clean

# Or just clean basic formal results (keeps riscv-formal integration)
make clean
```

The `.gitignore` file in this directory already excludes `checks/` from version control.
