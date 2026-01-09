// RISC-V RV32IMAC Functional Simulator
// Software simulator with UART, console magic address, and exit support
// Implements basic RV32IMAC instruction set with special device handling

#include "rv32sim.h"
#include "gdb_stub.h"
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <stdint.h>
#include <string>
#include <vector>
#include <unistd.h>

// Simple UART emulation implementation
UARTDevice::UARTDevice() : tx_data(0), rx_data(0), status(0), tx_busy(false) {}

uint32_t UARTDevice::read(uint32_t offset) {
    if (offset == UART_DATA_REG) {
        // Read RX data
        if (!rx_fifo.empty()) {
            uint8_t data = rx_fifo.front();
            rx_fifo.erase(rx_fifo.begin());
            return data;
        }
        return 0;
    } else if (offset == UART_STATUS_REG) {
        // Status: bit[0]=TX busy, bit[2]=RX ready
        uint32_t status = 0;
        if (tx_busy)
            status |= 0x01;
        if (!rx_fifo.empty())
            status |= 0x04;
        return status;
    }
    return 0;
}

void UARTDevice::write(uint32_t offset, uint32_t value) {
    if (offset == UART_DATA_REG) {
        // Write to TX - output to stdout
        char c = value & 0xFF;
        std::cout << c << std::flush;
        tx_fifo.push_back(c);
        tx_busy = false; // Instant TX for simulation
    }
}

// CLINT device implementation
CLINTDevice::CLINTDevice() : msip(0), mtimecmp(0), mtime(0) {}

uint32_t CLINTDevice::read(uint32_t offset) {
    if (offset == CLINT_MSIP) {
        return msip;
    } else if (offset == CLINT_MTIMECMP) {
        return (uint32_t)(mtimecmp & 0xFFFFFFFF);
    } else if (offset == CLINT_MTIMECMP + 4) {
        return (uint32_t)(mtimecmp >> 32);
    } else if (offset == CLINT_MTIME) {
        return (uint32_t)(mtime & 0xFFFFFFFF);
    } else if (offset == CLINT_MTIME + 4) {
        return (uint32_t)(mtime >> 32);
    }
    return 0;
}

void CLINTDevice::write(uint32_t offset, uint32_t value) {
    if (offset == CLINT_MSIP) {
        msip = value & 1;
    } else if (offset == CLINT_MTIMECMP) {
        mtimecmp = (mtimecmp & 0xFFFFFFFF00000000ULL) | value;
    } else if (offset == CLINT_MTIMECMP + 4) {
        mtimecmp = (mtimecmp & 0xFFFFFFFF) | ((uint64_t)value << 32);
    } else if (offset == CLINT_MTIME) {
        mtime = (mtime & 0xFFFFFFFF00000000ULL) | value;
    } else if (offset == CLINT_MTIME + 4) {
        mtime = (mtime & 0xFFFFFFFF) | ((uint64_t)value << 32);
    }
}

void CLINTDevice::tick() { mtime++; }

bool CLINTDevice::get_timer_interrupt() { return mtime >= mtimecmp; }

bool CLINTDevice::get_software_interrupt() { return msip != 0; }

// GDB stub callback functions
static uint32_t gdb_read_reg(void* user_data, int regno) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    if (regno >= 0 && regno < 32) {
        return sim->regs[regno];
    } else if (regno == 32) { // PC
        return sim->pc;
    }
    return 0;
}

static void gdb_write_reg(void* user_data, int regno, uint32_t value) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    if (regno >= 0 && regno < 32) {
        sim->regs[regno] = value;
        if (regno == 0) sim->regs[0] = 0; // x0 is always 0
    } else if (regno == 32) { // PC
        sim->pc = value;
    }
}

static uint32_t gdb_read_mem(void* user_data, uint32_t addr, int size) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    uint32_t offset = addr - sim->mem_base;
    if (offset < sim->mem_size) {
        if (size == 1) {
            return sim->memory[offset];
        } else if (size == 2 && offset + 1 < sim->mem_size) {
            return sim->memory[offset] | (sim->memory[offset + 1] << 8);
        } else if (size == 4 && offset + 3 < sim->mem_size) {
            return sim->memory[offset] | (sim->memory[offset + 1] << 8) |
                   (sim->memory[offset + 2] << 16) | (sim->memory[offset + 3] << 24);
        }
    }
    return 0;
}

static void gdb_write_mem(void* user_data, uint32_t addr, uint32_t value, int size) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    uint32_t offset = addr - sim->mem_base;
    if (offset < sim->mem_size) {
        if (size == 1) {
            sim->memory[offset] = value & 0xFF;
        } else if (size == 2 && offset + 1 < sim->mem_size) {
            sim->memory[offset] = value & 0xFF;
            sim->memory[offset + 1] = (value >> 8) & 0xFF;
        } else if (size == 4 && offset + 3 < sim->mem_size) {
            sim->memory[offset] = value & 0xFF;
            sim->memory[offset + 1] = (value >> 8) & 0xFF;
            sim->memory[offset + 2] = (value >> 16) & 0xFF;
            sim->memory[offset + 3] = (value >> 24) & 0xFF;
        }
    }
}

static uint32_t gdb_get_pc(void* user_data) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    return sim->pc;
}

static void gdb_set_pc(void* user_data, uint32_t pc) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    sim->pc = pc;
}

static void gdb_single_step(void* user_data) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    sim->gdb_stepping = true;
    sim->step();
    sim->gdb_stepping = false;
}

static bool gdb_is_running(void* user_data) {
    RV32Simulator* sim = (RV32Simulator*)user_data;
    return sim->running;
}

// RV32IMAC CPU simulator implementation
RV32Simulator::RV32Simulator(uint32_t base, uint32_t size)
    : pc(0), running(true), exit_code(0), inst_count(0), tohost_addr(0),
      trace_enabled(false), mem_base(base), mem_size(size), gdb_ctx(nullptr),
      gdb_enabled(false), gdb_stepping(false), max_instructions(0),
      signature_start(0), signature_end(0), signature_granularity(4), 
      signature_enabled(false) {
    memory = new uint8_t[mem_size]();
    memset(regs, 0, sizeof(regs));
    regs[0] = 0; // x0 is always 0

    // Initialize CSRs
    csr_mstatus = 0x00000000; // Start with cleared mstatus (spike behavior)
    csr_misa = 0x40101105;    // RV32IMA
    csr_mie = 0;
    csr_mtvec = 0;
    csr_mscratch = 0;
    csr_mepc = 0;
    csr_mcause = 0;
    csr_mtval = 0;
    csr_mip = 0;
}

RV32Simulator::~RV32Simulator() {
    delete[] memory;
    if (trace_file.is_open()) {
        trace_file.close();
    }
}

void RV32Simulator::enable_trace(const char *filename) {
    trace_enabled = true;
    trace_file.open(filename);
    if (!trace_file.is_open()) {
        std::cerr << "Warning: Failed to open trace file: " << filename
                  << std::endl;
        trace_enabled = false;
    }
}

void RV32Simulator::enable_signature(const char *filename, uint32_t granularity) {
    signature_file = filename;
    signature_granularity = granularity;
    signature_enabled = true;
}

void RV32Simulator::write_signature() {
    if (!signature_enabled || signature_start == 0 || signature_end == 0) {
        return;
    }

    std::ofstream sig_file(signature_file);
    if (!sig_file.is_open()) {
        std::cerr << "Error: Failed to open signature file: " << signature_file << std::endl;
        return;
    }

    // Write signature data in hex format
    for (uint32_t addr = signature_start; addr < signature_end; addr += signature_granularity) {
        if (addr + signature_granularity > signature_end) {
            break;
        }
        uint32_t value = read_mem(addr, signature_granularity);
        sig_file << std::hex << std::setfill('0') << std::setw(signature_granularity * 2) << value << std::endl;
    }

    sig_file.close();
}


void RV32Simulator::log_commit(uint32_t pc, uint32_t inst, int rd_num,
                               uint32_t rd_val, bool has_mem,
                               uint32_t mem_addr, uint32_t mem_val,
                               bool is_store, bool is_csr,
                               uint32_t csr_num) {
    if (trace_enabled && trace_file.is_open()) {
        trace_file << "core   0: 3 0x" << std::hex << std::setfill('0')
                   << std::setw(8) << pc << " (0x" << std::setw(8) << inst
                   << ")";

        // Log register write (skip if CSR write is present)
        if (rd_num > 0 && !is_csr) {
            trace_file << " x" << std::dec << std::left << std::setfill(' ')
                       << std::setw(2) << rd_num << " 0x" << std::right
                       << std::hex << std::setfill('0') << std::setw(8)
                       << rd_val;
        }

        // Log CSR write
        if (is_csr) {
            const char *csr_name = "";
            switch (csr_num) {
            case 0x300:
                csr_name = "mstatus";
                break;
            case 0x301:
                csr_name = "misa";
                break;
            case 0x304:
                csr_name = "mie";
                break;
            case 0x305:
                csr_name = "mtvec";
                break;
            case 0x340:
                csr_name = "mscratch";
                break;
            case 0x341:
                csr_name = "mepc";
                break;
            case 0x342:
                csr_name = "mcause";
                break;
            case 0x343:
                csr_name = "mtval";
                break;
            case 0x344:
                csr_name = "mip";
                break;
            default:
                csr_name = "unknown";
                break;
            }
            trace_file << " c" << std::dec << csr_num << "_" << csr_name
                       << " 0x" << std::hex << std::setfill('0') << std::setw(8)
                       << rd_val;
        }

        // Log memory access
        if (has_mem) {
            trace_file << " mem 0x" << std::hex << std::setfill('0')
                       << std::setw(8) << mem_addr;
            // Only show memory value for stores (loads show value in register)
            if (is_store) {
                trace_file << " 0x" << std::setw(8) << mem_val;
            }
        }

        trace_file << std::endl;
    }
}

// CSR operations
uint32_t RV32Simulator::read_csr(uint32_t csr) {
    switch (csr) {
    case CSR_MSTATUS:
        return csr_mstatus;
    case CSR_MISA:
        return csr_misa;
    case CSR_MIE:
        return csr_mie;
    case CSR_MTVEC:
        return csr_mtvec;
    case CSR_MSCRATCH:
        return csr_mscratch;
    case CSR_MEPC:
        return csr_mepc;
    case CSR_MCAUSE:
        return csr_mcause;
    case CSR_MTVAL:
        return csr_mtval;
    case CSR_MIP:
        return csr_mip;
    default:
        std::cerr << "Warning: Reading unknown CSR 0x" << std::hex << csr
                  << std::endl;
        return 0;
    }
}

void RV32Simulator::write_csr(uint32_t csr, uint32_t value) {
    switch (csr) {
    case CSR_MSTATUS:
        csr_mstatus = value & 0x00001888;
        break;     // Only writable bits
    case CSR_MISA: /* Read-only */
        break;
    case CSR_MIE:
        csr_mie = value & 0x888;
        break;
    case CSR_MTVEC:
        csr_mtvec = value;
        break;
    case CSR_MSCRATCH:
        csr_mscratch = value;
        break;
    case CSR_MEPC:
        csr_mepc = value & ~3;
        break; // Aligned to 4 bytes
    case CSR_MCAUSE:
        csr_mcause = value;
        break;
    case CSR_MTVAL:
        csr_mtval = value;
        break;
    case CSR_MIP:
        csr_mip = value & 0x888;
        break;
    default:
        std::cerr << "Warning: Writing unknown CSR 0x" << std::hex << csr
                  << std::endl;
        break;
    }
}

// Take trap (exception or interrupt)
void RV32Simulator::take_trap(uint32_t cause, uint32_t tval) {
    // Save current PC to MEPC
    csr_mepc = pc;

    // Set cause and trap value
    csr_mcause = cause;
    csr_mtval = tval;

    // Update MPIE and MIE in mstatus
    uint32_t mie = (csr_mstatus >> 3) & 1;
    csr_mstatus = (csr_mstatus & ~0x1888) | (mie << 7); // MPIE = MIE, MIE = 0

    // Jump to trap handler
    pc = csr_mtvec & ~3; // Vectored mode not yet supported

    if (trace_enabled && trace_file.is_open()) {
        trace_file << "core   0: trap cause=0x" << std::hex << cause
                   << " tval=0x" << tval << " -> pc=0x" << pc << std::endl;
    }
}

// Check for pending interrupts
void RV32Simulator::check_interrupts() {
    // Update MIP based on CLINT
    if (clint.get_timer_interrupt()) {
        csr_mip |= (1 << 7); // MTIP
    } else {
        csr_mip &= ~(1 << 7);
    }

    if (clint.get_software_interrupt()) {
        csr_mip |= (1 << 3); // MSIP
    } else {
        csr_mip &= ~(1 << 3);
    }

    // Check if interrupts are enabled
    uint32_t mie_bit = (csr_mstatus >> 3) & 1;
    if (!mie_bit)
        return;

    // Check for pending and enabled interrupts
    uint32_t pending = csr_mip & csr_mie;

    if (pending & (1 << 7)) { // Timer interrupt
        take_trap(CAUSE_MACHINE_TIMER_INT, 0);
    } else if (pending & (1 << 3)) { // Software interrupt
        take_trap(CAUSE_MACHINE_SOFTWARE_INT, 0);
    }
}

// Memory access
uint32_t RV32Simulator::read_mem(uint32_t addr, int size) {
    // Check watchpoints before memory read (if GDB enabled and not during instruction fetch)
    if (gdb_enabled && gdb_ctx && addr != pc) {
        gdb_context_t* gdb = (gdb_context_t*)gdb_ctx;
        if (gdb_stub_check_watchpoint_read(gdb, addr, size)) {
            gdb->should_stop = true;
            std::cout << "Read watchpoint hit at 0x" << std::hex << addr 
                      << " size=" << std::dec << size << std::endl;
        }
    }
    
    // Handle magic addresses
    if (addr == CONSOLE_MAGIC_ADDR) {
        return 0; // Read from console (not typically used)
    }
    if (addr == EXIT_MAGIC_ADDR) {
        return 0; // Read from exit addr
    }

    // Handle UART
    if (addr >= UART_BASE && addr < UART_BASE + 0x1000) {
        return uart.read(addr - UART_BASE);
    }

    // Handle CLINT
    if (addr >= CLINT_BASE && addr < CLINT_BASE + 0x10000) {
        return clint.read(addr - CLINT_BASE);
    }

    // Handle tohost
    if (addr == tohost_addr && tohost_addr != 0) {
        return 0;
    }

    // Regular memory - convert to physical offset
    if (addr < mem_base || addr >= mem_base + mem_size) {
        if (trace_enabled && trace_file.is_open()) {
            trace_file << "Memory read out of bounds: addr=0x" << std::hex
                       << std::setfill('0') << std::setw(8) << addr
                       << " size=" << std::dec << size << " pc=0x" << std::hex
                       << std::setfill('0') << std::setw(8) << pc << std::endl;
        }
        return 0;
    }

    uint32_t offset = addr - mem_base;
    uint32_t value = 0;
    if (size == 1) {
        value = memory[offset];
    } else if (size == 2) {
        value = memory[offset] | (memory[offset + 1] << 8);
    } else if (size == 4) {
        value = memory[offset] | (memory[offset + 1] << 8) |
                (memory[offset + 2] << 16) | (memory[offset + 3] << 24);
    }
    return value;
}

void RV32Simulator::write_mem(uint32_t addr, uint32_t value, int size) {
    // Check watchpoints before memory write (if GDB enabled)
    if (gdb_enabled && gdb_ctx) {
        gdb_context_t* gdb = (gdb_context_t*)gdb_ctx;
        if (gdb_stub_check_watchpoint_write(gdb, addr, size)) {
            gdb->should_stop = true;
            std::cout << "Write watchpoint hit at 0x" << std::hex << addr 
                      << " size=" << std::dec << size 
                      << " value=0x" << std::hex << value << std::endl;
        }
    }
    
    // Handle magic addresses
    if (addr == CONSOLE_MAGIC_ADDR) {
        // Console output
        char c = value & 0xFF;
        std::cout << c << std::flush;
        return;
    }

    if (addr == EXIT_MAGIC_ADDR) {
        // Exit simulation
        exit_code = (value >> 1) & 0x7FFFFFFF;
        running = false;
        std::cout << "\n[EXIT] Magic address write: exit code = " << exit_code
                  << std::endl;
        return;
    }

    // Handle UART
    if (addr >= UART_BASE && addr < UART_BASE + 0x1000) {
        uart.write(addr - UART_BASE, value);
        return;
    }

    // Handle CLINT
    if (addr >= CLINT_BASE && addr < CLINT_BASE + 0x10000) {
        clint.write(addr - CLINT_BASE, value);
        return;
    }

    // Handle tohost
    if (addr == tohost_addr && tohost_addr != 0) {
        if (value != 0) {
            exit_code = (value >> 1) & 0x7FFFFFFF;
            running = false;
            std::cout << "\n[EXIT] tohost write: exit code = " << exit_code
                      << std::endl;
        }
        return;
    }

    // Regular memory - convert to physical offset
    if (addr < mem_base || addr >= mem_base + mem_size) {
        std::cout << "Memory write out of bounds: addr=0x" << std::hex
                  << std::setfill('0') << std::setw(8) << addr
                  << " size=" << std::dec << size << " value=0x" << std::hex
                  << std::setfill('0') << std::setw(8) << value << " pc=0x"
                  << std::hex << std::setfill('0') << std::setw(8) << pc
                  << std::endl;
        return;
    }

    uint32_t offset = addr - mem_base;
    if (size == 1) {
        memory[offset] = value & 0xFF;
    } else if (size == 2) {
        memory[offset] = value & 0xFF;
        memory[offset + 1] = (value >> 8) & 0xFF;
    } else if (size == 4) {
        memory[offset] = value & 0xFF;
        memory[offset + 1] = (value >> 8) & 0xFF;
        memory[offset + 2] = (value >> 16) & 0xFF;
        memory[offset + 3] = (value >> 24) & 0xFF;
    }
}

// Sign extend
int32_t RV32Simulator::sign_extend(uint32_t value, int bits) {
    uint32_t sign_bit = 1U << (bits - 1);
    if (value & sign_bit) {
        return value | (~((1U << bits) - 1));
    }
    return value;
}

// Execute one instruction
void RV32Simulator::step() {
    if (!running)
        return;

    // Check for interrupts before fetching instruction
    check_interrupts();

    // Tick CLINT
    clint.tick();

    uint32_t inst = read_mem(pc, 4);
    uint32_t exec_pc = pc; // Save PC for logging

    uint32_t opcode = inst & 0x7F;
    uint32_t rd = (inst >> 7) & 0x1F;
    uint32_t funct3 = (inst >> 12) & 0x7;
    uint32_t rs1 = (inst >> 15) & 0x1F;
    uint32_t rs2 = (inst >> 20) & 0x1F;
    uint32_t funct7 = (inst >> 25) & 0x7F;

    uint32_t next_pc = pc + 4;
    inst_count++;

    // Trace variables
    int trace_rd = -1;
    uint32_t trace_rd_val = 0;
    bool trace_has_mem = false;
    uint32_t trace_mem_addr = 0;
    uint32_t trace_mem_val = 0;
    bool trace_is_store = false;
    bool trace_is_csr = false;
    uint32_t trace_csr_num = 0;

    // Decode and execute
    switch (opcode) {
    case 0x37: { // LUI
        uint32_t imm = inst & 0xFFFFF000;
        if (rd != 0) {
            regs[rd] = imm;
            trace_rd = rd;
            trace_rd_val = imm;
        }
        break;
    }
    case 0x17: { // AUIPC
        uint32_t imm = inst & 0xFFFFF000;
        uint32_t result = pc + imm;
        if (rd != 0) {
            regs[rd] = result;
            trace_rd = rd;
            trace_rd_val = result;
        }
        break;
    }
    case 0x6F: { // JAL
        int32_t imm = sign_extend(
            ((inst >> 31) << 20) | (((inst >> 12) & 0xFF) << 12) |
                (((inst >> 20) & 0x1) << 11) | (((inst >> 21) & 0x3FF) << 1),
            21);
        uint32_t link = pc + 4;
        if (rd != 0) {
            regs[rd] = link;
            trace_rd = rd;
            trace_rd_val = link;
        }
        next_pc = pc + imm;
        break;
    }
    case 0x67: { // JALR
        int32_t imm = sign_extend((inst >> 20) & 0xFFF, 12);
        uint32_t target = (regs[rs1] + imm) & ~1;
        uint32_t link = pc + 4;
        if (rd != 0) {
            regs[rd] = link;
            trace_rd = rd;
            trace_rd_val = link;
        }
        next_pc = target;
        break;
    }
    case 0x63: { // Branch
        int32_t imm = sign_extend(
            ((inst >> 31) << 12) | (((inst >> 7) & 0x1) << 11) |
                (((inst >> 25) & 0x3F) << 5) | (((inst >> 8) & 0xF) << 1),
            13);
        bool taken = false;
        switch (funct3) {
        case 0x0:
            taken = (regs[rs1] == regs[rs2]);
            break; // BEQ
        case 0x1:
            taken = (regs[rs1] != regs[rs2]);
            break; // BNE
        case 0x4:
            taken = ((int32_t)regs[rs1] < (int32_t)regs[rs2]);
            break; // BLT
        case 0x5:
            taken = ((int32_t)regs[rs1] >= (int32_t)regs[rs2]);
            break; // BGE
        case 0x6:
            taken = (regs[rs1] < regs[rs2]);
            break; // BLTU
        case 0x7:
            taken = (regs[rs1] >= regs[rs2]);
            break; // BGEU
        }
        if (taken)
            next_pc = pc + imm;
        break;
    }
    case 0x03: { // Load
        int32_t imm = sign_extend((inst >> 20) & 0xFFF, 12);
        uint32_t addr = regs[rs1] + imm;
        uint32_t value = 0;
        switch (funct3) {
        case 0x0:
            value = sign_extend(read_mem(addr, 1), 8);
            break; // LB
        case 0x1:
            value = sign_extend(read_mem(addr, 2), 16);
            break; // LH
        case 0x2:
            value = read_mem(addr, 4);
            break; // LW
        case 0x4:
            value = read_mem(addr, 1);
            break; // LBU
        case 0x5:
            value = read_mem(addr, 2);
            break; // LHU
        }
        if (rd != 0) {
            regs[rd] = value;
            trace_rd = rd;
            trace_rd_val = value;
        }
        trace_has_mem = true;
        trace_mem_addr = addr;
        trace_mem_val = value;
        trace_is_store = false; // Load instruction
        break;
    }
    case 0x23: { // Store
        int32_t imm =
            sign_extend(((inst >> 25) << 5) | ((inst >> 7) & 0x1F), 12);
        uint32_t addr = regs[rs1] + imm;
        uint32_t value = regs[rs2];
        switch (funct3) {
        case 0x0:
            write_mem(addr, value, 1);
            break; // SB
        case 0x1:
            write_mem(addr, value, 2);
            break; // SH
        case 0x2:
            write_mem(addr, value, 4);
            break; // SW
        }
        trace_has_mem = true;
        trace_mem_addr = addr;
        trace_mem_val = value;
        trace_is_store = true; // Store instruction
        break;
    }
    case 0x13: { // I-type ALU
        int32_t imm = sign_extend((inst >> 20) & 0xFFF, 12);
        uint32_t result = 0;
        switch (funct3) {
        case 0x0:
            result = regs[rs1] + imm;
            break; // ADDI
        case 0x2:
            result = ((int32_t)regs[rs1] < imm) ? 1 : 0;
            break; // SLTI
        case 0x3:
            result = (regs[rs1] < (uint32_t)imm) ? 1 : 0;
            break; // SLTIU
        case 0x4:
            result = regs[rs1] ^ imm;
            break; // XORI
        case 0x6:
            result = regs[rs1] | imm;
            break; // ORI
        case 0x7:
            result = regs[rs1] & imm;
            break; // ANDI
        case 0x1:
            result = regs[rs1] << (imm & 0x1F);
            break; // SLLI
        case 0x5:
            if (funct7 == 0x00)
                result = regs[rs1] >> (imm & 0x1F); // SRLI
            else
                result = (int32_t)regs[rs1] >> (imm & 0x1F); // SRAI
            break;
        }
        if (rd != 0) {
            regs[rd] = result;
            trace_rd = rd;
            trace_rd_val = result;
        }
        break;
    }
    case 0x33: { // R-type ALU
        uint32_t result = 0;
        switch (funct3) {
        case 0x0:
            if (funct7 == 0x00)
                result = regs[rs1] + regs[rs2]; // ADD
            else if (funct7 == 0x20)
                result = regs[rs1] - regs[rs2]; // SUB
            else if (funct7 == 0x01)
                result = regs[rs1] * regs[rs2]; // MUL
            break;
        case 0x1:
            if (funct7 == 0x00)
                result = regs[rs1] << (regs[rs2] & 0x1F); // SLL
            else if (funct7 == 0x01)
                result = ((uint64_t)regs[rs1] * regs[rs2]) >> 32; // MULH
            break;
        case 0x2:
            if (funct7 == 0x00)
                result =
                    ((int32_t)regs[rs1] < (int32_t)regs[rs2]) ? 1 : 0; // SLT
            else if (funct7 == 0x01)
                result = ((int64_t)(int32_t)regs[rs1] * (uint32_t)regs[rs2]) >>
                         32; // MULHSU
            break;
        case 0x3:
            if (funct7 == 0x00)
                result = (regs[rs1] < regs[rs2]) ? 1 : 0; // SLTU
            else if (funct7 == 0x01)
                result = ((uint64_t)regs[rs1] * regs[rs2]) >> 32; // MULHU
            break;
        case 0x4:
            if (funct7 == 0x00)
                result = regs[rs1] ^ regs[rs2]; // XOR
            else if (funct7 == 0x01)
                result = (int32_t)regs[rs1] / (int32_t)regs[rs2]; // DIV
            break;
        case 0x5:
            if (funct7 == 0x00)
                result = regs[rs1] >> (regs[rs2] & 0x1F); // SRL
            else if (funct7 == 0x20)
                result = (int32_t)regs[rs1] >> (regs[rs2] & 0x1F); // SRA
            else if (funct7 == 0x01)
                result = regs[rs1] / regs[rs2]; // DIVU
            break;
        case 0x6:
            if (funct7 == 0x00)
                result = regs[rs1] | regs[rs2]; // OR
            else if (funct7 == 0x01)
                result = (int32_t)regs[rs1] % (int32_t)regs[rs2]; // REM
            break;
        case 0x7:
            if (funct7 == 0x00)
                result = regs[rs1] & regs[rs2]; // AND
            else if (funct7 == 0x01)
                result = regs[rs1] % regs[rs2]; // REMU
            break;
        }
        if (rd != 0) {
            regs[rd] = result;
            trace_rd = rd;
            trace_rd_val = result;
        }
        break;
    }
    case 0x0F: { // FENCE
        // NOP for simulation
        break;
    }
    case 0x73: { // System
        uint32_t csr_addr = (inst >> 20) & 0xFFF;
        uint32_t zimm =
            rs1; // Zero-extended immediate for CSR immediate instructions

        if (funct3 == 0) {
            // ECALL, EBREAK, MRET, WFI
            if (csr_addr == 0) {
                // ECALL
                take_trap(CAUSE_ECALL_FROM_M, 0);
                next_pc = pc; // PC will be set by trap handler
            } else if (csr_addr == 1) {
                // EBREAK
                take_trap(CAUSE_BREAKPOINT, pc);
                next_pc = pc; // PC will be set by trap handler
            } else if (csr_addr == 0x302) {
                // MRET - return from machine-mode trap
                // Restore MIE from MPIE
                uint32_t mpie = (csr_mstatus >> 7) & 1;
                uint32_t new_mstatus =
                    (csr_mstatus & ~0x88) | (mpie << 3) | (1 << 7);
                csr_mstatus = new_mstatus;
                trace_is_csr = true;
                trace_csr_num = 0x300;
                trace_rd = -1;
                trace_rd_val = new_mstatus;
                next_pc = csr_mepc;
            }
        } else {
            // CSR instructions (Zicsr extension)
            uint32_t csr_val = read_csr(csr_addr);
            uint32_t write_val = 0;
            bool do_write = false;

            switch (funct3) {
            case 0x1: // CSRRW
                write_val = regs[rs1];
                do_write = true;
                break;
            case 0x2: // CSRRS
                write_val = csr_val | regs[rs1];
                do_write = (rs1 != 0);
                break;
            case 0x3: // CSRRC
                write_val = csr_val & ~regs[rs1];
                do_write = (rs1 != 0);
                break;
            case 0x5: // CSRRWI
                write_val = zimm;
                do_write = true;
                break;
            case 0x6: // CSRRSI
                write_val = csr_val | zimm;
                do_write = (zimm != 0);
                break;
            case 0x7: // CSRRCI
                write_val = csr_val & ~zimm;
                do_write = (zimm != 0);
                break;
            }

            if (rd != 0) {
                regs[rd] = csr_val;
                trace_rd = rd;
                trace_rd_val = csr_val;
            }

            if (do_write) {
                write_csr(csr_addr, write_val);
                trace_is_csr = true;
                trace_csr_num = csr_addr;
                trace_rd_val = read_csr(csr_addr); // Show the value after write/masking
            }
        }
        break;
    }
    case 0x2F: { // AMO (Atomic)
        uint32_t addr = regs[rs1];
        uint32_t loaded = read_mem(addr, 4);
        uint32_t result = loaded;
        uint32_t store_val = regs[rs2];

        switch (funct3) {
        case 0x2: { // Word operations
            uint32_t funct5 = (funct7 >> 2) & 0x1F;
            switch (funct5) {
            case 0x02:
                write_mem(addr, store_val, 4);
                break; // LR.W (just load)
            case 0x03:
                write_mem(addr, store_val, 4);
                result = 0;
                break; // SC.W
            case 0x01:
                result = loaded;
                write_mem(addr, store_val, 4);
                break; // AMOSWAP.W
            case 0x00:
                result = loaded;
                write_mem(addr, loaded + store_val, 4);
                break; // AMOADD.W
            case 0x04:
                result = loaded;
                write_mem(addr, loaded ^ store_val, 4);
                break; // AMOXOR.W
            case 0x0C:
                result = loaded;
                write_mem(addr, loaded & store_val, 4);
                break; // AMOAND.W
            case 0x08:
                result = loaded;
                write_mem(addr, loaded | store_val, 4);
                break; // AMOOR.W
            case 0x10:
                result = loaded;
                write_mem(addr,
                          ((int32_t)loaded < (int32_t)store_val) ? loaded
                                                                 : store_val,
                          4);
                break; // AMOMIN.W
            case 0x14:
                result = loaded;
                write_mem(addr,
                          ((int32_t)loaded > (int32_t)store_val) ? loaded
                                                                 : store_val,
                          4);
                break; // AMOMAX.W
            case 0x18:
                result = loaded;
                write_mem(addr, (loaded < store_val) ? loaded : store_val, 4);
                break; // AMOMINU.W
            case 0x1C:
                result = loaded;
                write_mem(addr, (loaded > store_val) ? loaded : store_val, 4);
                break; // AMOMAXU.W
            }
            break;
        }
        }
        if (rd != 0) {
            regs[rd] = result;
            trace_rd = rd;
            trace_rd_val = result;
        }
        // Note: AMO instructions do both read and write, but spike only shows
        // the result register
        break;
    }
    default:
        std::cerr << "Unknown instruction: 0x" << std::hex << inst
                  << " at PC 0x" << pc << std::endl;
        running = false;
        break;
    }

    // Log instruction commit with trace information
    log_commit(exec_pc, inst, trace_rd, trace_rd_val, trace_has_mem,
                   trace_mem_addr, trace_mem_val, trace_is_store, trace_is_csr,
                   trace_csr_num);
    regs[0] = 0; // x0 is always 0
    pc = next_pc;

    // Safety check
    if (inst_count > 100000000) {
        std::cerr << "Instruction limit exceeded" << std::endl;
        running = false;
    }
}

// Load ELF file
bool RV32Simulator::load_elf(const char *filename) {
    std::ifstream file(filename, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to open ELF file: " << filename << std::endl;
        return false;
    }
    Elf32_Ehdr ehdr;
    file.read((char *)&ehdr, sizeof(ehdr));

    if (memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0) {
        std::cerr << "Not a valid ELF file" << std::endl;
        return false;
    }

    // Set entry point
    pc = ehdr.e_entry;

    // Load program headers
    file.seekg(ehdr.e_phoff);
    for (int i = 0; i < ehdr.e_phnum; i++) {
        Elf32_Phdr phdr;
        file.read((char *)&phdr, sizeof(phdr));

        if (phdr.p_type == PT_LOAD) {
            // Check if address is within our memory range
            if (phdr.p_paddr >= mem_base &&
                phdr.p_paddr < mem_base + mem_size) {
                uint32_t offset = phdr.p_paddr - mem_base;
                if (offset + phdr.p_memsz <= mem_size) {
                    file.seekg(phdr.p_offset);
                    file.read((char *)&memory[offset], phdr.p_filesz);
                    // Zero out BSS
                    if (phdr.p_memsz > phdr.p_filesz) {
                        memset(&memory[offset + phdr.p_filesz], 0,
                               phdr.p_memsz - phdr.p_filesz);
                    }
                }
            }
        }
    }

    // Find tohost symbol
    file.seekg(ehdr.e_shoff);
    for (int i = 0; i < ehdr.e_shnum; i++) {
        Elf32_Shdr shdr;
        file.read((char *)&shdr, sizeof(shdr));

        if (shdr.sh_type == SHT_SYMTAB) {
            // Read symbol table
            std::vector<char> strtab;
            Elf32_Shdr strtab_hdr;
            file.seekg(ehdr.e_shoff + shdr.sh_link * sizeof(Elf32_Shdr));
            file.read((char *)&strtab_hdr, sizeof(strtab_hdr));
            strtab.resize(strtab_hdr.sh_size);
            file.seekg(strtab_hdr.sh_offset);
            file.read(strtab.data(), strtab_hdr.sh_size);

            file.seekg(shdr.sh_offset);
            for (size_t j = 0; j < shdr.sh_size / sizeof(Elf32_Sym); j++) {
                Elf32_Sym sym;
                file.read((char *)&sym, sizeof(sym));

                if (sym.st_name < strtab.size()) {
                    std::string name = &strtab[sym.st_name];
                    if (name == "tohost") {
                        tohost_addr = sym.st_value;
                        std::cout << "Found tohost at 0x" << std::hex
                                  << tohost_addr << std::endl;
                    } else if (name == "begin_signature") {
                        signature_start = sym.st_value;
                        std::cout << "Found begin_signature at 0x" << std::hex
                                  << signature_start << std::endl;
                    } else if (name == "end_signature") {
                        signature_end = sym.st_value;
                        std::cout << "Found end_signature at 0x" << std::hex
                                  << signature_end << std::endl;
                    }
                }
            }
        }
    }

    file.close();
    return true;
}

void RV32Simulator::run() {
    std::cout << "\n=== Starting RV32IMAC Simulation ===" << std::endl;
    std::cout << "Entry point: 0x" << std::hex << pc << std::endl;

    if (gdb_enabled) {
        std::cout << "GDB stub enabled, waiting for GDB connection..." << std::endl;
        gdb_context_t* gdb = (gdb_context_t*)gdb_ctx;
        
        // Setup callbacks
        gdb_callbacks_t callbacks = {
            .read_reg = gdb_read_reg,
            .write_reg = gdb_write_reg,
            .read_mem = gdb_read_mem,
            .write_mem = gdb_write_mem,
            .get_pc = gdb_get_pc,
            .set_pc = gdb_set_pc,
            .single_step = gdb_single_step,
            .is_running = gdb_is_running
        };
        
        // Wait for GDB to connect
        if (gdb_stub_accept(gdb) < 0) {
            std::cerr << "Failed to accept GDB connection" << std::endl;
            return;
        }
        
        std::cout << "GDB connected, starting debug session" << std::endl;
        
        // Start in stopped state, wait for GDB to issue continue/step
        gdb->should_stop = true;
        
        // GDB debug loop
        while (running) {
            // Process GDB commands
            int result = gdb_stub_process(gdb, this, &callbacks);
            if (result < 0) {
                std::cout << "GDB disconnected" << std::endl;
                break;
            }
            
            // If GDB issued continue/step command (result == 1), execute
            if (result == 1 && !gdb->should_stop) {
                // For single-step, execute just one instruction
                if (gdb->single_step) {
                    step();
                    gdb->should_stop = true;
                    gdb->single_step = false;
                    gdb_stub_send_stop_signal(gdb, 5); // SIGTRAP after single step
                } 
                // For continue, keep executing until breakpoint or exit
                else {
                    while (running && !gdb->should_stop) {
                        step();
                        
                        // Check if watchpoint was hit during execution (set by read_mem/write_mem)
                        if (gdb->should_stop) {
                            gdb_stub_send_stop_signal(gdb, 5); // SIGTRAP
                            break;
                        }
                        
                        // Check for breakpoint at new PC after execution
                        if (gdb_stub_check_breakpoint(gdb, pc)) {
                            // Hit breakpoint, stop and notify GDB
                            gdb->should_stop = true;
                            gdb_stub_send_stop_signal(gdb, 5); // SIGTRAP
                            std::cout << "Breakpoint hit at 0x" << std::hex << pc << std::endl;
                            break;
                        }
                        
                        // Check instruction limit (if set)
                        if (max_instructions > 0 && inst_count >= max_instructions) {
                            std::cout << "\n[LIMIT] Reached instruction limit: " << std::dec << inst_count << std::endl;
                            running = false;
                            break;
                        }
                    }
                }
            } else {
                // CPU is halted, wait briefly to avoid busy waiting
                usleep(1000); // 1ms
            }
        }
    } else {
        // Normal execution without GDB
        while (running) {
            step();
            
            // Check instruction limit (if set)
            if (max_instructions > 0 && inst_count >= max_instructions) {
                std::cout << "\n[LIMIT] Reached instruction limit: " << std::dec << inst_count << std::endl;
                break;
            }
        }
    }

    std::cout << "\n=== Simulation Complete ===" << std::endl;
    std::cout << "Instructions executed: " << std::dec << inst_count
              << std::endl;
    std::cout << "Exit code: " << exit_code << std::endl;
    
    // Write signature file if enabled
    write_signature();
}

void print_usage(const char *prog) {
    std::cerr << "Usage: " << prog << " [options] <elf_file>" << std::endl;
    std::cerr << "Options:" << std::endl;
    std::cerr << "  --isa=<name>         Specify ISA (default: rv32ima_zicsr)"
              << std::endl;
    std::cerr << "                       Supported: rv32ima, rv32ima_zicsr"
              << std::endl;
    std::cerr
        << "  --trace              Enable instruction trace logging (alias "
           "for --log-commits)"
        << std::endl;
    std::cerr << "  --log-commits        Enable instruction trace logging"
              << std::endl;
    std::cerr
        << "  --log=<file>         Specify trace log output file (default: "
           "sim_trace.txt)"
        << std::endl;
    std::cerr << "  +signature=<file>    Write signature to file (RISCOF compatibility)"
              << std::endl;
    std::cerr << "  +signature-granularity=<n>  Signature granularity in bytes (1, 2, or 4, default: 4)"
              << std::endl;
    std::cerr << "  -m<base>:<size>      Specify memory range (e.g., "
                 "-m0x80000000:0x200000)"
              << std::endl;
    std::cerr
        << "                       Default: -m0x80000000:0x200000 (2MB at "
           "0x80000000)"
        << std::endl;
    std::cerr << "  --instructions=<n>   Limit execution to N instructions (0 = no limit)"
              << std::endl;
    std::cerr << "  --gdb                Enable GDB stub for remote debugging"
              << std::endl;
    std::cerr << "  --gdb-port=<port>    Specify GDB port (default: 3333)"
              << std::endl;
    std::cerr << "Examples:" << std::endl;
    std::cerr << "  " << prog << " program.elf" << std::endl;
    std::cerr << "  " << prog << " --log-commits --log=output.log program.elf"
              << std::endl;
    std::cerr << "  " << prog
              << " --log-commits -m0x80000000:0x200000 program.elf"
              << std::endl;
    std::cerr << "  " << prog << " --gdb --gdb-port=3333 program.elf"
              << std::endl;
    std::cerr << "  " << prog << " +signature=output.sig +signature-granularity=4 test.elf"
              << std::endl;
}

bool parse_hex(const char *str, uint32_t &value) {
    char *endptr;
    if (strncmp(str, "0x", 2) == 0 || strncmp(str, "0X", 2) == 0) {
        value = strtoul(str + 2, &endptr, 16);
    } else {
        value = strtoul(str, &endptr, 16);
    }
    return (*endptr == '\0' || *endptr == ':');
}

int main(int argc, char *argv[]) {
    const char *elf_file = nullptr;
    const char *log_file = "sim_trace.txt";
    const char *signature_file = nullptr;
    uint32_t signature_granularity = 4;
    bool trace_enabled = false;
    uint32_t mem_base = MEM_BASE;
    uint32_t mem_size = MEM_SIZE;
    const char *isa_name = "rv32ima";
    bool gdb_enabled = false;
    int gdb_port = GDB_DEFAULT_PORT;
    uint64_t max_instructions = 0;  // 0 = no limit

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--isa=", 6) == 0) {
            isa_name = argv[i] + 6;
            // Accept rv32ima or rv32ima_zicsr
            if (strcmp(isa_name, "rv32ima") != 0 &&
                strcmp(isa_name, "rv32ima_zicsr") != 0) {
                std::cerr << "Error: Unsupported ISA '" << isa_name << "'"
                          << std::endl;
                std::cerr << "Supported ISAs: rv32ima, rv32ima_zicsr"
                          << std::endl;
                return 1;
            }
        } else if (strcmp(argv[i], "--log-commits") == 0 ||
                   strcmp(argv[i], "--trace") == 0) {
            trace_enabled = true;
        } else if (strncmp(argv[i], "--log=", 6) == 0) {
            log_file = argv[i] + 6;
        } else if (strncmp(argv[i], "+signature=", 11) == 0) {
            signature_file = argv[i] + 11;
        } else if (strncmp(argv[i], "+signature-granularity=", 23) == 0) {
            char *endptr;
            signature_granularity = strtoul(argv[i] + 23, &endptr, 10);
            if (*endptr != '\0' || (signature_granularity != 1 && 
                signature_granularity != 2 && signature_granularity != 4)) {
                std::cerr << "Invalid signature granularity (must be 1, 2, or 4): " 
                          << (argv[i] + 23) << std::endl;
                return 1;
            }
        } else if (strncmp(argv[i], "--instructions=", 15) == 0) {
            // Parse instruction limit
            char *endptr;
            max_instructions = strtoull(argv[i] + 15, &endptr, 10);
            if (*endptr != '\0') {
                std::cerr << "Invalid instruction limit: " << (argv[i] + 15) << std::endl;
                return 1;
            }
        } else if (strcmp(argv[i], "--gdb") == 0) {
            gdb_enabled = true;
        } else if (strncmp(argv[i], "--gdb-port=", 11) == 0) {
            // Parse GDB port (decimal)
            char *endptr;
            long port_val = strtol(argv[i] + 11, &endptr, 10);
            if (*endptr != '\0' || port_val <= 0 || port_val > 65535) {
                std::cerr << "Invalid GDB port (must be 1-65535): " << (argv[i] + 11) << std::endl;
                return 1;
            }
            gdb_port = port_val;
        } else if (strncmp(argv[i], "-m", 2) == 0) {
            // Parse memory range: -m0x80000000:0x200000
            const char *range = argv[i] + 2;
            const char *colon = strchr(range, ':');
            if (colon) {
                char base_str[32];
                strncpy(base_str, range, colon - range);
                base_str[colon - range] = '\0';

                if (!parse_hex(base_str, mem_base)) {
                    std::cerr << "Invalid memory base address: " << base_str
                              << std::endl;
                    return 1;
                }
                if (!parse_hex(colon + 1, mem_size)) {
                    std::cerr << "Invalid memory size: " << (colon + 1)
                              << std::endl;
                    return 1;
                }
            } else {
                std::cerr << "Invalid memory range format. Use -m<base>:<size>"
                          << std::endl;
                return 1;
            }
        } else if (argv[i][0] == '-') {
            std::cerr << "Unknown option: " << argv[i] << std::endl;
            print_usage(argv[0]);
            return 1;
        } else {
            elf_file = argv[i];
        }
    }

    if (!elf_file) {
        std::cerr << "Error: No ELF file specified" << std::endl;
        print_usage(argv[0]);
        return 1;
    }

    std::cout << "=== RV32IMAC Software Simulator ===" << std::endl;
    std::cout << "Memory: 0x" << std::hex << mem_base << " - 0x"
              << (mem_base + mem_size) << " (" << std::dec << (mem_size / 1024)
              << " KB)" << std::endl;
    if (trace_enabled) {
        std::cout << "Trace: enabled -> " << log_file << std::endl;
    }
    if (signature_file) {
        std::cout << "Signature: enabled -> " << signature_file 
                  << " (granularity=" << signature_granularity << ")" << std::endl;
    }
    if (gdb_enabled) {
        std::cout << "GDB: enabled on port " << std::dec << gdb_port
                  << std::endl;
    }
    std::cout << std::endl;

    RV32Simulator sim(mem_base, mem_size);

    if (trace_enabled) {
        sim.enable_trace(log_file);
    }
    
    if (signature_file) {
        sim.enable_signature(signature_file, signature_granularity);
    }

    // Set instruction limit
    sim.max_instructions = max_instructions;

    // Initialize GDB stub if enabled
    if (gdb_enabled) {
        gdb_context_t* gdb_ctx = new gdb_context_t();
        memset(gdb_ctx, 0, sizeof(gdb_context_t));
        
        if (gdb_stub_init(gdb_ctx, gdb_port) < 0) {
            std::cerr << "Failed to initialize GDB stub" << std::endl;
            delete gdb_ctx;
            return 1;
        }
        
        sim.gdb_ctx = gdb_ctx;
        sim.gdb_enabled = true;
    }

    if (!sim.load_elf(elf_file)) {
        return 1;
    }

    sim.run();

    return sim.exit_code;
}
