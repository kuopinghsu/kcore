# NuttShell (NSH) Sample

This sample provides the NuttShell command-line interface for NuttX on kcore.

## Features

- Interactive command shell
- File system operations
- Process management
- System information commands
- Built-in commands for testing

## Building

From the kcore project root:

```bash
make nuttx-nsh
```

## Running

In RTL simulation:

```bash
make nuttx-rtl-nsh
```

In C++ simulation:

```bash
make nuttx-sim-nsh
```

## Available Commands

Once NSH starts, you can use commands like:

- `help` - Show available commands
- `ls` - List directory contents
- `free` - Show memory usage
- `ps` - Show processes
- `uname` - Show system information
- `date` - Show/set date and time

## Example Session

```
NuttShell (NSH) NuttX-12.0.0
nsh> uname -a
NuttX 12.0.0 kcore-board
nsh> free
             total       used       free    largest
Mem:         65536       4096      61440      61440
nsh> help
...
```
