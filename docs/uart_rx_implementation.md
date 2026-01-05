# UART RX Implementation

**Date**: January 3, 2026  
**Status**: ✅ Complete and Tested

## Overview

Added full-duplex receive (RX) functionality to the UART peripheral, complementing the existing transmit (TX) implementation. The UART now supports bidirectional communication at 12.5 Mbaud with 16-entry FIFOs for both TX and RX paths.

## Implementation Details

### RX State Machine

Located in `rtl/uart.sv`, the RX path uses a 4-state FSM:

```systemverilog
typedef enum logic [1:0] {
    RX_IDLE  = 2'b00,  // Waiting for start bit
    RX_START = 2'b01,  // Start bit detected
    RX_DATA  = 2'b10,  // Receiving data bits
    RX_STOP  = 2'b11   // Stop bit
} rx_state_t;
```

**State Transitions**:
- **RX_IDLE → RX_START**: When start bit (0) detected on synchronized uart_rx
- **RX_START → RX_DATA**: After waiting for bit-center alignment
- **RX_DATA → RX_STOP**: After receiving 8 data bits
- **RX_STOP → RX_IDLE**: After stop bit (1) received, data written to FIFO

### Input Synchronizer

To handle asynchronous input from uart_rx pin:

```systemverilog
logic uart_rx_sync1, uart_rx_sync2;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        uart_rx_sync1 <= 1'b1;
        uart_rx_sync2 <= 1'b1;
    end else begin
        uart_rx_sync1 <= uart_rx;
        uart_rx_sync2 <= uart_rx_sync1;
    end
end
```

This 2-stage synchronizer prevents metastability issues when crossing clock domains.

### Separate RX Baud Counter

Critical design decision: RX uses its own baud counter, independent from TX:

```systemverilog
// Reset RX baud counter to half-period on start bit detection
if (rx_state == RX_IDLE && uart_rx_sync2 == 1'b0) begin
    rx_baud_counter <= (BAUD_DIV / 2);  // Start at bit center
    rx_baud_tick <= 1'b0;
end else if (rx_baud_counter == (BAUD_DIV - 1)) begin
    rx_baud_counter <= '0;
    rx_baud_tick <= 1'b1;
end else begin
    rx_baud_counter <= rx_baud_counter + 1;
    rx_baud_tick <= 1'b0;
end
```

**Why Separate Counter?**
- TX baud counter free-runs continuously
- RX needs to synchronize to incoming start bit
- Resetting to BAUD_DIV/2 ensures sampling at bit center
- Independent counters allow reliable full-duplex operation

### RX FIFO

16-entry FIFO buffer with overflow protection:

```systemverilog
logic [7:0] rx_fifo [16];
logic [3:0] rx_fifo_wr_ptr, rx_fifo_rd_ptr;
logic [4:0] rx_fifo_count;  // 5 bits to represent 0-16

// Write on RX_STOP state
if (rx_state == RX_STOP && rx_baud_tick) begin
    if (rx_fifo_count < 16) begin
        rx_fifo[rx_fifo_wr_ptr] <= rx_shift_reg;
        rx_fifo_wr_ptr <= rx_fifo_wr_ptr + 1;
        rx_fifo_count <= rx_fifo_count + 1;
    end else begin
        rx_overrun <= 1'b1;  // Set overrun flag
    end
end

// Read when AXI read from address 0x00
if (axi_rvalid && axi_rready) begin
    if (rx_fifo_count > 0) begin
        rx_fifo_rd_ptr <= rx_fifo_rd_ptr + 1;
        rx_fifo_count <= rx_fifo_count - 1;
    end
end
```

### Status Register (0x04)

Enhanced with RX status bits:

- **Bit[0]**: TX busy (1 = transmitting)
- **Bit[1]**: TX FIFO full (1 = cannot write)
- **Bit[2]**: RX ready (1 = data available in FIFO)
- **Bit[3]**: RX overrun (1 = FIFO overflow, data lost)

```systemverilog
assign status_reg = {28'h0, rx_overrun, (rx_fifo_count > 0), tx_fifo_full, tx_busy};
```

## Baud Rate Configuration

### Initial Problem (BAUD_DIV=2, 25 Mbaud)

Initial implementation used 25 Mbaud (2 cycles per bit):
- **Issue**: Data corruption - received 0xa0, 0x34, 0xf0 instead of 'A', 'B', 'C'
- **Root Cause**: Only 2 clock cycles insufficient for:
  - 2-stage synchronizer (2 cycles)
  - Sampling and processing logic
  - Timing margin for reliable detection

### Solution (BAUD_DIV=4, 12.5 Mbaud)

Changed to 12.5 Mbaud (4 cycles per bit):
- **CLK_FREQ**: 50 MHz
- **BAUD_RATE**: 12,500,000 (12.5 Mbaud)
- **BAUD_DIV**: CLK_FREQ / BAUD_RATE = 50,000,000 / 12,500,000 = 4

> **⚠️ IMPORTANT LIMITATION**: 
> **Minimum BAUD_DIV = 4** (Maximum baud rate = CLK_FREQ / 4)
> 
> The RX path requires at least 4 clock cycles per bit for reliable operation:
> - 2 cycles for input synchronizer (metastability protection)
> - 1 cycle for bit-center sampling
> - 1 cycle timing margin for state machine transitions
> 
> At 50 MHz clock:
> - Minimum BAUD_DIV: 4
> - Maximum baud rate: 12.5 Mbaud
> - Lower BAUD_DIV values will cause data corruption

**Changes in RTL**:
```systemverilog
// rtl/soc_top.sv
uart #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(12_500_000)  // Changed from 25_000_000
) u_uart (
    // ...
);
```

**Changes in Testbench**:
```cpp
// testbench/tb_main.cpp
const int UART_BIT_PERIOD = 4;  // Changed from 2
```

**Result**: ✅ All characters received correctly, test passes

## Software Support

### Bare Metal Driver (sw/uart/uart.c)

Updated with RX functions:

```c
// RX polling function
int uart_getc(void) {
    if (UART_STATUS & UART_STATUS_RX_READY) {
        return (int)(UART_RX & 0xFF);
    }
    return -1;
}

// Check RX ready
int uart_rx_ready(void) {
    return (UART_STATUS & UART_STATUS_RX_READY) ? 1 : 0;
}
```

**Echo Test**:
- Waits for input with timeout
- Receives characters from testbench
- Echoes each character back
- Reports statistics (RX count, TX count)

### Zephyr UART Driver (rtos/zephyr/drivers/serial/uart_kcore.c)

Implemented poll-in function:

```c
static int uart_kcore_poll_in(const struct device *dev, unsigned char *c) {
    uint32_t status = uart_kcore_read(dev, UART_REG_STATUS);
    if (!(status & UART_STATUS_RX_READY)) {
        return -1;  // No data available
    }
    *c = (unsigned char)uart_kcore_read(dev, UART_REG_RX_DATA);
    return 0;
}
```

**uart_echo Sample**:
- Loops reading characters with `uart_poll_in()`
- Echoes back with `uart_poll_out()`
- Exits on newline or after 20 characters

## Testbench Stimulus

Added UART TX stimulus generator in `testbench/tb_main.cpp`:

```cpp
void uart_transmit() {
    static int state = 0;
    static int bit_counter = 0;
    static int delay_counter = 0;
    static uint8_t tx_data = 0;
    static const char* test_string = "ABC\n";
    static int char_index = 0;
    
    const int UART_BIT_PERIOD = 4;  // 4 cycles per bit
    
    switch (state) {
        case 0: // IDLE
            if (test_string[char_index] != '\0') {
                tx_data = test_string[char_index++];
                state = 1;  // START bit
            }
            break;
        // ... (state machine for start, data, stop bits)
    }
}
```

Called in main simulation loop to drive `uart_rx` input.

## Testing Results

### Test: sw/uart

```
[TEST 6] UART Echo Test
  Waiting for UART input...
  Will echo received characters back
  
  RX: 0x00000041 ('A')
  TX: 0x00000041 (echoed)
A  RX: 0x00000042 ('B')
  TX: 0x00000042 (echoed)
B  RX: 0x00000043 ('C')
  TX: 0x00000043 (echoed)
C  RX: 0x0000000A ('?')
  TX: 0x0000000A (echoed)

  Received 4 characters
  Result: PASS (Echo test successful)

[TEST 7] Status Monitoring
  Status checks: 1054
  TX count: 1087
  RX count: 4
  
Summary: 7/7 tests PASSED
```

### Test: Zephyr uart_echo

```
Waiting for UART input...
Will echo received characters back

RX: 0x41 ('A')
TX: 0x41 (echoed)
RX: 0x42 ('B')
TX: 0x42 (echoed)
RX: 0x43 ('C')
TX: 0x43 (echoed)
RX: 0x0a ('?')
TX: 0x0a (echoed)

Received 4 characters

UART Echo test PASSED
Exit code: 0 (0x0)
```

## Design Lessons

1. **Separate Baud Counters Essential**: TX free-runs, RX must sync to start bit
2. **Bit-Center Sampling**: Reset RX counter to BAUD_DIV/2 on start bit
3. **Adequate Timing Margin**: BAUD_DIV=4 minimum for 2-stage synchronizer + logic
4. **Maximum Baud Rate Limitation**: BAUD_DIV < 4 causes corruption; max baud = CLK_FREQ / 4
5. **Status Flags Critical**: Polling needs reliable RX_READY indication
6. **FIFO Overflow Protection**: Set overrun flag, don't corrupt existing data

## Files Modified

- **rtl/uart.sv**: Added RX state machine, FIFO, synchronizer, separate baud counter
- **rtl/soc_top.sv**: Changed BAUD_RATE parameter from 25M to 12.5M
- **testbench/tb_main.cpp**: Added uart_transmit() stimulus generator, updated UART_BIT_PERIOD
- **sw/uart/uart.c**: Added RX functions and echo test
- **rtos/zephyr/drivers/serial/uart_kcore.c**: Implemented uart_kcore_poll_in()
- **rtos/zephyr/samples/uart_echo/src/main.c**: Changed from TX-only to bidirectional echo test

## Performance Impact

- **Baud Rate**: 12.5 Mbaud (50% reduction from 25 Mbaud)
- **Logic**: +~100 lines in uart.sv (RX state machine, FIFO, synchronizer)
- **Test Time**: Minimal impact (~140K cycles for uart test, dominated by other tests)
- **Reliability**: ✅ 100% correct character reception

## Future Enhancements

Potential improvements:
- Interrupt-driven RX (currently polling only)
- Configurable FIFO depth via parameter
- Hardware flow control (RTS/CTS)
- Parity bit support
- Configurable stop bits (1 or 2)
- Break detection
- Baud rate register for runtime configuration
