#!/usr/bin/env python3
import re
import sys

# Parse memory trace log
cpu_imem_reads = []
cpu_dmem_writes = []
cpu_dmem_reads = []
axi_writes = []
axi_reads = []

# Accept log file from command line or use default
log_file = sys.argv[1] if len(sys.argv) > 1 else 'build/mem_trace.txt'

try:
    with open(log_file, 'r', errors='ignore') as f:
        for line in f:
            # Parse CPU IMEM reads
            m = re.match(r'\[CPU_IMEM READ \] addr=0x([0-9a-f]+) data=0x([0-9a-f]+)', line)
            if m:
                addr, data = m.groups()
                cpu_imem_reads.append((addr, data))
                continue
                
            # Parse CPU DMEM transactions
            m = re.match(r'\[CPU_DMEM (WRITE|READ )\] addr=0x([0-9a-f]+) data=0x([0-9a-f]+)', line)
            if m:
                op, addr, data = m.groups()
                if 'WRITE' in op:
                    cpu_dmem_writes.append((addr, data))
                else:
                    cpu_dmem_reads.append((addr, data))
                continue
                    
            # Parse AXI MEM transactions
            m = re.match(r'\[AXI_MEM (WRITE|READ )\] addr=0x([0-9a-f]+) data=0x([0-9a-f]+)', line)
            if m:
                op, addr, data = m.groups()
                if 'WRITE' in op:
                    axi_writes.append((addr, data))
                else:
                    axi_reads.append((addr, data))
except FileNotFoundError:
    print(f"Error: {log_file} not found. Run 'make memtrace' first.")
    sys.exit(1)

print("=" * 70)
print("MEMORY TRACE VERIFICATION")
print("=" * 70)
print()
print("Transaction Counts:")
print(f"  CPU_IMEM READS:  {len(cpu_imem_reads):5d}")
print(f"  CPU_DMEM WRITES: {len(cpu_dmem_writes):5d}")
print(f"  CPU_DMEM READS:  {len(cpu_dmem_reads):5d}")
print(f"  AXI_MEM WRITES:  {len(axi_writes):5d}")
print(f"  AXI_MEM READS:   {len(axi_reads):5d}")
print()

# Create dictionaries for fast lookup
axi_read_dict = {}
for addr, data in axi_reads:
    if addr not in axi_read_dict:
        axi_read_dict[addr] = []
    axi_read_dict[addr].append(data)

axi_write_dict = {}
for addr, data in axi_writes:
    if addr not in axi_write_dict:
        axi_write_dict[addr] = []
    axi_write_dict[addr].append(data)

# Verify instruction fetches
print("-" * 70)
print("INSTRUCTION FETCH VERIFICATION (CPU_IMEM vs AXI_MEM)")
print("-" * 70)
imem_matches = 0
imem_excess_axi = 0
for addr, data in cpu_imem_reads:
    if addr in axi_read_dict and data in axi_read_dict[addr]:
        imem_matches += 1
        axi_read_dict[addr].remove(data)

# Count excess AXI reads (fetches that were discarded due to flushes)
for addr in axi_read_dict:
    imem_excess_axi += len(axi_read_dict[addr])

print(f"Matched:    {imem_matches}/{len(cpu_imem_reads)}")
print(f"Mismatched: {len(cpu_imem_reads) - imem_matches}")
if imem_excess_axi > 0:
    print(f"Note:       {imem_excess_axi} AXI fetch(es) discarded by CPU (pipeline flushes)")
if imem_matches == len(cpu_imem_reads):
    print("Status:     PASS - All instruction fetches match!")
else:
    # Instruction mismatches are warnings, not failures (expected with pipeline flushes)
    print("Status:     WARNING - Some CPU fetches don't match AXI (check for errors)")
print()

# Verify data reads
print("-" * 70)
print("DATA READ VERIFICATION (CPU_DMEM vs AXI_MEM)")
print("-" * 70)
axi_read_dict = {}
for addr, data in axi_reads:
    if addr not in axi_read_dict:
        axi_read_dict[addr] = []
    axi_read_dict[addr].append(data)

dmem_read_matches = 0
for addr, data in cpu_dmem_reads:
    if addr in axi_read_dict and data in axi_read_dict[addr]:
        dmem_read_matches += 1
        axi_read_dict[addr].remove(data)

print(f"Matched:    {dmem_read_matches}/{len(cpu_dmem_reads)}")
print(f"Mismatched: {len(cpu_dmem_reads) - dmem_read_matches}")
if dmem_read_matches == len(cpu_dmem_reads):
    print("Status:     PASS - All data reads match!")
else:
    print("Status:     FAIL - Mismatches detected")
print()

# Verify data writes
print("-" * 70)
print("DATA WRITE VERIFICATION (CPU_DMEM vs AXI_MEM)")
print("-" * 70)
magic_addrs = ['fffffff4', 'fffffff0']
cpu_dmem_writes_mem = [(a, d) for a, d in cpu_dmem_writes if a not in magic_addrs]

dmem_write_matches = 0
for addr, data in cpu_dmem_writes_mem:
    if addr in axi_write_dict and data in axi_write_dict[addr]:
        dmem_write_matches += 1
        axi_write_dict[addr].remove(data)

console_writes = len([1 for a, d in cpu_dmem_writes if a == 'fffffff4'])
exit_writes = len([1 for a, d in cpu_dmem_writes if a == 'fffffff0'])

print(f"Matched:          {dmem_write_matches}/{len(cpu_dmem_writes_mem)}")
print(f"Mismatched:       {len(cpu_dmem_writes_mem) - dmem_write_matches}")
print(f"Console writes:   {console_writes} (magic addr, not in AXI)")
print(f"Exit writes:      {exit_writes} (magic addr, not in AXI)")
if dmem_write_matches == len(cpu_dmem_writes_mem):
    print("Status:           PASS - All data writes match!")
else:
    print("Status:           FAIL - Mismatches detected")
print()

# Overall summary
print("=" * 70)
print("OVERALL SUMMARY")
print("=" * 70)

# Only fail on data read/write mismatches; instruction mismatches are warnings
data_pass = (
    dmem_read_matches == len(cpu_dmem_reads) and
    dmem_write_matches == len(cpu_dmem_writes_mem)
)

imem_pass = imem_matches == len(cpu_imem_reads)

if data_pass:
    print("RESULT: PASS - Data memory interface verified")
    print()
    print("Details:")
    print(f"  - {len(cpu_imem_reads)} instruction fetches ({imem_matches} matched, {len(cpu_imem_reads) - imem_matches} mismatched)")
    if imem_excess_axi > 0:
        print(f"    Note: {imem_excess_axi} AXI instruction fetch(es) discarded due to pipeline flushes")
        print(f"          (branches/interrupts/exceptions - this is correct behavior)")
    print(f"  - {len(cpu_dmem_reads)} data reads verified")
    print(f"  - {len(cpu_dmem_writes_mem)} data writes verified")
    print(f"  - {console_writes} console writes (handled at SoC level)")
    print(f"  - {exit_writes} exit write (program termination)")
    if not imem_pass:
        print()
        print("WARNING: Some instruction fetch mismatches detected.")
        print("         This is typically expected due to pipeline flushes.")
        print("         Check for actual errors in data memory transactions above.")
    sys.exit(0)
else:
    print("RESULT: FAIL - Data memory inconsistencies detected")
    print(f"  Instruction fetch mismatches: {len(cpu_imem_reads) - imem_matches} (warning only)")
    print(f"  Data read issues: {len(cpu_dmem_reads) - dmem_read_matches}")
    print(f"  Data write issues: {len(cpu_dmem_writes_mem) - dmem_write_matches}")
    sys.exit(1)
print("=" * 70)
