#!/bin/bash
# Script to check ASAP7 PDK library availability and unzip if necessary

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# PDK directory
PDK_DIR="pdk/asap7/asap7sc7p5t_27/LIB/NLDM"

# Required library files (based on config.tcl)
REQUIRED_LIBS=(
    "asap7sc7p5t_SIMPLE_RVT_TT_nldm_201020.lib"
    "asap7sc7p5t_SEQ_RVT_TT_nldm_201020.lib"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ASAP7 PDK Library Checker${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if PDK directory exists
if [ ! -d "$PDK_DIR" ]; then
    echo -e "${RED}ERROR: PDK directory not found: $PDK_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} PDK directory found: $PDK_DIR"
echo ""

# Check each required library
all_available=true
files_to_unzip=()

for lib_file in "${REQUIRED_LIBS[@]}"; do
    lib_path="$PDK_DIR/$lib_file"
    compressed_path="$PDK_DIR/${lib_file}.7z"
    
    if [ -f "$lib_path" ]; then
        # File exists, check size
        size=$(du -h "$lib_path" | cut -f1)
        echo -e "${GREEN}✓${NC} $lib_file (${size})"
    elif [ -f "$compressed_path" ]; then
        # Compressed version exists
        echo -e "${YELLOW}⚠${NC} $lib_file - compressed version found, needs extraction"
        files_to_unzip+=("$compressed_path")
        all_available=false
    else
        # Neither exists
        echo -e "${RED}✗${NC} $lib_file - NOT FOUND (neither .lib nor .7z)"
        all_available=false
    fi
done

echo ""

# If files need to be unzipped
if [ ${#files_to_unzip[@]} -gt 0 ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Files need to be extracted${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    
    # Check if 7z is available
    if ! command -v 7z &> /dev/null && ! command -v 7za &> /dev/null; then
        echo -e "${RED}ERROR: 7z/7za command not found${NC}"
        echo "Please install p7zip:"
        echo "  - Ubuntu/Debian: sudo apt-get install p7zip-full"
        echo "  - RHEL/CentOS: sudo yum install p7zip p7zip-plugins"
        echo "  - macOS: brew install p7zip"
        exit 1
    fi
    
    # Determine which 7z command to use
    if command -v 7z &> /dev/null; then
        ZIP_CMD="7z"
    else
        ZIP_CMD="7za"
    fi
    
    # Extract files
    for compressed_file in "${files_to_unzip[@]}"; do
        echo -e "${BLUE}Extracting:${NC} $(basename $compressed_file)"
        cd "$PDK_DIR"
        $ZIP_CMD x -y "$(basename $compressed_file)" > /dev/null 2>&1
        cd - > /dev/null
        
        # Verify extraction
        extracted_file="${compressed_file%.7z}"
        if [ -f "$extracted_file" ]; then
            size=$(du -h "$extracted_file" | cut -f1)
            echo -e "${GREEN}✓${NC} Successfully extracted: $(basename $extracted_file) (${size})"
        else
            echo -e "${RED}✗${NC} Failed to extract: $(basename $compressed_file)"
            exit 1
        fi
    done
    
    echo ""
    all_available=true
fi

# Final status
echo -e "${BLUE}========================================${NC}"
if [ "$all_available" = true ]; then
    echo -e "${GREEN}✓ All required PDK libraries are available${NC}"
    echo -e "${BLUE}========================================${NC}"
    exit 0
else
    echo -e "${RED}✗ Some PDK libraries are missing${NC}"
    echo -e "${BLUE}========================================${NC}"
    exit 1
fi
