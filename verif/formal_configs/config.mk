# RISC-V Formal Verification Configuration

# XLEN = 32 (32-bit architecture)
XLEN = 32

# ILEN = 32 (32-bit instructions)
ILEN = 32

# Number of instructions retired per cycle
RISCV_FORMAL_NRET = 1

# Channel index for verification
RISCV_FORMAL_CHANNEL_IDX = 0

# ISA extensions to verify
# I = Base integer instruction set
# M = Multiplication and division
# A = Atomic instructions (if implemented)
# C = Compressed instructions (not implemented)
RISCV_FORMAL_ISA = rv32im

# Enable/disable specific instruction groups
RISCV_FORMAL_CHECK_IMM = yes
RISCV_FORMAL_CHECK_REG = yes
RISCV_FORMAL_CHECK_PC = yes
RISCV_FORMAL_CHECK_MEM = yes
RISCV_FORMAL_CHECK_CSR = yes

# Verification depth (number of cycles)
# Higher depth = more thorough but slower verification
RISCV_FORMAL_DEPTH = 15

# Timeout (seconds)
RISCV_FORMAL_TIMEOUT = 300

# Solver to use (yices, z3, boolector, abc)
RISCV_FORMAL_SOLVER = yices

# Verification mode
# bmc = Bounded model checking
# prove = Unbounded proof (if possible)
# cover = Coverage analysis
RISCV_FORMAL_MODE = bmc

# Additional defines
# Uncomment to enable specific features
# RISCV_FORMAL_BLACKBOX_REGS = yes  # Blackbox register file
# RISCV_FORMAL_BLACKBOX_ALU = yes   # Blackbox ALU
# RISCV_FORMAL_ALTOPS = yes         # Alternative operations
