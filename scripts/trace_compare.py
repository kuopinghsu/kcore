#!/usr/bin/env python3
"""
Trace Comparison Tool
Compares execution traces from RTL, Spike, and rv32sim with all combinations
Supports:
  - RTL vs Spike
  - RTL vs rv32sim
  - Spike vs rv32sim
  - RTL vs Spike vs rv32sim (three-way comparison)
"""

import sys
import re
import argparse

def parse_rtl_trace(filename):
    """Parse RTL trace file (format: CYCLES PC (INSTR) ...)"""
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
                    'instr': int(instr, 16),
                    'line': line
                })
    return traces

def parse_spike_trace(filename):
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
                    'instr': int(instr, 16),
                    'line': line
                })
                continue
            # Try Spike format with --log-commits: core   0: 3 0x80000000 (0x00000297) ...
            match = re.match(r'core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)', line)
            if match:
                pc, instr = match.groups()
                traces.append({
                    'pc': int(pc, 16),
                    'instr': int(instr, 16),
                    'line': line
                })
    return traces

def detect_trace_type(filename):
    """Detect if this is an RTL trace or Spike/rv32sim trace"""
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # RTL format starts with cycle count (number without 'core')
            if re.match(r'^\d+\s+0x[0-9a-fA-F]+\s+\(0x[0-9a-fA-F]+\)', line):
                return 'rtl'
            # Spike/rv32sim format starts with 'core'
            if re.match(r'^core\s+\d+:', line):
                return 'spike'
    return 'unknown'

def compare_traces(traces1, traces2, name1="Trace1", name2="Trace2"):
    """Compare two traces (generic comparison)"""
    print(f"{name1} entries: {len(traces1)}")
    print(f"{name2} entries: {len(traces2)}")

    # Fail if either trace is empty
    if len(traces1) == 0 or len(traces2) == 0:
        print(f"\n[FAIL] One or both traces are empty")
        return 1

    # Find where traces align (skip bootloader if necessary)
    trace1_start_pc = traces1[0]['pc']
    trace2_offset = 0
    for i, entry in enumerate(traces2):
        if entry['pc'] == trace1_start_pc:
            trace2_offset = i
            if trace2_offset > 0:
                print(f"Aligning traces: {name2} offset = {trace2_offset} (skipping bootloader)")
            break

    if trace2_offset == 0 and trace1_start_pc != traces2[0]['pc']:
        print(f"\n[FAIL] Cannot align traces - {name1} starts at 0x{trace1_start_pc:08x}, {name2} starts at 0x{traces2[0]['pc']:08x}")
        return 1

    mismatches = 0
    max_compare = min(len(traces1), len(traces2) - trace2_offset)

    for i in range(max_compare):
        t1 = traces1[i]
        t2 = traces2[i + trace2_offset]

        if t1['pc'] != t2['pc'] or t1['instr'] != t2['instr']:
            print(f"\nMismatch at entry {i}:")
            print(f"  {name1:10s}: PC=0x{t1['pc']:08x} INSTR=0x{t1['instr']:08x}")
            print(f"  {name2:10s}: PC=0x{t2['pc']:08x} INSTR=0x{t2['instr']:08x}")
            mismatches += 1
            if mismatches >= 10:
                print("\n... stopping after 10 mismatches")
                break

    effective_trace2_len = len(traces2) - trace2_offset
    if mismatches == 0:
        if len(traces1) == effective_trace2_len:
            print(f"\n[PASS] Traces match perfectly!")
            return 0
        elif len(traces1) < effective_trace2_len:
            print(f"\n[PASS] All {len(traces1)} {name1} instructions match {name2}")
            print(f"  ({name2} continued for {effective_trace2_len - len(traces1)} more instructions)")
            return 0
        else:
            print(f"\n[PASS] All {name2} instructions matched, but {name1} has {len(traces1) - effective_trace2_len} extra entries")
            return 0
    else:
        print(f"\n[FAIL] Found {mismatches} mismatches")
        if len(traces1) != effective_trace2_len:
            print(f"  Length mismatch: {name1}={len(traces1)} {name2}={effective_trace2_len}")
        return 1

def compare_three_way(rtl_traces, spike_traces, rv32sim_traces):
    """Three-way comparison of RTL, Spike, and rv32sim traces"""
    print("=== Three-Way Trace Comparison ===\n")
    print(f"RTL entries:     {len(rtl_traces)}")
    print(f"Spike entries:   {len(spike_traces)}")
    print(f"rv32sim entries: {len(rv32sim_traces)}\n")

    # Align all three traces
    rtl_start = rtl_traces[0]['pc'] if rtl_traces else 0
    spike_offset = 0
    rv32sim_offset = 0

    for i, entry in enumerate(spike_traces):
        if entry['pc'] == rtl_start:
            spike_offset = i
            break

    for i, entry in enumerate(rv32sim_traces):
        if entry['pc'] == rtl_start:
            rv32sim_offset = i
            break

    if spike_offset > 0:
        print(f"Spike alignment offset: {spike_offset}")
    if rv32sim_offset > 0:
        print(f"rv32sim alignment offset: {rv32sim_offset}")

    mismatches = 0
    max_compare = min(
        len(rtl_traces),
        len(spike_traces) - spike_offset,
        len(rv32sim_traces) - rv32sim_offset
    )

    for i in range(max_compare):
        rtl = rtl_traces[i]
        spike = spike_traces[i + spike_offset]
        rv32 = rv32sim_traces[i + rv32sim_offset]

        all_match = (rtl['pc'] == spike['pc'] == rv32['pc'] and
                     rtl['instr'] == spike['instr'] == rv32['instr'])

        if not all_match:
            print(f"\nMismatch at entry {i}:")
            print(f"  RTL:     PC=0x{rtl['pc']:08x} INSTR=0x{rtl['instr']:08x}")
            print(f"  Spike:   PC=0x{spike['pc']:08x} INSTR=0x{spike['instr']:08x}")
            print(f"  rv32sim: PC=0x{rv32['pc']:08x} INSTR=0x{rv32['instr']:08x}")
            mismatches += 1
            if mismatches >= 10:
                print("\n... stopping after 10 mismatches")
                break

    if mismatches == 0:
        print(f"\n[PASS] All three traces match for {max_compare} instructions!")
        return 0
    else:
        print(f"\n[FAIL] Found {mismatches} mismatches in three-way comparison")
        return 1
def main():
    parser = argparse.ArgumentParser(
        description='Compare execution traces from RTL, Spike, and rv32sim',
        epilog='''
Examples:
  # Two-way comparisons
  %(prog)s build/rtl_trace.txt spike_trace.txt
  %(prog)s build/rtl_trace.txt build/sim_trace.txt
  %(prog)s spike_trace1.txt spike_trace2.txt

  # Three-way comparison
  %(prog)s --rtl build/rtl_trace.txt --spike spike.txt --rv32sim sim.txt
        ''',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    # Support both positional and named arguments
    parser.add_argument('trace1', nargs='?', help='First trace file (auto-detect format)')
    parser.add_argument('trace2', nargs='?', help='Second trace file (auto-detect format)')
    parser.add_argument('--rtl', help='RTL trace file (for three-way comparison)')
    parser.add_argument('--spike', help='Spike trace file (for three-way comparison)')
    parser.add_argument('--rv32sim', help='rv32sim trace file (for three-way comparison)')

    args = parser.parse_args()

    try:
        # Three-way comparison mode
        if args.rtl and args.spike and args.rv32sim:
            print(f"Comparing three traces:")
            print(f"  RTL:     {args.rtl}")
            print(f"  Spike:   {args.spike}")
            print(f"  rv32sim: {args.rv32sim}\n")

            rtl_traces = parse_rtl_trace(args.rtl)
            spike_traces = parse_spike_trace(args.spike)
            rv32sim_traces = parse_spike_trace(args.rv32sim)

            result = compare_three_way(rtl_traces, spike_traces, rv32sim_traces)
            sys.exit(result)

        # Two-way comparison mode
        elif args.trace1 and args.trace2:
            print(f"Comparing two traces:")
            print(f"  Trace 1: {args.trace1}")
            print(f"  Trace 2: {args.trace2}\n")

            # Auto-detect trace formats
            type1 = detect_trace_type(args.trace1)
            type2 = detect_trace_type(args.trace2)

            print(f"Detected formats: {type1} vs {type2}\n")

            if type1 == 'rtl':
                traces1 = parse_rtl_trace(args.trace1)
                name1 = "RTL"
            elif type1 == 'spike':
                traces1 = parse_spike_trace(args.trace1)
                name1 = "Trace1"
            else:
                print(f"Error: Unknown format for {args.trace1}")
                sys.exit(1)

            if type2 == 'rtl':
                traces2 = parse_rtl_trace(args.trace2)
                name2 = "RTL"
            elif type2 == 'spike':
                traces2 = parse_spike_trace(args.trace2)
                name2 = "Trace2"
            else:
                print(f"Error: Unknown format for {args.trace2}")
                sys.exit(1)

            result = compare_traces(traces1, traces2, name1, name2)
            sys.exit(result)

        else:
            parser.print_help()
            sys.exit(1)

    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
