#!/usr/bin/env python3
"""
Patch NuttX arch/risc-v/Kconfig to add KCORE configuration
"""
import sys

def patch_kconfig(kconfig_file):
    with open(kconfig_file, 'r') as f:
        lines = f.readlines()
    
    # Check if already patched
    for line in lines:
        if 'CONFIG_ARCH_CHIP_KCORE' in line or 'config ARCH_CHIP_KCORE' in line:
            print("Kconfig already patched")
            return True
    
    # 1. Insert KCORE config before ESP32C3_LEGACY
    insert_idx = None
    for i, line in enumerate(lines):
        if 'config ARCH_CHIP_ESP32C3_LEGACY' in line:
            insert_idx = i
            break
    
    if insert_idx:
        kcore_lines = [
            'config ARCH_CHIP_KCORE\n',
            '\tbool "KCORE"\n',
            '\tselect ARCH_RV32\n',
            '\tselect ARCH_RV_ISA_M\n',
            '\tselect ARCH_RV_ISA_A\n',
            '\t---help---\n',
            '\t\tKCORE custom RISC-V processor\n',
            '\n',
        ]
        lines[insert_idx:insert_idx] = kcore_lines
        print(f"✓ Inserted KCORE config at line {insert_idx}")
    
    # 2. Add default line after bl602
    insert_idx = None
    for i, line in enumerate(lines):
        if 'default "bl602"' in line and 'ARCH_CHIP_BL602' in line:
            insert_idx = i + 1
            break
    
    if insert_idx:
        lines[insert_idx:insert_idx] = ['\tdefault "kcore"\t\t\tif ARCH_CHIP_KCORE\n']
        print(f"✓ Inserted kcore default at line {insert_idx}")
    
    # 3. Add source statement after bl602
    insert_idx = None
    for i, line in enumerate(lines):
        if 'source "arch/risc-v/src/bl602/Kconfig"' in line:
            insert_idx = i + 4  # After endif
            break
    
    if insert_idx:
        source_lines = [
            'if ARCH_CHIP_KCORE\n',
            'source "arch/risc-v/src/kcore/Kconfig"\n',
            'endif\n',
        ]
        lines[insert_idx:insert_idx] = source_lines
        print(f"✓ Inserted kcore source at line {insert_idx}")
    
    # Write patched file
    with open(kconfig_file, 'w') as f:
        f.writelines(lines)
    
    print("✓ Kconfig patched successfully")
    return True

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: patch_kconfig.py <kconfig_file>")
        sys.exit(1)
    
    success = patch_kconfig(sys.argv[1])
    sys.exit(0 if success else 1)
