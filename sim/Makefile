# Makefile for RV32IMAC Software Simulator
# Builds rv32_sim with GDB stub support

# Load environment configuration
-include ../env.config

# Directories
BUILD_DIR = ../build

# Compiler settings
CC = gcc
CXX = g++
CFLAGS = -std=c11 -O2 -Wall
CXXFLAGS = -std=c++14 -O2 -Wall

# Source files
SOURCES = rv32_sim.cpp gdb_stub.c
HEADERS = rv32_sim.h gdb_stub.h
OBJECTS = $(BUILD_DIR)/rv32_sim.o $(BUILD_DIR)/gdb_stub.o

# Target binary
TARGET = $(BUILD_DIR)/rv32_sim

# ============================================================================
# Build targets
# ============================================================================

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJECTS) | $(BUILD_DIR)
	@echo "Linking $(TARGET)..."
	$(CXX) $(CXXFLAGS) -o $@ $(OBJECTS)
	@echo "Build complete: $(TARGET)"

$(BUILD_DIR)/rv32_sim.o: rv32_sim.cpp rv32_sim.h gdb_stub.h | $(BUILD_DIR)
	@echo "Compiling rv32_sim.cpp..."
	$(CXX) $(CXXFLAGS) -c -o $@ rv32_sim.cpp

$(BUILD_DIR)/gdb_stub.o: gdb_stub.c gdb_stub.h | $(BUILD_DIR)
	@echo "Compiling gdb_stub.c..."
	$(CC) $(CFLAGS) -c -o $@ gdb_stub.c

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

clean:
	@echo "Cleaning simulator build artifacts..."
	@rm -f $(OBJECTS) $(TARGET)
	@echo "Clean complete"

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help:
	@echo "RV32IMAC Software Simulator Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build rv32_sim simulator (default)"
	@echo "  clean   - Remove build artifacts"
	@echo "  help    - Show this help message"
	@echo ""
	@echo "Output:"
	@echo "  $(TARGET)"
