#!/usr/bin/env python3
"""
Trace Comparison Tool
Compares RTL execution trace with software simulator trace
"""

import sys
import re

def parse_rtl_trace(filename):
    """Parse RTL trace file"""
    traces = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # Expected format: CYCLES 0xPC (0xINSTR) [optional reg/mem/csr info]
            match = re.match(r'(\d+)\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)', line)
            if match:
                cycle, pc, instr = match.groups()
                traces.append({
                    'cycle': int(cycle),
                    'pc': int(pc, 16),
                    'instr': int(instr, 16)
                })
    return traces

def parse_sim_trace(filename):
    """Parse Spike trace file (handles both -l and --log-commits formats)"""
    traces = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Try Spike format with -l flag: core   0: 0x80000000 (0x00000297) ...
            match = re.match(r'core\s+\d+:\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)', line)
            if match:
                pc, instr = match.groups()
                traces.append({
                    'pc': int(pc, 16),
                    'instr': int(instr, 16)
                })
                continue
            # Try Spike format with --log-commits: core   0: 3 0x80000000 (0x00000297) ...
            match = re.match(r'core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)', line)
            if match:
                pc, instr = match.groups()
                traces.append({
                    'pc': int(pc, 16),
                    'instr': int(instr, 16)
                })
    return traces

def compare_traces(rtl_traces, sim_traces):
    """Compare RTL and software simulator traces"""
    print(f"RTL trace entries: {len(rtl_traces)}")
    print(f"SW Sim trace entries: {len(sim_traces)}")
    
    # Fail if either trace is empty
    if len(rtl_traces) == 0 or len(sim_traces) == 0:
        print("\n[FAIL] One or both traces are empty")
        return 1
    
    # Find where Spike trace starts matching RTL (skip bootloader)
    rtl_start_pc = rtl_traces[0]['pc'] if len(rtl_traces) > 0 else 0
    spike_offset = 0
    for i, spike_entry in enumerate(sim_traces):
        if spike_entry['pc'] == rtl_start_pc:
            spike_offset = i
            print(f"Aligning traces: SW Sim offset = {spike_offset} (skipping bootloader)")
            break
    
    if spike_offset == 0 and rtl_start_pc != sim_traces[0]['pc']:
        print(f"\n[FAIL] Cannot align traces - RTL starts at 0x{rtl_start_pc:08x}, SW Sim starts at 0x{sim_traces[0]['pc']:08x}")
        return 1
    
    mismatches = 0
    max_compare = min(len(rtl_traces), len(sim_traces) - spike_offset)
    
    for i in range(max_compare):
        rtl = rtl_traces[i]
        spike = sim_traces[i + spike_offset]
        
        if rtl['pc'] != spike['pc'] or rtl['instr'] != spike['instr']:
            print(f"\nMismatch at entry {i}:")
            print(f"  RTL:    PC=0x{rtl['pc']:08x} INSTR=0x{rtl['instr']:08x}")
            print(f"  SW Sim: PC=0x{spike['pc']:08x} INSTR=0x{spike['instr']:08x}")
            mismatches += 1
            if mismatches >= 10:
                print("\n... stopping after 10 mismatches")
                break
    
    effective_spike_len = len(sim_traces) - spike_offset
    if mismatches == 0:
        if len(rtl_traces) == effective_spike_len:
            print("\n[PASS] Traces match perfectly!")
            return 0
        elif len(rtl_traces) < effective_spike_len:
            print(f"\n[PASS] All {len(rtl_traces)} RTL instructions match SW Sim")
            print(f"  (SW Sim continued for {effective_spike_len - len(rtl_traces)} more instructions)")
            print(f"  RTL trace ends at line {len(rtl_traces)}")
            print(f"  Last RTL instruction: PC=0x{rtl_traces[-1]['pc']:08x} INSTR=0x{rtl_traces[-1]['instr']:08x}")
            return 0
        else:
            print(f"\n[WARNING] Length mismatch: RTL={len(rtl_traces)} SW Sim={effective_spike_len}")
            print(f"  All SW Sim instructions matched, but RTL trace has {len(rtl_traces) - effective_spike_len} extra entries")
            print(f"  SW Sim trace ends at line {effective_spike_len + spike_offset} (after alignment)")
            print(f"  RTL continues from line {effective_spike_len + 1} to {len(rtl_traces)}")
            if effective_spike_len > 0:
                print(f"  Last matching instruction: PC=0x{sim_traces[effective_spike_len + spike_offset - 1]['pc']:08x}")
            if effective_spike_len < len(rtl_traces):
                print(f"  First unmatched RTL instruction (line {effective_spike_len + 1}): PC=0x{rtl_traces[effective_spike_len]['pc']:08x} INSTR=0x{rtl_traces[effective_spike_len]['instr']:08x}")
            print(f"\n[PASS] Partial match - core instructions verified (extra entries are acceptable)")
            return 0
    else:
        print(f"\n[FAIL] Found {mismatches} mismatches")
        if len(rtl_traces) != effective_spike_len:
            print(f"  Length mismatch: RTL={len(rtl_traces)} SW Sim={effective_spike_len}")
            if len(rtl_traces) > effective_spike_len:
                print(f"  RTL has {len(rtl_traces) - effective_spike_len} extra entries after line {effective_spike_len}")
            else:
                print(f"  SW Sim has {effective_spike_len - len(rtl_traces)} extra entries after line {len(rtl_traces)}")
        return 1

def main():
    if len(sys.argv) < 3:
        print("Usage: trace_compare.py <rtl_trace> <sim_trace>")
        sys.exit(1)
    
    rtl_file = sys.argv[1]
    spike_file = sys.argv[2]
    
    print(f"Comparing traces:")
    print(f"  RTL:    {rtl_file}")
    print(f"  SW Sim: {spike_file}")
    print()
    
    try:
        rtl_traces = parse_rtl_trace(rtl_file)
        sim_traces = parse_sim_trace(spike_file)
        result = compare_traces(rtl_traces, sim_traces)
        sys.exit(result)
    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
