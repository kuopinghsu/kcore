#!/usr/bin/env python3
"""
Trace Comparison Tool
Compares RTL execution trace with Spike ISA simulator trace
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

def parse_spike_trace(filename):
    """Parse Spike trace file"""
    traces = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Spike format: core   0: 3 0x80000000 (0x00000297) ...
            # The number after colon is the privilege level
            match = re.match(r'core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)', line)
            if match:
                pc, instr = match.groups()
                traces.append({
                    'pc': int(pc, 16),
                    'instr': int(instr, 16)
                })
    return traces

def compare_traces(rtl_traces, spike_traces):
    """Compare RTL and Spike traces"""
    print(f"RTL trace entries: {len(rtl_traces)}")
    print(f"Spike trace entries: {len(spike_traces)}")
    
    # Fail if either trace is empty
    if len(rtl_traces) == 0 or len(spike_traces) == 0:
        print("\n[FAIL] One or both traces are empty")
        return 1
    
    # Find where Spike trace starts matching RTL (skip bootloader)
    rtl_start_pc = rtl_traces[0]['pc'] if len(rtl_traces) > 0 else 0
    spike_offset = 0
    for i, spike_entry in enumerate(spike_traces):
        if spike_entry['pc'] == rtl_start_pc:
            spike_offset = i
            print(f"Aligning traces: Spike offset = {spike_offset} (skipping bootloader)")
            break
    
    if spike_offset == 0 and rtl_start_pc != spike_traces[0]['pc']:
        print(f"\n[FAIL] Cannot align traces - RTL starts at 0x{rtl_start_pc:08x}, Spike starts at 0x{spike_traces[0]['pc']:08x}")
        return 1
    
    mismatches = 0
    max_compare = min(len(rtl_traces), len(spike_traces) - spike_offset)
    
    for i in range(max_compare):
        rtl = rtl_traces[i]
        spike = spike_traces[i + spike_offset]
        
        if rtl['pc'] != spike['pc'] or rtl['instr'] != spike['instr']:
            print(f"\nMismatch at entry {i}:")
            print(f"  RTL:   PC=0x{rtl['pc']:08x} INSTR=0x{rtl['instr']:08x}")
            print(f"  Spike: PC=0x{spike['pc']:08x} INSTR=0x{spike['instr']:08x}")
            mismatches += 1
            if mismatches >= 10:
                print("\n... stopping after 10 mismatches")
                break
    
    effective_spike_len = len(spike_traces) - spike_offset
    if mismatches == 0:
        if len(rtl_traces) == effective_spike_len:
            print("\n[PASS] Traces match perfectly!")
            return 0
        elif len(rtl_traces) < effective_spike_len:
            print(f"\n[PASS] All {len(rtl_traces)} RTL instructions match Spike")
            print(f"  (Spike continued for {effective_spike_len - len(rtl_traces)} more instructions)")
            return 0
        else:
            print(f"\n[FAIL] Length mismatch: RTL={len(rtl_traces)} Spike={effective_spike_len}")
            return 1
    else:
        print(f"\n[FAIL] Found {mismatches} mismatches")
        if len(rtl_traces) != effective_spike_len:
            print(f"  Length mismatch: RTL={len(rtl_traces)} Spike={effective_spike_len}")
        return 1

def main():
    if len(sys.argv) < 3:
        print("Usage: trace_compare.py <rtl_trace> <spike_trace>")
        sys.exit(1)
    
    rtl_file = sys.argv[1]
    spike_file = sys.argv[2]
    
    print(f"Comparing traces:")
    print(f"  RTL:   {rtl_file}")
    print(f"  Spike: {spike_file}")
    print()
    
    try:
        rtl_traces = parse_rtl_trace(rtl_file)
        spike_traces = parse_spike_trace(spike_file)
        result = compare_traces(rtl_traces, spike_traces)
        sys.exit(result)
    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
