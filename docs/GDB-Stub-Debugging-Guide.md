# GDB Stub Debugging Guide

## Overview

The RV32 simulator includes an integrated GDB stub that enables remote debugging using standard GDB (GNU Debugger) tools. This allows you to debug RISC-V programs running in the simulator as if they were running on real hardware, with full support for breakpoints, watchpoints, memory inspection, and single-stepping.

## Architecture

### GDB Remote Serial Protocol (RSP)

The GDB stub implements the GDB Remote Serial Protocol, a standard protocol that allows GDB to communicate with debugging targets over a network connection. The simulator acts as the "target" and GDB acts as the "client".

```
┌─────────────────┐                    ┌──────────────────────┐
│   GDB Client    │  <--- Network ---> │  RV32 Simulator      │
│   (localhost)   │   (TCP Port 3333)  │  (GDB Stub Server)   │
└─────────────────┘                    └──────────────────────┘
```

### GDB Stub Components

#### 1. **gdb_stub.h** - Interface Definition
Defines the public API and data structures:
- `gdb_context_t`: Main GDB context structure
- `breakpoint_t`: Breakpoint management
- `watchpoint_t`: Watchpoint management with type support
- `gdb_callbacks_t`: Callback functions for simulator integration

#### 2. **gdb_stub.c** - Protocol Implementation
Implements the GDB RSP protocol:
- Packet parsing and encoding
- Command handlers for all GDB commands
- Breakpoint and watchpoint management
- TCP socket communication

#### 3. **rv32sim.cpp** - Simulator Integration
Integrates GDB stub into the RV32 simulator:
- Callback functions connecting GDB to simulator state
- Breakpoint/watchpoint checking during execution
- Single-step support
- Memory and register access through GDB

## Supported GDB Commands

The GDB stub implements the following remote protocol commands:

### Execution Control Commands

| Command | Format | Description |
|---------|--------|-------------|
| Continue | `c` | Resume execution |
| Step | `s` | Single-step one instruction |
| Step with Address | `s[addr]` | Single-step from specific address |
| Continue with Address | `c[addr]` | Continue from specific address |
| Kill | `k` | Terminate the program |

### Register Commands

| Command | Format | Description |
|---------|--------|-------------|
| Read All Registers | `g` | Read all 32 RISC-V registers + PC |
| Write All Registers | `G[data]` | Write all 32 RISC-V registers + PC |
| Read Single Register | `p[reg]` | Read specific register (0-32, where 32=PC) |
| Write Single Register | `P[reg]=[value]` | Write to specific register |

### Memory Commands

| Command | Format | Description |
|---------|--------|-----------|
| Read Memory | `m[addr],[length]` | Read memory (hex address/length) |
| Write Memory (Hex) | `M[addr],[length]:[data]` | Write memory data (hex-encoded) |
| Write Memory (Binary) | `X[addr],[length]:[data]` | Write binary data (more efficient) |
| Search Memory | `qSearch:memory:[addr]:[length]:[pattern]` | Search for hex pattern in memory |

### Breakpoint/Watchpoint Commands

| Command | Format | Description |
|---------|--------|-------------|
| Insert Breakpoint | `Z0,[addr],1` | Set breakpoint at address |
| Remove Breakpoint | `z0,[addr],1` | Clear breakpoint at address |
| Insert Write Watchpoint | `Z2,[addr],[len]` | Watch memory writes |
| Remove Write Watchpoint | `z2,[addr],[len]` | Remove write watchpoint |
| Insert Read Watchpoint | `Z3,[addr],[len]` | Watch memory reads |
| Remove Read Watchpoint | `z3,[addr],[len]` | Remove read watchpoint |
| Insert Access Watchpoint | `Z4,[addr],[len]` | Watch any memory access |
| Remove Access Watchpoint | `z4,[addr],[len]` | Remove access watchpoint |

### Status Commands

| Command | Format | Description |
|---------|--------|-------------|
| Get Status | `?` | Enhanced stop reason (breakpoint/watchpoint/signal) |
| Query Support | `qSupported` | Feature negotiation |
| Query Attached | `qAttached` | Check if attached to process |
| Read Thread Info | `qfThreadInfo` | Get thread list (returns single thread) |
| Continue Thread Info | `qsThreadInfo` | Continue thread enumeration |
| Current Thread | `qC` | Get current thread ID |
| Section Offsets | `qOffsets` | Get section load addresses |
| Trace Status | `qTStatus` | Get trace status information |
| XML Target Info | `qXfer:features:read:target.xml` | Get target description |

### Thread Commands

| Command | Format | Description |
|---------|--------|-----------|
| Set Thread | `H[g|c][thread-id]` | Set thread for subsequent operations |
| Thread Alive | `T[thread-id]` | Check if thread is alive |

### Program Control

| Command | Format | Description |
|---------|--------|-----------|
| Detach | `D` | Detach debugger from target |
| Reset | `R` | Reset the simulator (clear registers/breakpoints) |
| Interrupt | `Ctrl+C` | Stop execution (send SIGINT) |

## Integration with Simulator

### Initialization

To enable GDB debugging in the simulator, use the `--gdb` and optional `--gdb-port` options:

```bash
./build/rv32sim --gdb --gdb-port=3333 program.elf
```

### Callback Functions

The simulator provides these callback functions to allow GDB to access simulator state:

```c
typedef struct {
    uint32_t (*read_reg)(void *sim, int reg_num);      // Read RISC-V register
    void (*write_reg)(void *sim, int reg_num, uint32_t value);  // Write RISC-V register
    uint32_t (*read_mem)(void *sim, uint32_t addr, int size);   // Read memory
    void (*write_mem)(void *sim, uint32_t addr, uint32_t value, int size); // Write memory
    uint32_t (*get_pc)(void *sim);                      // Get program counter
    void (*set_pc)(void *sim, uint32_t pc);            // Set program counter
    void (*single_step)(void *sim);                    // Execute one instruction
    bool (*is_running)(void *sim);                     // Check if running
    void (*reset)(void *sim);                          // Optional: reset simulator state
} gdb_callbacks_t;
```

### Breakpoint/Watchpoint Handling

During execution, the simulator checks for breakpoints and watchpoints:

```cpp
// Check breakpoint at current PC
if (gdb_enabled && gdb_ctx) {
    if (gdb_stub_check_breakpoint((gdb_context_t*)gdb_ctx, pc)) {
        // Stop execution and notify GDB
        break;
    }
}

// Check watchpoints on memory access
if (gdb_enabled && gdb_ctx && addr != pc) {
    if (gdb_stub_check_watchpoint_write((gdb_context_t*)gdb_ctx, addr, size)) {
        // Stop execution on watchpoint hit
        break;
    }
}
```

## Debugging Steps

### Step 1: Start the Simulator with GDB Enabled

```bash
make build-sim
./build/rv32sim --gdb --gdb-port=3333 sw/simple/simple.elf &
```

The simulator will output:
```
GDB: enabled on port 3333
Waiting for GDB connection...
```

### Step 2: Connect GDB Client

In another terminal, start GDB:

```bash
riscv64-unknown-elf-gdb sw/simple/simple.elf
```

In GDB, connect to the simulator:

```gdb
(gdb) target remote localhost:3333
Remote debugging using localhost:3333
Reading symbols from /path/to/program.elf...
(gdb)
```

### Step 3: Set Breakpoints

Set a breakpoint at main or any function:

```gdb
(gdb) break main
Breakpoint 1 at 0x80000000: file sw/simple/simple.c, line 5.

(gdb) break *0x80000100
Breakpoint 2 at 0x80000100

(gdb) info breakpoints
Num     Type           Disp Enb Address    What
1       breakpoint     keep y   0x80000000 main at sw/simple/simple.c:5
2       breakpoint     keep y   0x80000100 <code>
```

### Step 4: Run the Program

Continue execution until the first breakpoint:

```gdb
(gdb) continue
Breakpoint 1, main () at sw/simple/simple.c:5
5       int main() {
```

Or use `run` to start from the beginning:

```gdb
(gdb) run
Starting program: /path/to/program.elf
Breakpoint 1, main () at sw/simple/simple.c:5
5       int main() {
```

### Step 5: Inspect State

#### View Registers

```gdb
(gdb) info registers
ra             0x80000004          2147483652
sp             0x80200000          0x80200000
gp             0x80001000          2147517440
tp             0x0                 0
t0             0x0                 0
...
(gdb) print $sp
$1 = (void *) 0x80200000

(gdb) print/x $a0
$2 = 0x42
```

#### Read Memory

```gdb
(gdb) x/4x 0x80000000
0x80000000:     0x00001197  0xe6018193  0x30047073  0x00200117

(gdb) x/10i 0x80000000
   0x80000000:  auipc   gp,0x1
   0x80000004:  addi    gp,gp,-416
   0x80000008:  csrrci  zero,mstatus,8
   0x8000000c:  auipc   sp,0x200
   0x80000010:  addi    sp,sp,-12
   ...
```

#### View Variables

```gdb
(gdb) print variable_name
(gdb) print *(int*)0x80200000
$3 = 42
```

### Step 6: Single-Step Through Code

Execute one instruction at a time:

```gdb
(gdb) stepi
0x80000004 in main () at sw/simple/simple.c:6
6           printf("Hello, World!\n");

(gdb) stepi 5      # Step 5 instructions
```

Or step through source code lines:

```gdb
(gdb) step         # Step into function
(gdb) next         # Step over function call
(gdb) finish       # Run until function returns
```

### Step 7: Set Watchpoints

Watch memory locations for changes:

```gdb
(gdb) watch *0x80200000
Hardware watchpoint 1: *0x80200000

(gdb) watch variable_name
Hardware watchpoint 2: variable_name

(gdb) rwatch *0x80200000
Hardware watchpoint 3: *0x80200000 (read)

(gdb) awatch *0x80200000
Hardware watchpoint 4: *0x80200000 (read/write)

(gdb) info watchpoints
Num     Type           Disp Enb Address    What
1       hw watchpoint  keep y              *0x80200000
2       hw watchpoint  keep y              variable_name
```

When a watchpoint is hit:

```gdb
Hardware watchpoint 1: *0x80200000
Old value = 0x0
New value = 0x42
0x80000050 in function_name () from /path/to/program.elf
```

### Step 8: Conditional Breakpoints

Break only when a condition is met:

```gdb
(gdb) break main if x > 10
(gdb) break *0x80000100 if $a0 == 42
```

### Step 9: Enhanced Debugging Features

#### Individual Register Access

Read/write specific registers more efficiently:

```gdb
(gdb) print $x1          # Read register x1
(gdb) set $x1 = 0x1234   # Write to register x1
(gdb) print $pc          # Read program counter
(gdb) set $pc = 0x80000100  # Set program counter
```

#### Memory Pattern Search

Search for specific patterns in memory:

```gdb
(gdb) find 0x80000000, 0x80001000, 0x12, 0x34, 0x56, 0x78
Pattern found at 0x80000450
```

#### Reset Target

Reset the simulator without disconnecting:

```gdb
(gdb) monitor reset
# Or use the R command directly through the protocol
```

#### Enhanced Stop Reasons

The stub now provides detailed stop information:
- Breakpoint hits show breakpoint details
- Watchpoint hits include the watched address
- Signal information is more descriptive

### Step 10: Continue and Quit

Resume execution:

```gdb
(gdb) continue       # Run until next breakpoint
```

Exit debugging:

```gdb
(gdb) quit
```

## Example Debugging Session

```bash
# Terminal 1: Start simulator with GDB
$ ./build/rv32sim --gdb --gdb-port=3333 sw/simple/simple.elf
GDB: enabled on port 3333
Waiting for GDB connection...
```

```bash
# Terminal 2: Start GDB
$ riscv64-unknown-elf-gdb sw/simple/simple.elf
(gdb) target remote localhost:3333
(gdb) break main
(gdb) run
Breakpoint 1, main () at sw/simple/simple.c:5
5       int main() {
(gdb) info registers
(gdb) x/10i $pc
(gdb) stepi
(gdb) continue
(gdb) quit
```

## Eclipse Debugger Integration

Eclipse CDT (C/C++ Development Tooling) provides a graphical interface for remote debugging with GDB. This section explains how to configure Eclipse to debug RISC-V programs running in the simulator.

### Prerequisites

1. **Eclipse CDT** - Install Eclipse with C/C++ Development Tooling plugin
2. **RISC-V Toolchain** - Ensure `riscv64-unknown-elf-gdb` is installed and in PATH
3. **Build Project** - Import the kcore project into Eclipse or use existing Eclipse project

### Step 1: Create/Open Eclipse Project

Open Eclipse and create a new C/C++ project or import the existing kcore project:

```
File → New → Project → C/C++ → C/C++ Project
(or import existing project)
```

Ensure the project is configured with RISC-V toolchain:

```
Project → Properties → C/C++ Build → Tool Chain Editor
Select: RISC-V toolchain
```

### Step 2: Build the Project

Build your RISC-V program in Eclipse:

```
Project → Build Project (Ctrl+B)
```

The executable should be generated (e.g., `simple.elf`)

### Step 3: Create Debug Configuration

Create a new debug configuration for remote debugging:

```
Run → Debug Configurations...
```

Right-click on "GDB Hardware Debugging" and select "New":

**Main Tab:**
- Project: Select your project
- C/C++ Application: Browse to your ELF file (e.g., `build/simple.elf`)
- Build configuration: Select appropriate build type

**Debugger Tab:**
- GDB debugger: `riscv64-unknown-elf-gdb` (or path to your GDB)
- GDB command file: (leave empty or specify if needed)

**Connection Tab:**
- Connection type: TCP
- Hostname/IP address: `localhost`
- Port number: `3333`
- Timeout (seconds): `30`

**Common Options Tab:**
- Run commands: Leave default or add initialization commands

**Example GDB initialization commands:**
```
set remote hardware-watchpoint-limit 4
set remote hardware-breakpoint-limit 6
define hook-quit
    if connected
        disconnect
    end
end
```

Click "Debug" to save and start debugging.

### Step 4: Start Simulator with GDB

Open a terminal and start the simulator with GDB enabled:

```bash
./build/rv32sim --gdb --gdb-port=3333 sw/simple/simple.elf &
```

The simulator will wait for GDB connection:
```
GDB: enabled on port 3333
Waiting for GDB connection...
```

### Step 5: Connect Eclipse Debugger

In Eclipse, the debugger should automatically connect to the simulator. You should see:

1. **Debug Perspective** opens automatically
2. **Breakpoints** view shows available breakpoints
3. **Debug** view shows the current execution state
4. **Variables** view shows local variables and registers
5. **Disassembly** view shows the current instruction

### Step 6: Set Breakpoints in Eclipse

Set breakpoints by clicking in the left margin of the editor:

1. Open source file in editor
2. Click left margin next to line number to create breakpoint
3. Right-click breakpoint to access options:
   - **Conditional Breakpoint**: Add condition (e.g., `x > 10`)
   - **Enable/Disable**: Toggle breakpoint state
   - **Properties**: Configure breakpoint behavior

### Step 7: Control Execution

Use Eclipse Debug toolbar or keyboard shortcuts:

| Action | Button | Shortcut |
|--------|--------|----------|
| Resume | ▶ | F8 |
| Suspend | ⏸ | - |
| Terminate | ⏹ | Ctrl+Alt+W |
| Step Into | ↓ | F5 |
| Step Over | → | F6 |
| Step Return | ↑ | F7 |
| Step to Line | - | Ctrl+Alt+B |

### Step 8: Inspect Program State

Eclipse provides several views to inspect program state:

#### Variables View
Shows local variables and their current values:
- Automatically updates after each step
- Right-click to "Watch" selected variable
- Expandable for structs and arrays

#### Registers View
Shows RISC-V register values:

```
View → Show View → Other → Debug → Registers
```

Displays all 32 registers with current values in decimal/hex.

#### Memory View
Inspect memory contents:

```
View → Show View → Other → Debug → Memory
```

- Add memory monitors for specific addresses
- View memory as bytes, words, or formatted data

#### Expressions View
Evaluate C expressions at runtime:

```
View → Show View → Other → Debug → Expressions
```

Add expressions like:
- `*(int*)0x80200000` - Read integer at address
- `variable_name` - Evaluate variable
- `$sp + 0x100` - Evaluate register expressions

#### Disassembly View
Show assembly instructions:

```
View → Show View → Other → Debug → Disassembly
```

### Step 9: Set Watchpoints in Eclipse

Set watchpoints on variables or memory locations:

1. **Right-click variable** in Variables view → "Watch"
2. Or in editor: **Ctrl+Shift+B** to create watchpoint at cursor
3. Configure watchpoint type:
   - Read: Stop on memory read
   - Write: Stop on memory write
   - Read/Write: Stop on any access

### Step 10: View Call Stack

The Debug view shows the call stack:

```
Debug View → Stack Frame list
```

Click on any stack frame to see:
- Source code location
- Local variables at that level
- Register values

### Eclipse Debug Workflow Example

```
1. Set breakpoint at main() by clicking left margin
2. Click "Debug" button to start remote debugging
3. Debugger connects and pauses at breakpoint
4. Inspect variables in Variables view
5. Step into function (F5)
6. View registers in Registers view
7. Right-click variable to add watch expression
8. Continue to next breakpoint (F8)
9. Examine memory in Memory view
10. Terminate when done
```

### Advanced Eclipse Features

#### Conditional Breakpoints

Right-click breakpoint → Properties:

```
Condition: x > 100
Suspend when true (default)
```

#### Tracepoints

Right-click breakpoint → Convert to Tracepoint:
- Logs value without stopping
- Useful for high-frequency breakpoints

#### Skip All Breakpoints

Debug toolbar → Skip All Breakpoints (Ctrl+Alt+K)
- Temporarily disable all breakpoints
- Useful for performance testing

#### Debug Filtering

Filter which threads/stack frames to show:

```
Window → Preferences → Debug → Detail Formatters
```

#### Remote Debugging with SSH

For remote simulator (not localhost):

Debug Configuration → Debugger → Connection Tab:
- Hostname/IP: `your.remote.host`
- Port: `3333` (if simulator is listening on that port)

Or use SSH tunneling:

```bash
ssh -L 3333:localhost:3333 remote_host
# Then connect to localhost:3333 in Eclipse
```

### Troubleshooting Eclipse Debugging

#### Cannot Connect to Remote Target

**Problem**: "Connection refused" error
- Check simulator is running with `--gdb` flag
- Verify port number matches (3333)
- Check firewall settings

**Solution**:
```bash
# Check if simulator is running
ps aux | grep rv32sim

# Check port is listening
lsof -i :3333

# Verify GDB path
which riscv64-unknown-elf-gdb
```

#### Breakpoints Not Highlighting

**Problem**: Breakpoints don't show in editor margin
- Ensure source files match the ELF file being debugged
- Check project build paths match source paths
- Rebuild project with debug symbols (`-g` flag)

#### Variables Not Showing

**Problem**: Variables view is empty
- Ensure program is paused at breakpoint
- Check debug symbols are included in ELF
- Verify variables are in scope at current location

#### Eclipse Unresponsive During Debugging

**Problem**: Eclipse freezes when stepping
- Increase GDB timeout in Debug Configuration
- Check system resources (CPU, memory)
- Try limiting watchpoint count

### Eclipse Tips and Tricks

#### Quick Variable Watch

1. Pause execution
2. Highlight variable name in editor
3. Right-click → "Display as → ..."
4. Select format (hex, decimal, binary, etc.)

#### Display at Cursor

```
Window → Show View → Display
```

Type expressions and press Ctrl+U to evaluate:
```
*(int*)0x80200000
$sp + 100
variable_name * 2
```

#### Save Debug Session

```
File → Save As → Save Debug Session
```

Useful for complex debugging scenarios.

#### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Debug Last Launched | F11 |
| Step Into | F5 |
| Step Over | F6 |
| Step Return | F7 |
| Resume | F8 |
| Terminate | Ctrl+Alt+W |
| Conditional Breakpoint | Shift+Ctrl+B |

## Advanced Debugging Techniques

### Debugging with Core Dump

Save simulator state:

```gdb
(gdb) set logging on
(gdb) set logging file debug.log
(gdb) info all-registers
(gdb) dump memory memory.bin 0x80000000 0x80200000
```

### Debugging Loops

```gdb
(gdb) break loop_function if counter > 100
(gdb) continue          # Skip to iteration 100
```

### Debugging Memory Corruption

```gdb
(gdb) awatch global_buffer
(gdb) continue          # Stop on any access
```

### Using GDB Scripts

Create `debug.gdb`:

```
target remote localhost:3333
break main
break *0x80000100
run
info registers
x/10i $pc
continue
quit
```

Run with:

```bash
riscv64-unknown-elf-gdb -x debug.gdb -batch sw/simple/simple.elf
```

## Troubleshooting

### Connection Issues

**Problem**: "Cannot connect to remote target"
- Ensure simulator is running with `--gdb` flag
- Check port number matches in both simulator and GDB
- Verify port is not in use: `lsof -i :3333`

**Solution**:
```bash
# Kill process on port
lsof -i :3333 | awk 'NR!=1 {print $2}' | xargs kill -9

# Restart simulator
./build/rv32sim --gdb --gdb-port=3333 program.elf
```

### Breakpoint Not Hit

**Problem**: Breakpoint set but not triggered
- Verify address is correct: `info breakpoints`
- Check if code execution reaches that address
- Ensure breakpoint is enabled: `enable breakpoint_number`

### Watchpoint Issues

**Problem**: Watchpoint not catching memory changes
- Verify address and size are correct
- Check if access is through the expected path
- Try simpler watchpoint first: `watch *(int*)0x80200000`

## Performance Considerations

- GDB debugging adds overhead due to breakpoint checking
- For performance testing, disable GDB: `--no-gdb`
- Use breakpoints strategically to minimize performance impact
- Watchpoints have more overhead than breakpoints

## Recent Enhancements

The GDB stub has been enhanced with several new features:

### Individual Register Access
- **Single register read (`p`)**: More efficient than reading all 33 registers
- **Single register write (`P`)**: Allows precise register modification
- **Support for PC register**: Access program counter as register 32

### Memory Operations
- **Binary memory write (`X`)**: More efficient for large memory transfers
- **Memory pattern search**: Find specific byte patterns in memory ranges
- **Enhanced memory access**: Better error handling and validation

### Target Control
- **Reset command (`R`)**: Reset processor state without disconnecting
- **Thread simulation**: Basic thread commands for single-threaded debugging
- **Enhanced stop reporting**: Detailed information about breakpoint/watchpoint hits

### Protocol Extensions
- **Section offsets (`qOffsets`)**: Support for relocated code
- **Trace status (`qTStatus`)**: Trace debugging information
- **Extended queries**: Better GDB feature negotiation

### Improved Integration
- **Optional reset callback**: Simulator-specific reset handling
- **Enhanced state tracking**: Better breakpoint and watchpoint state management
- **Detailed stop reasons**: Differentiate between breakpoints, watchpoints, and signals

## Limitations

- Single-threaded debugging only (thread commands supported but simulate single thread)
- No multi-core debugging support
- Watchpoints limited to 32 per execution
- Breakpoints limited to 64 per execution
- No coprocessor debugging support
- Binary memory transfer (`X` command) currently uses hex encoding for simplicity
- Memory search is implemented with linear search (may be slow for large ranges)

## References

- [GDB Remote Serial Protocol Documentation](https://sourceware.org/gdb/onlinedocs/gdb/Remote-Protocol.html)
- [RISC-V Specification](https://riscv.org/)
- [GDB Manual](https://sourceware.org/gdb/documentation/)

