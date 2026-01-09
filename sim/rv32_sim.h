// RISC-V RV32IMAC Functional Simulator - Header
// Contains ELF definitions, magic addresses, and device classes

#ifndef RV32_SIM_H
#define RV32_SIM_H

#include <stdint.h>
#include <vector>
#include <fstream>
#include <cstring>

// Lightweight ELF definitions (ELF32)
#define EI_NIDENT 16
#define ELFMAG "\177ELF"
#define SELFMAG 4

// ELF header
struct Elf32_Ehdr {
    uint8_t  e_ident[EI_NIDENT];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint32_t e_entry;
    uint32_t e_phoff;
    uint32_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
};

// Program header
struct Elf32_Phdr {
    uint32_t p_type;
    uint32_t p_offset;
    uint32_t p_vaddr;
    uint32_t p_paddr;
    uint32_t p_filesz;
    uint32_t p_memsz;
    uint32_t p_flags;
    uint32_t p_align;
};

// Section header
struct Elf32_Shdr {
    uint32_t sh_name;
    uint32_t sh_type;
    uint32_t sh_flags;
    uint32_t sh_addr;
    uint32_t sh_offset;
    uint32_t sh_size;
    uint32_t sh_link;
    uint32_t sh_info;
    uint32_t sh_addralign;
    uint32_t sh_entsize;
};

// Symbol table entry
struct Elf32_Sym {
    uint32_t st_name;
    uint32_t st_value;
    uint32_t st_size;
    uint8_t  st_info;
    uint8_t  st_other;
    uint16_t st_shndx;
};

// ELF constants
#define PT_LOAD    1
#define SHT_SYMTAB 2
#define SHT_STRTAB 3

// Memory address
#define MEM_BASE           0x80000000
#define MEM_SIZE           (2 * 1024 * 1024)  // 2MB

// Magic addresses
#define CONSOLE_MAGIC_ADDR 0xFFFFFFF4  // Console output
#define EXIT_MAGIC_ADDR    0xFFFFFFF0  // Exit simulation
#define UART_BASE          0x10000000  // UART peripheral
#define CLINT_BASE         0x02000000  // CLINT peripheral

// UART registers (offset from UART_BASE)
#define UART_DATA_REG      0x00
#define UART_STATUS_REG    0x04

// CLINT registers (offset from CLINT_BASE)
#define CLINT_MSIP         0x0000      // Machine Software Interrupt Pending
#define CLINT_MTIMECMP     0x4000      // Machine Time Compare
#define CLINT_MTIME        0xBFF8      // Machine Time

// CSR addresses
#define CSR_MSTATUS   0x300
#define CSR_MISA      0x301
#define CSR_MIE       0x304
#define CSR_MTVEC     0x305
#define CSR_MSCRATCH  0x340
#define CSR_MEPC      0x341
#define CSR_MCAUSE    0x342
#define CSR_MTVAL     0x343
#define CSR_MIP       0x344

// Exception/Interrupt codes
#define CAUSE_MISALIGNED_FETCH    0
#define CAUSE_FETCH_ACCESS        1
#define CAUSE_ILLEGAL_INSTRUCTION 2
#define CAUSE_BREAKPOINT          3
#define CAUSE_MISALIGNED_LOAD     4
#define CAUSE_LOAD_ACCESS         5
#define CAUSE_MISALIGNED_STORE    6
#define CAUSE_STORE_ACCESS        7
#define CAUSE_ECALL_FROM_M        11
#define CAUSE_MACHINE_TIMER_INT   0x80000007
#define CAUSE_MACHINE_SOFTWARE_INT 0x80000003

// Simple UART emulation
class UARTDevice {
public:
    uint32_t tx_data;
    uint32_t rx_data;
    uint32_t status;
    bool tx_busy;
    std::vector<uint8_t> rx_fifo;
    std::vector<uint8_t> tx_fifo;

    UARTDevice();
    uint32_t read(uint32_t offset);
    void write(uint32_t offset, uint32_t value);
};

// CLINT device for timer and software interrupts
class CLINTDevice {
public:
    uint32_t msip;          // Machine Software Interrupt Pending
    uint64_t mtimecmp;      // Machine Time Compare
    uint64_t mtime;         // Machine Time

    CLINTDevice();
    uint32_t read(uint32_t offset);
    void write(uint32_t offset, uint32_t value);
    void tick();            // Increment mtime
    bool get_timer_interrupt();
    bool get_software_interrupt();
};

// RV32IMAC CPU simulator
class RV32Simulator {
public:
    uint32_t regs[32];
    uint32_t pc;
    uint8_t* memory;
    bool running;
    int exit_code;
    uint64_t inst_count;
    UARTDevice uart;
    CLINTDevice clint;
    uint32_t tohost_addr;
    std::ofstream trace_file;
    bool trace_enabled;
    uint32_t mem_base;
    uint32_t mem_size;

    // CSR registers
    uint32_t csr_mstatus;
    uint32_t csr_misa;
    uint32_t csr_mie;
    uint32_t csr_mtvec;
    uint32_t csr_mscratch;
    uint32_t csr_mepc;
    uint32_t csr_mcause;
    uint32_t csr_mtval;
    uint32_t csr_mip;

    RV32Simulator(uint32_t base = MEM_BASE, uint32_t size = MEM_SIZE);
    ~RV32Simulator();

    void enable_trace(const char* filename);
    void log_commit(uint32_t pc, uint32_t inst, int rd_num, uint32_t rd_val, bool has_mem, uint32_t mem_addr, uint32_t mem_val, bool is_csr, uint32_t csr_num);
    uint32_t read_mem(uint32_t addr, int size);
    void write_mem(uint32_t addr, uint32_t value, int size);
    int32_t sign_extend(uint32_t value, int bits);

    // CSR operations
    uint32_t read_csr(uint32_t csr);
    void write_csr(uint32_t csr, uint32_t value);

    // Interrupt and exception handling
    void take_trap(uint32_t cause, uint32_t tval);
    void check_interrupts();

    void step();
    bool load_elf(const char* filename);
    void run();
};

#endif // RV32_SIM_H
