// Universal Asynchronous Receiver/Transmitter (UART)
// Full-duplex UART with TX and RX support
// Memory-mapped registers:
//   0x00: TX/RX data register (write TX, read RX)
//   0x04: Status register (read)
//        bit[0]: TX busy
//        bit[1]: TX FIFO full
//        bit[2]: RX data ready (RX FIFO not empty)
//        bit[3]: RX overrun error
//
// IMPORTANT: Minimum BAUD_DIV = 4 (Maximum baud rate = CLK_FREQ / 4)
// - RX requires 2-stage synchronizer (2 cycles) + sampling/processing (2 cycles)
// - Lower BAUD_DIV values will cause RX data corruption
// - TX can operate at higher rates, but limited by RX path for full-duplex operation

module uart #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115200
    // Note: BAUD_DIV = CLK_FREQ / BAUD_RATE must be >= 4 for reliable RX operation
    //       At 50MHz, maximum baud rate is 12.5 Mbaud (BAUD_DIV=4)
) (
    input  logic        clk,
    input  logic        rst_n,

    // AXI4-Lite Slave Interface
    input  logic [31:0] axi_awaddr,
    input  logic        axi_awvalid,
    output logic        axi_awready,
    input  logic [31:0] axi_wdata,
    input  logic [3:0]  axi_wstrb,
    input  logic        axi_wvalid,
    output logic        axi_wready,
    output logic [1:0]  axi_bresp,
    output logic        axi_bvalid,
    input  logic        axi_bready,
    input  logic [31:0] axi_araddr,
    input  logic        axi_arvalid,
    output logic        axi_arready,
    output logic [31:0] axi_ardata,
    output logic [1:0]  axi_rresp,
    output logic        axi_rvalid,
    input  logic        axi_rready,

    // UART signals
    output logic        uart_tx,
    input  logic        uart_rx
);

    // Baud rate generator
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
    logic [$clog2(BAUD_DIV)-1:0] baud_counter;
    logic baud_tick;

    // Separate RX baud counter for proper bit sampling
    logic [$clog2(BAUD_DIV)-1:0] rx_baud_counter;
    logic rx_baud_tick;

    // TX state machine
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP,
        TX_DONE
    } tx_state_t;
    tx_state_t tx_state;

    logic [7:0]  tx_data;
    logic [2:0]  tx_bit_count;
    logic        tx_busy;
    logic        tx_start;

    // RX state machine
    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;
    rx_state_t rx_state;

    logic [7:0]  rx_data;
    logic [2:0]  rx_bit_count;
    logic        rx_data_ready;
    logic        rx_overrun;

    // FIFO for TX data
    logic [7:0]  tx_fifo [16];
    logic [3:0]  tx_fifo_wr_ptr;
    logic [3:0]  tx_fifo_rd_ptr;
    logic [4:0]  tx_fifo_count;
    logic        tx_fifo_empty;
    logic        tx_fifo_full;

    assign tx_fifo_empty = (tx_fifo_count == 5'd0);
    assign tx_fifo_full = (tx_fifo_count == 5'd16);

    // FIFO for RX data
    logic [7:0]  rx_fifo [16];
    logic [3:0]  rx_fifo_wr_ptr;
    logic [3:0]  rx_fifo_rd_ptr;
    logic [4:0]  rx_fifo_count;
    logic        rx_fifo_empty;
    logic        rx_fifo_full;

    assign rx_fifo_empty = (rx_fifo_count == 5'd0);
    assign rx_fifo_full = (rx_fifo_count == 5'd16);

    // RX input synchronizer (2-stage to avoid metastability)
    // This is the critical path that limits maximum baud rate to CLK_FREQ/4
    // Synchronizer consumes 2 clock cycles for metastability protection
    logic uart_rx_sync1, uart_rx_sync2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_sync1 <= 1'b1;
            uart_rx_sync2 <= 1'b1;
        end else begin
            uart_rx_sync1 <= uart_rx;
            uart_rx_sync2 <= uart_rx_sync1;
        end
    end

    // AXI state machines
    typedef enum logic [1:0] {
        WRITE_IDLE,
        WRITE_DATA,
        WRITE_RESP
    } write_state_t;
    write_state_t write_state;

    typedef enum logic [1:0] {
        READ_IDLE,
        READ_DATA
    } read_state_t;
    read_state_t read_state;

    // Baud rate generator (for TX)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_counter == BAUD_DIV - 1) begin
                baud_counter <= '0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end

    // RX baud rate generator (synchronized to start bit)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_baud_counter <= '0;
            rx_baud_tick <= 1'b0;
        end else begin
            // Reset counter on start bit detection - start halfway through for bit center sampling
            if (rx_state == RX_IDLE && uart_rx_sync2 == 1'b0) begin
                rx_baud_counter <= (BAUD_DIV / 2);  // Start at half-bit offset
                rx_baud_tick <= 1'b0;
            end else begin
                if (rx_baud_counter == BAUD_DIV - 1) begin
                    rx_baud_counter <= '0;
                    rx_baud_tick <= 1'b1;
                end else begin
                    rx_baud_counter <= rx_baud_counter + 1'b1;
                    rx_baud_tick <= 1'b0;
                end
            end
        end
    end

    // TX FIFO management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_fifo_wr_ptr <= 4'd0;
            tx_fifo_rd_ptr <= 4'd0;
            tx_fifo_count <= 5'd0;
        end else begin
            // Write to FIFO
            if (write_state == WRITE_DATA && axi_wvalid && axi_wready &&
                axi_awaddr[7:0] == 8'h00 && !tx_fifo_full) begin
                tx_fifo[tx_fifo_wr_ptr] <= axi_wdata[7:0];
                tx_fifo_wr_ptr <= tx_fifo_wr_ptr + 4'd1;

                if (!tx_start) begin
                    tx_fifo_count <= tx_fifo_count + 5'd1;
                end
            end

            // Read from FIFO
            if (tx_start && !tx_fifo_empty) begin
                tx_fifo_rd_ptr <= tx_fifo_rd_ptr + 4'd1;

                if (!(write_state == WRITE_DATA && axi_wvalid && axi_wready &&
                      axi_awaddr[7:0] == 8'h00 && !tx_fifo_full)) begin
                    tx_fifo_count <= tx_fifo_count - 5'd1;
                end
            end
        end
    end

    // TX state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_data <= 8'd0;
            tx_bit_count <= 3'd0;
            tx_busy <= 1'b0;
            tx_start <= 1'b0;
            uart_tx <= 1'b1;
        end else begin
            tx_start <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    tx_busy <= 1'b0;

                    if (!tx_fifo_empty) begin
                        tx_data <= tx_fifo[tx_fifo_rd_ptr];
                        tx_start <= 1'b1;
                        tx_busy <= 1'b1;
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    if (baud_tick) begin
                        uart_tx <= 1'b0;  // Start bit
                        tx_bit_count <= 3'd0;
                        tx_state <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    if (baud_tick) begin
                        uart_tx <= tx_data[tx_bit_count];

                        if (tx_bit_count == 3'd7) begin
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit_count <= tx_bit_count + 3'd1;
                        end
                    end
                end

                TX_STOP: begin
                    if (baud_tick) begin
                        uart_tx <= 1'b1;  // Stop bit
                        tx_state <= TX_DONE;
                    end
                end

                TX_DONE: begin
                    if (baud_tick) begin
                        tx_state <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // RX FIFO management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_fifo_wr_ptr <= 4'd0;
            rx_fifo_rd_ptr <= 4'd0;
            rx_fifo_count <= 5'd0;
            rx_overrun <= 1'b0;
        end else begin
            // Write to FIFO (from RX state machine)
            if (rx_data_ready && !rx_fifo_full) begin
                rx_fifo[rx_fifo_wr_ptr] <= rx_data;
                rx_fifo_wr_ptr <= rx_fifo_wr_ptr + 4'd1;

                if (!(read_state == READ_DATA && axi_rvalid && axi_rready &&
                      axi_araddr[7:0] == 8'h00 && !rx_fifo_empty)) begin
                    rx_fifo_count <= rx_fifo_count + 5'd1;
                end
            end else if (rx_data_ready && rx_fifo_full) begin
                // Overrun error
                rx_overrun <= 1'b1;
            end

            // Read from FIFO (from AXI)
            if (read_state == READ_DATA && axi_rvalid && axi_rready &&
                axi_araddr[7:0] == 8'h00 && !rx_fifo_empty) begin
                rx_fifo_rd_ptr <= rx_fifo_rd_ptr + 4'd1;

                if (!(rx_data_ready && !rx_fifo_full)) begin
                    rx_fifo_count <= rx_fifo_count - 5'd1;
                end
            end

            // Clear overrun on status read
            if (read_state == READ_DATA && axi_rvalid && axi_rready &&
                axi_araddr[7:0] == 8'h04) begin
                rx_overrun <= 1'b0;
            end
        end
    end

    // RX state machine (sample on baud tick)
    logic rx_sampling;  // Flag to indicate we're in the middle of sampling

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_data <= 8'd0;
            rx_bit_count <= 3'd0;
            rx_data_ready <= 1'b0;
            rx_sampling <= 1'b0;
        end else begin
            rx_data_ready <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    rx_sampling <= 1'b0;
                    // Wait for start bit (falling edge on RX line)
                    if (uart_rx_sync2 == 1'b0 && !rx_sampling) begin
                        rx_bit_count <= 3'd0;
                        rx_sampling <= 1'b1;
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    // Wait for one baud tick to skip start bit
                    if (rx_baud_tick) begin
                        rx_state <= RX_DATA;
                    end
                end

                RX_DATA: begin
                    if (rx_baud_tick) begin
                        // Sample at bit center
                        rx_data[rx_bit_count] <= uart_rx_sync2;

                        if (rx_bit_count == 3'd7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_count <= rx_bit_count + 3'd1;
                        end
                    end
                end

                RX_STOP: begin
                    if (rx_baud_tick) begin
                        // Check for stop bit (should be high)
                        if (uart_rx_sync2 == 1'b1) begin
                            // Valid stop bit, data is ready
                            rx_data_ready <= 1'b1;
                        end
                        // Go back to idle regardless
                        rx_state <= RX_IDLE;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // Write channel state machine
    logic [31:0] write_addr_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_state <= WRITE_IDLE;
            write_addr_reg <= 32'd0;
            axi_awready <= 1'b0;
            axi_wready <= 1'b0;
            axi_bresp <= 2'b00;
            axi_bvalid <= 1'b0;
        end else begin
            case (write_state)
                WRITE_IDLE: begin
                    axi_awready <= 1'b1;
                    axi_wready <= 1'b0;
                    axi_bvalid <= 1'b0;

                    if (axi_awvalid && axi_awready) begin
                        write_addr_reg <= axi_awaddr;
                        axi_awready <= 1'b0;
                        write_state <= WRITE_DATA;
                    end
                end

                WRITE_DATA: begin
                    axi_wready <= 1'b1;

                    if (axi_wvalid && axi_wready) begin
                        axi_wready <= 1'b0;
                        write_state <= WRITE_RESP;

                        // TX data is written to FIFO in separate always block
                    end
                end

                WRITE_RESP: begin
                    axi_bresp <= 2'b00;  // OKAY
                    axi_bvalid <= 1'b1;

                    if (axi_bvalid && axi_bready) begin
                        axi_bvalid <= 1'b0;
                        write_state <= WRITE_IDLE;
                    end
                end

                default: write_state <= WRITE_IDLE;
            endcase
        end
    end

    // Read channel state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_state <= READ_IDLE;
            axi_arready <= 1'b0;
            axi_ardata <= 32'd0;
            axi_rresp <= 2'b00;
            axi_rvalid <= 1'b0;
        end else begin
            case (read_state)
                READ_IDLE: begin
                    axi_arready <= 1'b1;
                    axi_rvalid <= 1'b0;

                    if (axi_arvalid && axi_arready) begin
                        axi_arready <= 1'b0;
                        read_state <= READ_DATA;

                        // Perform read
                        case (axi_araddr[7:0])
                            8'h00: begin
                                // RX data register - read from FIFO
                                if (!rx_fifo_empty) begin
                                    axi_ardata <= {24'd0, rx_fifo[rx_fifo_rd_ptr]};
                                end else begin
                                    axi_ardata <= 32'd0;
                                end
                            end
                            8'h04: begin
                                // Status register
                                axi_ardata <= {28'd0, rx_overrun, !rx_fifo_empty, tx_fifo_full, tx_busy};
                            end
                            default: axi_ardata <= 32'd0;
                        endcase
                    end
                end

                READ_DATA: begin
                    axi_rresp <= 2'b00;  // OKAY
                    axi_rvalid <= 1'b1;

                    if (axi_rvalid && axi_rready) begin
                        axi_rvalid <= 1'b0;
                        read_state <= READ_IDLE;
                    end
                end

                default: read_state <= READ_IDLE;
            endcase
        end
    end

endmodule
