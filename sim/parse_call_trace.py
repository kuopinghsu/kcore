#!/usr/bin/env python3
"""
Parse RTL trace and generate call trace with function names
"""

import sys
import re
import subprocess
from pathlib import Path
from collections import defaultdict

# Configuration: Maximum number of trace entries to display in output files
# Increase this value if you need to see more trace entries
MAX_TRACE_ENTRIES = 5000

def get_symbols_from_elf(elf_file, toolchain_prefix):
    """Extract symbol table from ELF file using nm"""
    print(f"Extracting symbols from {elf_file}...")
    
    nm_cmd = f"{toolchain_prefix}nm -n {elf_file}"
    try:
        result = subprocess.run(nm_cmd, shell=True, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running nm: {e}")
        return []
    
    symbols = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            addr = int(parts[0], 16)
            sym_type = parts[1]
            name = ' '.join(parts[2:])
            symbols.append((addr, name, sym_type))
    
    print(f"Found {len(symbols)} symbols")
    return symbols

def addr_to_symbol(addr, symbols):
    """Find the function name for a given address"""
    if not symbols:
        return None
    
    # Find the symbol with the highest address <= addr
    best_match = None
    best_addr = 0
    
    for sym_addr, name, sym_type in symbols:
        if sym_addr <= addr and sym_addr > best_addr:
            # Only consider text (T/t) symbols for functions
            if sym_type in ['T', 't', 'W', 'w']:
                best_match = name
                best_addr = sym_addr
    
    if best_match:
        offset = addr - best_addr
        if offset > 0:
            return f"{best_match}+0x{offset:x}"
        else:
            return best_match
    
    return None

def parse_rtl_trace(trace_file, symbols):
    """Parse RTL trace and generate call trace"""
    print(f"Parsing {trace_file}...")
    
    current_func = None
    func_call_count = defaultdict(int)
    call_trace = []
    pc_history = []
    
    with open(trace_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            # Format: "cycle_num 0xPC (0xINSTR) ..."
            # Example: "7 0x80000000 (0x00000297) x5  0x80000000                                ; auipc t0,0x0"
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            
            # Second column should be PC (0xHHHHHHHH format)
            if not parts[1].startswith('0x'):
                continue
            
            try:
                pc = int(parts[1], 16)
            except ValueError:
                continue
            
            pc_history.append(pc)
            
            # Find function name for this PC
            func_name = addr_to_symbol(pc, symbols)
            
            if func_name:
                # Extract base function name (without offset)
                base_func = func_name.split('+')[0]
                
                # Check if we entered a new function
                if current_func != base_func:
                    func_call_count[base_func] += 1
                    call_trace.append({
                        'line': line_num,
                        'pc': pc,
                        'function': func_name,
                        'count': func_call_count[base_func]
                    })
                    current_func = base_func
            
            # Show progress every 10000 lines
            if line_num % 10000 == 0:
                print(f"Processed {line_num} lines...")
    
    print(f"Total lines processed: {line_num}")
    return call_trace, func_call_count, pc_history

def get_stack_frame_size(elf_file, toolchain_prefix, func_name):
    """Get stack frame size for a function by analyzing its prologue"""
    try:
        # Use objdump to get disassembly
        objdump_cmd = f"{toolchain_prefix}objdump -d {elf_file}"
        result = subprocess.run(objdump_cmd, shell=True, capture_output=True, text=True, check=True)
        
        # Find function and look for "addi sp,sp,-XXX" in prologue
        in_function = False
        for line in result.stdout.splitlines():
            if f"<{func_name}>:" in line:
                in_function = True
                continue
            
            if in_function:
                # Look for stack allocation: addi sp,sp,-XXX
                match = re.search(r'addi\s+sp,sp,(-\d+)', line)
                if match:
                    return abs(int(match.group(1)))
                # Stop at next function or after a few instructions
                if line.strip() and '<' in line and '>:' in line:
                    break
    except:
        pass
    return None

def parse_rtl_trace_tree(trace_file, symbols, elf_file, toolchain_prefix):
    """Parse RTL trace and build call tree with stack tracking"""
    print(f"Parsing {trace_file} for tree structure...")
    
    call_stack = []
    tree_output = []
    prev_pc = None
    
    # Cache for stack sizes
    stack_size_cache = {}
    
    # Track which functions we've already added to tree to avoid duplicates
    seen_calls = set()
    
    with open(trace_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            
            if not parts[1].startswith('0x'):
                continue
            
            try:
                pc = int(parts[1], 16)
            except ValueError:
                continue
            
            # Check instruction type from disassembly comment
            line_lower = line.lower()
            
            # Detect function calls (jal/jalr that saves return address)
            # Format: "x1  0x..." means x1 (ra) is written
            is_call = False
            if '; jal ' in line_lower and ' x1 ' in line_lower:
                is_call = True
            
            # Detect returns (ret or jalr with specific patterns)
            is_return = False
            if '; ret' in line_lower:
                is_return = True
            elif '; jalr' in line_lower and 'x0' in line_lower:
                is_return = True
            
            # Find function name for this PC
            func_name = addr_to_symbol(pc, symbols)
            
            if func_name:
                base_func = func_name.split('+')[0]
                
                # On function call, push to stack
                if is_call:
                    # Find the target function being called
                    # Look for target address in the line
                    target_match = re.search(r'<([^>]+)>', line)
                    if target_match:
                        target_func = target_match.group(1)
                        
                        # Get stack size if not cached
                        if target_func not in stack_size_cache:
                            stack_size_cache[target_func] = get_stack_frame_size(elf_file, toolchain_prefix, target_func)
                        
                        stack_size = stack_size_cache[target_func]
                        
                        # Create unique key for this call to avoid exact duplicates
                        call_key = (len(call_stack), target_func, line_num // 100)  # Group by line number ranges
                        
                        if call_key not in seen_calls:
                            seen_calls.add(call_key)
                            
                            call_stack.append({
                                'name': target_func,
                                'entry_pc': pc,
                                'line': line_num,
                                'stack_size': stack_size
                            })
                            
                            indent = "  " * (len(call_stack) - 1)
                            stack_info = f" [frame: {stack_size} bytes]" if stack_size else ""
                            tree_output.append({
                                'line': line_num,
                                'pc': pc,
                                'indent': indent,
                                'text': f"{target_func}{stack_info}",
                                'depth': len(call_stack) - 1
                            })
                
                # On return, pop from stack
                elif is_return and len(call_stack) > 0:
                    call_stack.pop()
            
            prev_pc = pc
            
            # Progress
            if line_num % 10000 == 0:
                print(f"Processed {line_num} lines...")
    
    print(f"Total lines processed: {line_num}")
    print(f"Call tree entries: {len(tree_output)}")
    print(f"Maximum call depth: {max([e['depth'] for e in tree_output]) + 1 if tree_output else 0}")
    return tree_output, stack_size_cache

def generate_call_trace_report(output_file, call_trace, func_call_count, pc_history, tree_output=None, stack_size_cache=None):
    """Generate detailed call trace report"""
    print(f"Generating report to {output_file}...")
    
    with open(output_file, 'w') as f:
        f.write("=" * 80 + "\n")
        f.write("RTL Call Trace Report\n")
        f.write("=" * 80 + "\n\n")
        
        # Tree view if available
        if tree_output:
            f.write("Call Tree Structure:\n")
            f.write("-" * 80 + "\n")
            for entry in tree_output[:MAX_TRACE_ENTRIES]:
                f.write(f"{entry['indent']}{entry['text']}\n")
            
            if len(tree_output) > MAX_TRACE_ENTRIES:
                f.write(f"\n... ({len(tree_output) - MAX_TRACE_ENTRIES} more calls omitted for brevity)\n")
            
            # Stack usage summary
            if stack_size_cache:
                f.write("\n" + "=" * 80 + "\n")
                f.write("Stack Frame Sizes:\n")
                f.write("-" * 80 + "\n")
                
                sorted_stack = sorted([(k, v) for k, v in stack_size_cache.items() if v], 
                                    key=lambda x: x[1], reverse=True)
                for func, size in sorted_stack[:30]:
                    f.write(f"  {size:4d} bytes  {func}\n")
                
                if sorted_stack:
                    total_stack = sum([v for k, v in sorted_stack])
                    max_depth = max([e['depth'] for e in tree_output]) if tree_output else 0
                    f.write(f"\n  Total stack in traced functions: {total_stack} bytes\n")
                    f.write(f"  Maximum call depth: {max_depth}\n")
        
        f.write("\n" + "=" * 80 + "\n")
        f.write("Function Call Summary (by frequency):\n")
        f.write("-" * 80 + "\n")
        sorted_funcs = sorted(func_call_count.items(), key=lambda x: x[1], reverse=True)
        for func, count in sorted_funcs[:50]:  # Top 50 most called
            f.write(f"  {count:6d}x  {func}\n")
        
        f.write("\n" + "=" * 80 + "\n")
        f.write("Detailed Call Trace (function transitions):\n")
        f.write("=" * 80 + "\n\n")
        
        # Detailed trace
        for entry in call_trace[:MAX_TRACE_ENTRIES]:
            f.write(f"Line {entry['line']:8d}: PC=0x{entry['pc']:08x}  "
                   f"=> {entry['function']}")
            if entry['count'] > 1:
                f.write(f"  [call #{entry['count']}]")
            f.write("\n")
        
        if len(call_trace) > MAX_TRACE_ENTRIES:
            f.write(f"\n... ({len(call_trace) - MAX_TRACE_ENTRIES} more transitions omitted)\n")
        
        # PC range summary
        if pc_history:
            f.write("\n" + "=" * 80 + "\n")
            f.write("PC Range Summary:\n")
            f.write("-" * 80 + "\n")
            f.write(f"  Min PC: 0x{min(pc_history):08x}\n")
            f.write(f"  Max PC: 0x{max(pc_history):08x}\n")
            f.write(f"  Total unique PCs: {len(set(pc_history))}\n")
            
            # Check for invalid PCs (outside normal RAM range)
            invalid_pcs = [pc for pc in pc_history if pc < 0x80000000 or pc > 0x80040000]
            if invalid_pcs:
                f.write(f"\n  WARNING: Found {len(invalid_pcs)} PCs outside RAM range!\n")
                f.write(f"  Invalid PC examples: ")
                f.write(", ".join([f"0x{pc:08x}" for pc in set(invalid_pcs)[:10]]))
                f.write("\n")

def main():
    if len(sys.argv) < 4:
        print("Usage: parse_call_trace.py <trace_file> <elf_file> <toolchain_prefix> [output_file]")
        print("Example: parse_call_trace.py build/rtl_trace.txt build/test.elf riscv-none-elf-")
        sys.exit(1)
    
    trace_file = sys.argv[1]
    elf_file = sys.argv[2]
    toolchain_prefix = sys.argv[3]
    output_file = sys.argv[4] if len(sys.argv) > 4 else "call_trace_report.txt"
    
    # Validate input files
    if not Path(trace_file).exists():
        print(f"Error: Trace file not found: {trace_file}")
        sys.exit(1)
    
    if not Path(elf_file).exists():
        print(f"Error: ELF file not found: {elf_file}")
        sys.exit(1)
    
    # Extract symbols from ELF
    symbols = get_symbols_from_elf(elf_file, toolchain_prefix)
    if not symbols:
        print("Error: No symbols found in ELF file")
        sys.exit(1)
    
    # Parse RTL trace for tree structure
    tree_output, stack_size_cache = parse_rtl_trace_tree(trace_file, symbols, elf_file, toolchain_prefix)
    
    # Parse RTL trace for detailed call info
    call_trace, func_call_count, pc_history = parse_rtl_trace(trace_file, symbols)
    
    # Generate report
    generate_call_trace_report(output_file, call_trace, func_call_count, pc_history, tree_output, stack_size_cache)
    
    print(f"\nReport generated: {output_file}")
    print(f"Total function transitions: {len(call_trace)}")
    print(f"Unique functions called: {len(func_call_count)}")
    print(f"Call tree entries: {len(tree_output)}")

if __name__ == "__main__":
    main()
