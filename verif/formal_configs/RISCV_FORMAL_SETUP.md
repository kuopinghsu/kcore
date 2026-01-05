# riscv-formal Integration Setup

This document explains how the riscv-formal integration is organized.

## Overview

The riscv-formal framework is included as a git submodule at `riscv-verif/formal_configs/`. To avoid polluting the submodule with project-specific integration files, we maintain the integration separately in the main repository and use symlinks.

## Directory Structure

```
verif/formal_configs/
├── riscv-formal-integration/     # Integration files (tracked in main repo)
│   ├── checks.cfg                # Configuration for RV32IM verification
│   ├── wrapper.sv                # RVFI wrapper for riscv-formal
│   ├── README.md                 # Integration documentation
│   ├── .gitignore                # Excludes generated checks/
│   └── checks/                   # Generated checks (not tracked)
│
├── setup-riscv-formal.sh         # Setup script (run this first!)
├── config.mk                     # Configuration parameters
├── Makefile                      # Formal verification build system
├── rvfi_wrapper.sv               # Basic SymbiYosys wrapper
├── formal_basic.sby              # Basic formal verification config
├── README.md                     # Formal verification overview
├── RISCV_FORMAL_SETUP.md         # This file - setup documentation
└── RVFI_IMPLEMENTATION_REPORT.md # Full implementation documentation

verif/riscv-formal/               # Git submodule (not modified)
├── .gitignore                    # Excludes cores/kcore
├── checks/                       # Verification check generators
├── cores/                        # Core integration directory
│   └── kcore/                  # → Symlink to verif/formal_configs/riscv-formal-integration/
└── [other framework files]        # Framework infrastructure
```

## Setup Instructions

### First Time Setup

1. Initialize the riscv-formal submodule (if not already done):
   ```bash
   git submodule update --init --recursive
   ```

2. Run the setup script to create the symlink:
   ```bash
   ./verif/formal_configs/setup-riscv-formal.sh
   ```

   This creates: `riscv-verif/formal_configs/cores/kcore` → `verif/formal_configs/riscv-formal-integration/`

### After Setup

The integration is now ready to use:

```bash
# Generate verification checks
cd riscv-verif/formal_configs/cores/kcore
python3 ../../checks/genchecks.py

# Run checks (see README.md for details)
cd checks
sby -f <check_name>.sby
```

## Why This Approach?

1. **Keeps submodule clean**: No modifications to riscv-formal submodule
2. **Version controlled**: Integration files tracked in main repo at `verif/formal_configs/riscv-formal-integration/`
3. **Standard workflow**: Works with riscv-formal's expected directory structure
4. **Easy setup**: Single script creates necessary symlink

## Git Considerations

### What's Tracked in Main Repo

- `verif/formal_configs/riscv-formal-integration/checks.cfg`
- `verif/formal_configs/riscv-formal-integration/wrapper.sv`  
- `verif/formal_configs/riscv-formal-integration/README.md`
- `verif/formal_configs/riscv-formal-integration/.gitignore`
- `verif/formal_configs/setup-riscv-formal.sh`

### What's Ignored

- `verif/formal_configs/riscv-formal-integration/checks/` (generated files)
- `riscv-verif/formal_configs/cores/kcore` (symlink, excluded in submodule's .gitignore)

### Cleaning Generated Files

The `checks/` directory can grow large with verification results:

```bash
# Clean all formal verification results
cd formal
make formal-clean

# Or just clean basic results (keeps riscv-formal integration)
make clean
```

This removes all generated `.sby` files and execution results from `riscv-formal-integration/checks/`.

### Cloning the Repository

When someone clones your repository:

```bash
git clone <your-repo>
cd <your-repo>
git submodule update --init --recursive
./verif/formal_configs/setup-riscv-formal.sh
```

## Current Status

The integration structure is complete, but riscv-formal checks do not pass due to the CPU's pipeline characteristics:

- ✅ RVFI interface fully functional
- ✅ Integration files properly organized
- ✅ Symlink approach working
- ⚠️ Checks fail: CPU CPI (~9) too high for BMC depths (20-100 cycles)

See `verif/formal_configs/RVFI_IMPLEMENTATION_REPORT.md` for full details.
