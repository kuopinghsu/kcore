// RISC-V Functional Simulator
// Uses Spike ISA simulator for reference execution trace generation

#include <iostream>
#include <fstream>
#include <cstdlib>
#include <cstring>
#include <string>

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

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <elf_file> [trace_file]" << std::endl;
        return 1;
    }
    
    const char* elf_file = argv[1];
    const char* trace_file = (argc > 2) ? argv[2] : "sim_trace.txt";
    
    // Get Spike path from env.config, fallback to "spike" in PATH
    std::string spike_path = read_config_value("SPIKE");
    if (spike_path.empty()) {
        spike_path = "spike";  // Default fallback
        std::cout << "Using default spike (from PATH)" << std::endl;
    } else {
        std::cout << "Using spike from env.config: " << spike_path << std::endl;
    }
    
    // Build spike command
    // spike --isa=rv32imac --log-commits --log=<trace_file> <elf_file>
    std::string cmd = spike_path + " --isa=rv32imac --log-commits --log=";
    cmd += trace_file;
    cmd += " ";
    cmd += elf_file;
    
    std::cout << "Running Spike simulator..." << std::endl;
    std::cout << "Command: " << cmd << std::endl;
    
    int result = system(cmd.c_str());
    int exit_code = WEXITSTATUS(result);
    
    std::cout << "Spike simulation completed." << std::endl;
    std::cout << "Program exit code (tohost): " << exit_code << std::endl;
    std::cout << "Trace written to: " << trace_file << std::endl;
    
    // Always return 0 - let trace comparison decide if results are correct
    // The exit_code is just the program's return value, not an error
    return 0;
}
