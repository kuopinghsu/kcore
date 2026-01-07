#!/usr/bin/env python3
"""
Extract test signature from Verilator simulation by running it with signature parameters.
Supports debug mode for tracing and comparison with Spike reference model.
"""

import sys
import re
import subprocess
import os
import shutil

# Get debug mode from environment
DEBUG_MODE = os.environ.get('RISCOF_DEBUG', '0') == '1'

if DEBUG_MODE:
    print(f"[DEBUG] *** Debug mode enabled (RISCOF_DEBUG={os.environ.get('RISCOF_DEBUG')}) ***")

def print_debug(msg):
    """Print debug message if debug mode is enabled"""
    if DEBUG_MODE:
        print(f"[DEBUG] {msg}")

def extract_signature(elf_file, sig_file):
    """Run simulation and extract signature"""
    try:
        # Read signature addresses from .symbols file or extract directly from ELF
        symbols_file = elf_file + '.symbols'
        sig_begin = None
        sig_end = None

        if os.path.exists(symbols_file):
            with open(symbols_file, 'r') as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        if 'begin_signature' == parts[2]:
                            sig_begin = int(parts[0], 16)
                        elif 'end_signature' == parts[2]:
                            sig_end = int(parts[0], 16)

        # If symbols not found or file doesn't exist, try to extract directly from ELF
        if (sig_begin is None or sig_end is None) and os.path.exists(elf_file):
            print_debug(f"Symbols not found in file, extracting from ELF {elf_file}")
            # Get RISCV_PREFIX from environment or use default
            import configparser
            script_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.abspath(os.path.join(script_dir, '../../..'))
            env_config_path = os.path.join(project_root, 'env.config')

            riscv_prefix = 'riscv-none-elf-'
            if os.path.exists(env_config_path):
                with open(env_config_path, 'r') as f:
                    for line in f:
                        if line.startswith('RISCV_PREFIX='):
                            riscv_prefix = line.split('=', 1)[1].strip()
                            break

            print_debug(f"Using riscv_prefix: {riscv_prefix}")
            # Run nm to get symbols
            try:
                nm_cmd = [riscv_prefix + 'nm', elf_file]
                print_debug(f"Running {' '.join(nm_cmd)}")
                result = subprocess.run(nm_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
                print_debug(f"nm returned {result.returncode}, output lines: {len(result.stdout.split(chr(10)))}")
                for line in result.stdout.split('\n'):
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        if 'begin_signature' == parts[2]:
                            sig_begin = int(parts[0], 16)
                            print_debug(f"Found begin_signature = 0x{sig_begin:x}")
                        elif 'end_signature' == parts[2]:
                            sig_end = int(parts[0], 16)
                            print_debug(f"Found end_signature = 0x{sig_end:x}")
            except Exception as e:
                print(f"Warning: Could not run nm: {e}")

        if sig_begin is None or sig_end is None:
            print(f"Warning: Could not find signature addresses (begin={sig_begin}, end={sig_end})")
            # Create empty signature file
            with open(sig_file, 'w') as f:
                f.write("")
            return 0

        # Get DUT executable path (relative to plugin directory)
        script_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.abspath(os.path.join(script_dir, '../../..'))
        
        # Use FST binary in debug mode, standard binary otherwise
        if DEBUG_MODE:
            dut_exe = os.path.join(project_root, 'build/verilator_fst/kcore_vsim')
        else:
            dut_exe = os.path.join(project_root, 'build/verilator/kcore_vsim')
        
        test_dir = os.path.dirname(sig_file)
        test_name = os.path.basename(test_dir)

        # In debug mode, save outputs in a dedicated directory
        if DEBUG_MODE:
            debug_dir = os.path.join(test_dir, 'debug_output')
            os.makedirs(debug_dir, exist_ok=True)
            print(f"[DEBUG] Test: {test_name}")
            print(f"[DEBUG] Debug output directory: {debug_dir}")

        # Run simulation with signature extraction
        cmd = [
            dut_exe,
            f'+PROGRAM={elf_file}',
            f'+MAX_CYCLES=100000',
            f'+SIGNATURE={sig_file}',
            f'+SIG_BEGIN={sig_begin:x}',
            f'+SIG_END={sig_end:x}'
        ]
        
        # Enable RTL trace in debug mode
        if DEBUG_MODE:
            cmd.append('+TRACE')

        log_file = sig_file + '.log'
        with open(log_file, 'w') as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=test_dir)

        print_debug(f"Simulation returned: {result.returncode}")

        if result.returncode != 0:
            print(f"Warning: Simulation returned non-zero exit code: {result.returncode}")

        # In debug mode, save RTL trace if it was generated
        if DEBUG_MODE:
            rtl_trace = os.path.join(test_dir, 'rtl_trace.txt')
            if os.path.exists(rtl_trace):
                debug_trace = os.path.join(debug_dir, f'{test_name}_rtl_trace.txt')
                shutil.copy(rtl_trace, debug_trace)
                print(f"[DEBUG] RTL trace saved: {debug_trace}")
                
                # Also show first 50 lines of RTL trace
                try:
                    with open(debug_trace, 'r') as f:
                        lines = f.readlines()[:50]
                    print(f"[DEBUG] First 50 lines of RTL trace:")
                    for i, line in enumerate(lines, 1):
                        print(f"[DEBUG] {i:3d}: {line.rstrip()}")
                except Exception as e:
                    print(f"[DEBUG] Could not read RTL trace: {e}")
            else:
                print(f"[DEBUG] RTL trace file not found at: {rtl_trace}")
            
            # Save simulation log
            if os.path.exists(log_file):
                debug_log = os.path.join(debug_dir, f'{test_name}_sim.log')
                shutil.copy(log_file, debug_log)
                print(f"[DEBUG] Simulation log saved: {debug_log}")

        # Check if signature file was created
        if not os.path.exists(sig_file) or os.path.getsize(sig_file) == 0:
            print(f"Warning: Signature file is empty or not created")
            with open(sig_file, 'w') as f:
                f.write("")

        return 0
    except Exception as e:
        print(f"Error extracting signature: {e}")
        # Create empty signature to allow test to continue
        with open(sig_file, 'w') as f:
            f.write("")
        return 1

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: extract_signature.py <elf_file> <output_signature_file>")
        print("Debug mode can be enabled with: export RISCOF_DEBUG=1")
        sys.exit(1)


    sys.exit(extract_signature(sys.argv[1], sys.argv[2]))
