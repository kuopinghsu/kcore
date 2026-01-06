// Verilator C++ Testbench Wrapper
// Provides main() function and simulation control for Verilator

#include <verilated.h>
#include "Vtb_soc.h"
#include "svdpi.h"
#include "elfloader.h"
#include <iostream>
#include <fstream>
#include <iomanip>
#include <cstdlib>
#include <map>
#include <sstream>
#include <cstdio>
#include <vector>
#include <queue>
#include <cstring>

#define HAVE_CHRONO

#ifdef HAVE_CHRONO
#include <chrono>
#endif

#define RESOLUTION 10 // 10 ns

#ifdef TRACE_FST
#include <verilated_fst_c.h>
#endif

#ifdef TRACE_VCD
#include <verilated_vcd_c.h>
#endif

// Current simulation time
vluint64_t main_time = 0;

// Called by $time in Verilog
double sc_time_stamp() {
    return main_time;
}

// DPI-C imported functions from SystemVerilog
extern "C" {
    void mem_write_byte(int addr, char data);
    char mem_read_byte(int addr);
}

// DPI-C exported function for console output from magic address
extern "C" void console_putchar(char c) {
    std::cout << c << std::flush;
}

// UART monitoring
void uart_monitor(uint8_t tx_bit) {
    static int uart_state = 0;  // 0=idle, 1=start, 2-9=data, 10=stop
    static int uart_timer = 0;
    static uint8_t uart_data = 0;
    static int uart_bit_count = 0;
    const int UART_BIT_PERIOD = 4;  // 50MHz / 12500000 = 4 cycles/bit (BAUD_DIV=4)

    if (uart_state == 0) {  // Idle
        if (tx_bit == 0) {  // Start bit
            uart_state = 1;
            uart_timer = UART_BIT_PERIOD / 2;
        }
    } else if (uart_state == 1) {  // Start bit
        if (--uart_timer == 0) {
            uart_timer = UART_BIT_PERIOD;
            uart_state = 2;
            uart_bit_count = 0;
            uart_data = 0;
        }
    } else if (uart_state >= 2 && uart_state <= 9) {  // Data bits
        if (--uart_timer == 0) {
            uart_data |= (tx_bit << uart_bit_count);
            uart_bit_count++;
            uart_timer = UART_BIT_PERIOD;
            uart_state++;
        }
    } else if (uart_state == 10) {  // Stop bit
        if (--uart_timer == 0) {
            std::cout << (char)uart_data << std::flush;
            uart_state = 0;
        }
    }
}

// UART transmitter (for stimulating RX input)
// Returns the current bit value to drive on uart_rx
uint8_t uart_transmit() {
    static int tx_state = 0;        // 0=idle, 1=start, 2-9=data, 10=stop
    static int tx_timer = 0;
    static uint8_t tx_data = 0;
    static int tx_bit_count = 0;
    static std::queue<char> tx_queue;
    static bool initialized = false;
    static int startup_delay = 50000;  // Delay before starting transmission
    const int UART_BIT_PERIOD = 4;  // 50MHz / 12500000 = 4 cycles/bit (BAUD_DIV=4)

    // Initial startup delay
    if (startup_delay > 0) {
        startup_delay--;
        return 1;  // Idle
    }

    // Initialize with test data (only once)
    if (!initialized) {
        // Send some test characters for UART echo test
        const char* test_string = "ABC\n";
        for (int i = 0; test_string[i] != '\0'; i++) {
            tx_queue.push(test_string[i]);
        }
        initialized = true;
    }

    if (tx_state == 0) {  // Idle
        if (!tx_queue.empty()) {
            tx_data = tx_queue.front();
            tx_queue.pop();
            tx_state = 1;
            tx_timer = UART_BIT_PERIOD;
        }
        return 1;  // Idle high
    } else if (tx_state == 1) {  // Start bit
        if (--tx_timer == 0) {
            tx_timer = UART_BIT_PERIOD;
            tx_state = 2;
            tx_bit_count = 0;
        }
        return 0;  // Start bit is low
    } else if (tx_state >= 2 && tx_state <= 9) {  // Data bits
        uint8_t bit_value = (tx_data >> (tx_state - 2)) & 0x01;
        if (--tx_timer == 0) {
            tx_timer = UART_BIT_PERIOD;
            tx_state++;
        }
        return bit_value;
    } else if (tx_state == 10) {  // Stop bit
        if (--tx_timer == 0) {
            tx_state = 0;
            tx_timer = UART_BIT_PERIOD * 2;  // Extra idle time between characters
        }
        return 1;  // Stop bit is high
    }

    return 1;  // Default idle
}

// Read environment configuration from env.config
std::string read_config_value(const std::string& key) {
    std::ifstream config_file("env.config");
    if (!config_file.is_open()) {
        return "";  // Config file not found
    }

    std::string line;
    while (std::getline(config_file, line)) {
        // Skip comments and empty lines
        if (line.empty() || line[0] == '#') continue;

        // Find key=value
        size_t eq_pos = line.find('=');
        if (eq_pos != std::string::npos) {
            std::string config_key = line.substr(0, eq_pos);
            // Trim whitespace
            config_key.erase(0, config_key.find_first_not_of(" \t"));
            config_key.erase(config_key.find_last_not_of(" \t") + 1);

            if (config_key == key) {
                std::string value = line.substr(eq_pos + 1);
                // Trim whitespace
                value.erase(0, value.find_first_not_of(" \t"));
                value.erase(value.find_last_not_of(" \t\r\n") + 1);
                config_file.close();
                return value;
            }
        }
    }
    config_file.close();
    return "";
}

// Load disassembly from objdump
std::map<uint32_t, std::string> load_disassembly(const std::string& binary_file, const std::string& objdump_path) {
    std::map<uint32_t, std::string> disasm_map;
    std::string cmd = objdump_path + " -d " + binary_file + " 2>/dev/null";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        std::cerr << "Warning: Could not run objdump for disassembly" << std::endl;
        return disasm_map;
    }

    char buffer[256];
    while (fgets(buffer, sizeof(buffer), pipe)) {
        std::string line(buffer);
        // Match lines like: "80000000:\t30047073\taddi\tsp,sp,-16"
        size_t colon_pos = line.find(':');
        if (colon_pos != std::string::npos && colon_pos > 0) {
            // Extract PC address
            std::string addr_str = line.substr(0, colon_pos);
            // Trim whitespace
            addr_str.erase(0, addr_str.find_first_not_of(" \t"));

            uint32_t pc = 0;
            if (sscanf(addr_str.c_str(), "%x", &pc) == 1) {
                // Extract disassembly (after tabs)
                size_t tab_pos = line.find('\t', colon_pos);
                if (tab_pos != std::string::npos) {
                    tab_pos = line.find('\t', tab_pos + 1);  // Skip hex instruction
                    if (tab_pos != std::string::npos) {
                        std::string disasm = line.substr(tab_pos + 1);
                        // Remove newline and trim
                        size_t newline_pos = disasm.find('\n');
                        if (newline_pos != std::string::npos) {
                            disasm = disasm.substr(0, newline_pos);
                        }
                        // Replace tabs with spaces
                        for (size_t i = 0; i < disasm.length(); i++) {
                            if (disasm[i] == '\t') disasm[i] = ' ';
                        }
                        disasm_map[pc] = disasm;
                    }
                }
            }
        }
    }
    pclose(pipe);
    std::cout << "Loaded " << disasm_map.size() << " disassembly entries from objdump" << std::endl;
    return disasm_map;
}

int main(int argc, char** argv) {
    // Initialize Verilators variables
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    #ifdef HAVE_CHRONO
    std::chrono::steady_clock::time_point time_begin;
    std::chrono::steady_clock::time_point time_end;
    #endif

    // Create instance of module
    Vtb_soc* dut = new Vtb_soc;

    // Check if RTL trace is enabled
    const char* trace_flag = Verilated::commandArgsPlusMatch("TRACE");
    bool enable_trace = (trace_flag && 0 == strcmp(trace_flag, "+TRACE"));

    // Trace file setup (only if enabled)
    std::ofstream trace_file;
    if (enable_trace) {
        trace_file.open("rtl_trace.txt");
        std::cout << "RTL instruction trace enabled (rtl_trace.txt)" << std::endl;
    }

#ifdef TRACE_FST
    VerilatedFstC* tfp = nullptr;
    const char* flag = Verilated::commandArgsPlusMatch("WAVE");
    if (flag && 0 == strcmp(flag, "+WAVE")) {
        std::cout << "Enabling FST waveform dump to dump.fst" << std::endl;
        tfp = new VerilatedFstC;
        dut->trace(tfp, 99);  // Trace 99 levels of hierarchy
        tfp->open("dump.fst");
    }
#endif

#ifdef TRACE_VCD
    VerilatedVcdC* tfp_vcd = nullptr;
    const char* flag_vcd = Verilated::commandArgsPlusMatch("WAVE");
    if (flag_vcd && 0 == strcmp(flag_vcd, "+WAVE")) {
        std::cout << "Enabling VCD waveform dump to dump.vcd" << std::endl;
        tfp_vcd = new VerilatedVcdC;
        dut->trace(tfp_vcd, 99);  // Trace 99 levels of hierarchy
        tfp_vcd->open("dump.vcd");
    }
#endif

    // Display memory configuration (compile-time parameters)
#ifdef MEM_DUAL_PORT
    std::cout << "Memory configuration:" << std::endl;
    std::cout << "  Mode: " << (MEM_DUAL_PORT ? "Dual-port" : "One-port") << std::endl;
    std::cout << "  Read latency: " << MEM_READ_LATENCY << " cycles" << std::endl;
    std::cout << "  Write latency: " << MEM_WRITE_LATENCY << " cycles" << std::endl;
#endif

    // Load program
    const char* prog_arg = Verilated::commandArgsPlusMatch("PROGRAM=");
    std::string prog_name;
    if (prog_arg) {
        prog_name = prog_arg + 9;  // Skip "+PROGRAM="
        if (!load_program(dut, prog_name)) {
            return 1;
        }
    } else {
        std::cerr << "Error: No program specified. Use +PROGRAM=<filename>" << std::endl;
        return 1;
    }

    // Initialize signature region to zero (for RISCOF tests)
    // The signature region is in BSS and should be zero-initialized
    const char* sig_begin_arg = Verilated::commandArgsPlusMatch("SIG_BEGIN=");
    const char* sig_end_arg = Verilated::commandArgsPlusMatch("SIG_END=");
    if (sig_begin_arg && sig_end_arg) {
        uint32_t sig_begin = 0, sig_end = 0;
        sscanf(sig_begin_arg, "+SIG_BEGIN=%x", &sig_begin);
        sscanf(sig_end_arg, "+SIG_END=%x", &sig_end);

        if (sig_begin && sig_end && sig_end > sig_begin) {
            // Set scope for DPI calls
            svSetScope(svGetScopeFromName("TOP.tb_soc.u_memory"));

            // Zero out signature region
            for (uint32_t addr = sig_begin; addr < sig_end; addr++) {
                mem_write_byte(addr, 0);
            }
            std::cout << "Initialized signature region 0x" << std::hex << sig_begin
                      << " to 0x" << sig_end << std::dec << " to zero" << std::endl;
        }
    }

    // Load disassembly only if trace is enabled
    std::map<uint32_t, std::string> disasm_map;
    if (enable_trace) {
        // Get objdump path - try +OBJDUMP= argument first, then env.config, then default
        std::string objdump_path;
        const char* objdump_arg = Verilated::commandArgsPlusMatch("OBJDUMP=");
        if (objdump_arg && strlen(objdump_arg) > 9) {  // Check if there's actually a value after "+OBJDUMP="
            objdump_path = objdump_arg + 9;  // Use command line argument
            std::cout << "Using objdump from +OBJDUMP argument: " << objdump_path << std::endl;
        } else {
            // Read from env.config
            std::string riscv_prefix = read_config_value("RISCV_PREFIX");
            if (!riscv_prefix.empty()) {
                objdump_path = riscv_prefix + "objdump";
                std::cout << "Using objdump from env.config: " << objdump_path << std::endl;
            } else {
                objdump_path = "riscv-none-elf-objdump";  // Default fallback
                std::cout << "Using default objdump: " << objdump_path << std::endl;
            }
        }

        // Derive ELF filename from binary (replace .bin with .elf)
        std::string elf_name = prog_name;
        size_t dot_pos = elf_name.rfind(".bin");
        if (dot_pos != std::string::npos) {
            elf_name.replace(dot_pos, 4, ".elf");
        }

        // Load disassembly from objdump using ELF file
        disasm_map = load_disassembly(elf_name, objdump_path);
    }

    // Simulation parameters
    vluint64_t max_cycles = 5*1000*1000;  // 5M cycles max
    vluint64_t cycle = 0;
    bool finished = false;
    bool error = false;  // Track if simulation ended with error

    const char* cycle_arg = Verilated::commandArgsPlusMatch("MAX_CYCLES=");
    if (cycle_arg) {
        int cycles;
        if (sscanf(cycle_arg, "+MAX_CYCLES=%d", &cycles) == 1) {
            max_cycles = cycles;
        }
    }

    std::cout << "=== Verilator RTL Simulation ===" << std::endl;
    if (max_cycles == 0) {
        std::cout << "Max cycles: unlimited" << std::endl;
    } else {
        std::cout << "Max cycles: " << max_cycles << std::endl;
    }

    // Initialize inputs
    dut->clk = 0;
    dut->rst_n = 0;
    dut->uart_rx = 1;

    uint32_t prev_wb_pc = 0;
    uint32_t same_pc_retire_count = 0;
    const uint32_t INFINITE_LOOP_THRESHOLD = 100;  // Same PC retiring many times = infinite loop (increased to allow exit processing)
    const uint64_t MIN_INSTRET_FOR_TIMEOUT = 5;  // Only check timeout after some instructions retired

    // Track instruction retirement for trace
    uint64_t prev_instret = 0;

    // Helper function to get register name
    // Optimized register name lookup using static array
    static const char* reg_names[32] = {
        "x0 ", "x1 ", "x2 ", "x3 ", "x4 ", "x5 ", "x6 ", "x7 ",
        "x8 ", "x9 ", "x10", "x11", "x12", "x13", "x14", "x15",
        "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23",
        "x24", "x25", "x26", "x27", "x28", "x29", "x30", "x31"
    };

    auto get_reg_name = [](uint32_t reg) -> const char* {
        return (reg < 32) ? reg_names[reg] : "x??";
    };

    // Helper function to get CSR name
    auto get_csr_name = [](uint32_t addr) -> std::string {
        switch (addr) {
            case 0x300: return "mstatus";
            case 0x304: return "mie";
            case 0x305: return "mtvec";
            case 0x340: return "mscratch";
            case 0x341: return "mepc";
            case 0x342: return "mcause";
            case 0x343: return "mtval";
            case 0x344: return "mip";
            case 0xB00: return "mcycle";
            case 0xB02: return "minstret";
            case 0xC00: return "cycle";
            case 0xC02: return "instret";
            case 0xF11: return "mvendorid";
            case 0xF12: return "marchid";
            case 0xF13: return "mimpid";
            case 0xF14: return "mhartid";
            default: {
                static char buf[16];
                snprintf(buf, sizeof(buf), "0x%03x", addr);
                return std::string(buf);
            }
        }
    };

    #ifdef HAVE_CHRONO
    time_begin = std::chrono::steady_clock::now();
    #endif

    // Run simulation
    while (!Verilated::gotFinish() && (max_cycles == 0 || cycle < max_cycles) && !finished) {
        // Clock low phase
        dut->clk = 0;
        dut->eval();

        // Dump trace for falling edge
#ifdef TRACE_FST
        if (tfp) {
            tfp->dump(main_time);
        }
#endif
#ifdef TRACE_VCD
        if (tfp_vcd) {
            tfp_vcd->dump(main_time);
        }
#endif
        main_time += (RESOLUTION/2);

        // Release reset after 10 cycles
        if (cycle == 10) {
            dut->rst_n = 1;
            std::cout << "Reset released at cycle " << cycle << std::endl;
        }

        // Clock high phase
        dut->clk = 1;
        dut->eval();

        // Monitor UART TX output
        uart_monitor(dut->uart_tx);

        // Drive UART RX input (stimulus)
        dut->uart_rx = uart_transmit();

        // Check for NULL pointer access (PC = 0)
        if (dut->cpu_pc == 0 && cycle > 10) {
            std::cout << "\n=== ERROR: NULL Pointer Execution Detected ===" << std::endl;
            std::cout << "PC jumped to address 0x00000000" << std::endl;
            std::cout << "Cycle: " << cycle << std::endl;
            std::cout << "Instructions executed: " << dut->instret_count << std::endl;
            std::cout << "Last valid PC: 0x" << std::hex << (uint32_t)dut->wb_pc << std::dec << std::endl;
            finished = true;
            break;
        }

        // Check for NULL pointer memory access
        if (dut->mem_valid && dut->mem_addr == 0 && cycle > 10) {
            std::cout << "\n=== ERROR: NULL Pointer Memory Access Detected ===" << std::endl;
            std::cout << "Memory " << (dut->mem_write ? "write" : "read") << " to address 0x00000000" << std::endl;
            std::cout << "PC: 0x" << std::hex << (uint32_t)dut->wb_pc << std::dec << std::endl;
            std::cout << "Cycle: " << cycle << std::endl;
            std::cout << "Instructions executed: " << dut->instret_count << std::endl;
            finished = true;
            break;
        }

        // Write trace when instruction retires (wb_instr_retired pulses)
        // Format: CYCLES PC (INSTR) [REGWRITE] [MEMACCESS] [CSRACCESS] ; DISASM
        if (enable_trace && dut->wb_instr_retired) {
            std::ostringstream line_stream;

            // Start with: CYCLES PC (INSTR)
            line_stream << std::dec << (uint64_t)dut->cycle_count << " "
                       << "0x" << std::hex << std::setfill('0') << std::setw(8) << (uint32_t)dut->wb_pc << " "
                       << "(0x" << std::setw(8) << (uint32_t)dut->wb_instr << ")";

            // Add register write if present (rd != 0)
            // Calculate has_rd_write based on opcode since wb_rd_write has struct access issues
            bool has_rd_write = (dut->wb_rd != 0) &&
                               (dut->wb_opcode != 0x23) &&  // Not STORE
                               (dut->wb_opcode != 0x63);    // Not BRANCH
            if (has_rd_write) {
                const char* reg_name = get_reg_name(dut->wb_rd);
                line_stream << " " << reg_name
                           << " 0x" << std::setw(8) << std::setfill('0') << std::right << (uint32_t)dut->wb_rd_data;
            }

            // Add memory operation if present (all signals are from WB stage now)
            if (dut->mem_valid) {
                line_stream << " mem 0x" << std::setw(8) << std::setfill('0') << (uint32_t)dut->mem_addr;
                if (dut->mem_write) {
                    // For stores, show the data written
                    line_stream << " 0x" << std::setw(8) << std::setfill('0') << (uint32_t)dut->mem_wdata;
                }
            }

            // Add CSR operation if present (matches Spike format: c<addr>_<name> <value>)
            if (dut->csr_valid) {
                std::string csr_name = get_csr_name(dut->csr_addr);
                line_stream << " c" << std::setw(3) << std::setfill('0') << std::hex << (uint32_t)dut->csr_addr
                           << "_" << csr_name
                           << " 0x" << std::setw(8) << std::setfill('0') << (uint32_t)dut->csr_wdata;
            }

            // Get base line for alignment
            std::string base_line = line_stream.str();

            // Add disassembly comment aligned at column 72
            std::string disasm = "unknown";
            auto it = disasm_map.find((uint32_t)dut->wb_pc);
            if (it != disasm_map.end()) {
                disasm = it->second;
            }

            int padding_needed = 72 - base_line.length();
            if (padding_needed < 2) padding_needed = 2;  // At least 2 spaces

            trace_file << base_line << std::string(padding_needed, ' ') << "; " << disasm << std::endl;
        }

        // Check for magic exit address write
        if (dut->exit_request) {
            std::cout << "\n=== Program Exit Requested ===" << std::endl;
            std::cout << "Exit code: " << (int32_t)dut->exit_code << " (0x"
                      << std::hex << (uint32_t)dut->exit_code << std::dec << ")" << std::endl;

            // Extract signature if requested via +SIGNATURE=
            const char* sig_arg = Verilated::commandArgsPlusMatch("SIGNATURE=");
            if (sig_arg) {
                std::string sig_file = sig_arg + 11;  // Skip "+SIGNATURE="

                // Get signature begin/end addresses
                uint32_t sig_begin = 0, sig_end = 0;

                const char* sig_begin_arg = Verilated::commandArgsPlusMatch("SIG_BEGIN=");
                if (sig_begin_arg) {
                    sscanf(sig_begin_arg, "+SIG_BEGIN=%x", &sig_begin);
                }

                const char* sig_end_arg = Verilated::commandArgsPlusMatch("SIG_END=");
                if (sig_end_arg) {
                    sscanf(sig_end_arg, "+SIG_END=%x", &sig_end);
                }

                if (sig_begin && sig_end) {

                    std::cout << "Extracting signature from 0x" << std::hex << sig_begin
                              << " to 0x" << sig_end << std::dec << std::endl;

                    // Set the scope for DPI calls to the memory module
                    svSetScope(svGetScopeFromName("TOP.tb_soc.u_memory"));

                    // Dump signature to file
                    std::ofstream sig_out(sig_file);
                    if (sig_out.is_open()) {
                        for (uint32_t addr = sig_begin; addr < sig_end; addr += 4) {
                            uint32_t word = 0;
                            for (int i = 0; i < 4; i++) {
                                word |= ((uint8_t)mem_read_byte(addr + i)) << (i * 8);
                            }
                            sig_out << std::hex << std::setw(8) << std::setfill('0') << word << std::endl;
                        }
                        sig_out.close();
                        std::cout << "Signature written to " << sig_file << std::endl;
                    } else {
                        std::cerr << "Error: Could not open signature file: " << sig_file << std::endl;
                    }
                }
            }

            std::cout << "Program terminated normally." << std::endl;
            finished = true;
            break;
        }

        // Check for infinite loop (CPU stuck at same PC)
        if (cycle >= 10 && dut->instret_count >= MIN_INSTRET_FOR_TIMEOUT) {
            if (dut->wb_instr_retired) {
                uint32_t current_wb_pc = dut->wb_pc;
                if (current_wb_pc == prev_wb_pc) {
                    same_pc_retire_count++;
                    if (same_pc_retire_count >= INFINITE_LOOP_THRESHOLD) {
                        // Check if exit was already requested (exit hang loop)
                        if (dut->exit_request) {
                            // This is the expected hang loop after exit - terminate gracefully
                            std::cout << "Program exit processed (at hang loop)." << std::endl;
                            finished = true;
                            break;
                        } else {
                            // Real infinite loop - report error
                            std::cerr << "\n=== ERROR: Infinite Loop Detected ===" << std::endl;
                            std::cerr << "PC 0x" << std::hex << current_wb_pc << std::dec
                                      << " retired " << same_pc_retire_count << " times consecutively" << std::endl;
                            std::cerr << "Last instruction: 0x" << std::hex << (uint32_t)dut->wb_instr << std::dec << std::endl;
                            std::cerr << "Simulation halted due to infinite loop." << std::endl;
                            error = true;
                            finished = true;
                            break;
                        }
                    }
                } else {
                    same_pc_retire_count = 0;
                    prev_wb_pc = current_wb_pc;
                }
            }
        }

        // Dump trace for rising edge
#ifdef TRACE_FST
        if (tfp) {
            tfp->dump(main_time);
        }
#endif

#ifdef TRACE_VCD
        if (tfp_vcd) {
            tfp_vcd->dump(main_time);
        }
#endif

        // Advance time and cycle counter
        main_time += (RESOLUTION/2);
        cycle++;
    }

    #ifdef HAVE_CHRONO
    time_end = std::chrono::steady_clock::now();
    #endif

    // Display final statistics
    std::cout << "\n=== Simulation Statistics ===" << std::endl;

    #ifdef HAVE_CHRONO
    {
        float sec = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_begin).count() / 1000.0;
        if (sec == 0) {
            std::cout << "Simulation speed : N/A" << std::endl;
        } else {
            float speed_mhz = cycle / sec / 1000000.0;
            std::cout << "Simulation speed : " << speed_mhz << "MHz" << std::endl;
        }
    }
    #endif

    std::cout << "Simulation time  : " << main_time << " ns" << std::endl;
    std::cout << "Total cycles     : " << cycle << std::endl;
    std::cout << "Cycles (counter) : " << (uint64_t)dut->cycle_count << std::endl;
    std::cout << "Instructions     : " << (uint64_t)dut->instret_count << std::endl;
    std::cout << "Stall cycles     : " << (uint64_t)dut->stall_count << std::endl;

    if (dut->instret_count > 0) {
        double cpi = (double)dut->cycle_count / (double)dut->instret_count;
        std::cout << "CPI              : " << cpi << std::endl;
    }

    // Check if simulation timed out
    if (!finished && max_cycles > 0 && cycle >= max_cycles) {
        std::cerr << "\n*** ERROR: Simulation reached maximum cycle limit ***" << std::endl;
        std::cerr << "*** Program did not complete normally (no exit request) ***" << std::endl;
        std::cerr << "*** Consider increasing MAX_CYCLES or check for infinite loops ***" << std::endl;
        error = true;
    }

    // Final evaluation
    dut->eval();

    // Cleanup
    trace_file.close();

#ifdef TRACE_FST
    if (tfp) {
        tfp->close();
        delete tfp;
    }
#endif

#ifdef TRACE_VCD
    if (tfp_vcd) {
        tfp_vcd->close();
        delete tfp_vcd;
    }
#endif

    delete dut;

    std::cout << "\nSimulation complete." << std::endl;

    // Return 0 for success, 1 for error
    if (error) {
        return 1;  // Abnormal termination (infinite loop, timeout, etc.)
    } else if (finished) {
        return 0;  // Normal termination (exit request processed)
    } else {
        return 1;  // Unexpected termination
    }
}
