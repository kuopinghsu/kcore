#ifndef ELFLOADER_H
#define ELFLOADER_H

#include <stdint.h>
#include <string>
#include <map>

// Symbol table entry
struct Symbol {
    std::string name;
    uint32_t addr;
    uint32_t size;
};

// Global variables for special symbols
extern uint32_t g_tohost_addr;
extern uint32_t g_fromhost_addr;
extern std::map<std::string, Symbol> g_symbols;

// Forward declaration for DUT type
class Vtb_soc;

// Load ELF file into memory
bool load_elf(Vtb_soc* dut, const std::string& filename);

// Load binary file into memory (legacy support)
bool load_bin(Vtb_soc* dut, const std::string& filename);

// Auto-detect and load program (ELF or binary)
bool load_program(Vtb_soc* dut, const std::string& filename);

#endif // ELFLOADER_H
