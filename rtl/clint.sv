// Core Local Interruptor (CLINT)
// Provides machine-mode timer interrupts and software interrupts
// Memory-mapped registers:
//   0x0000: msip (Machine Software Interrupt Pending)
//   0x4000: mtimecmp low (Timer compare value lower 32-bit)
//   0x4004: mtimecmp high (Timer compare value upper 32-bit)
//   0xBFF8: mtime low (Current time lower 32-bit)
//   0xBFFC: mtime high (Current time upper 32-bit)

module clint (
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

    // Interrupt outputs
    output logic        timer_irq,
    output logic        software_irq
);

    // Internal registers
    logic [63:0] mtime;
    logic [63:0] mtimecmp;
    logic        msip;

    // AXI state machines
    typedef enum logic [1:0] {
        WRITE_IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP
    } write_state_t;
    write_state_t write_state;

    typedef enum logic [1:0] {
        READ_IDLE,
        READ_ADDR,
        READ_DATA
    } read_state_t;
    read_state_t read_state;

    logic [31:0] write_addr_reg;
    logic [31:0] write_data_reg;
    logic [3:0]  write_strb_reg;

    // mtime counter (increments every clock cycle per RISC-V spec)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= 64'd0;
        end else begin
            mtime <= mtime + 64'd1;
        end
    end

    // Timer interrupt generation (combinational for immediate response)
    assign timer_irq = (mtime >= mtimecmp);

    // Software interrupt
    assign software_irq = msip;

    // Write channel state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_state <= WRITE_IDLE;
            write_addr_reg <= 32'd0;
            write_data_reg <= 32'd0;
            write_strb_reg <= 4'd0;
            axi_awready <= 1'b0;
            axi_wready <= 1'b0;
            axi_bresp <= 2'b00;
            axi_bvalid <= 1'b0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
            msip <= 1'b0;
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
                        write_data_reg <= axi_wdata;
                        write_strb_reg <= axi_wstrb;
                        axi_wready <= 1'b0;

                        // Perform write
                        case (write_addr_reg[15:0])
                            16'h0000: begin  // msip
                                if (axi_wstrb[0]) msip <= axi_wdata[0];
                            end
                            16'h4000: begin  // mtimecmp low
                                if (axi_wstrb[0]) mtimecmp[7:0] <= axi_wdata[7:0];
                                if (axi_wstrb[1]) mtimecmp[15:8] <= axi_wdata[15:8];
                                if (axi_wstrb[2]) mtimecmp[23:16] <= axi_wdata[23:16];
                                if (axi_wstrb[3]) mtimecmp[31:24] <= axi_wdata[31:24];
                            end
                            16'h4004: begin  // mtimecmp high
                                if (axi_wstrb[0]) mtimecmp[39:32] <= axi_wdata[7:0];
                                if (axi_wstrb[1]) mtimecmp[47:40] <= axi_wdata[15:8];
                                if (axi_wstrb[2]) mtimecmp[55:48] <= axi_wdata[23:16];
                                if (axi_wstrb[3]) mtimecmp[63:56] <= axi_wdata[31:24];
                            end
                            16'hBFF8: begin  // mtime low (writable for testing)
                                if (axi_wstrb[0]) mtime[7:0] <= axi_wdata[7:0];
                                if (axi_wstrb[1]) mtime[15:8] <= axi_wdata[15:8];
                                if (axi_wstrb[2]) mtime[23:16] <= axi_wdata[23:16];
                                if (axi_wstrb[3]) mtime[31:24] <= axi_wdata[31:24];
                            end
                            16'hBFFC: begin  // mtime high (writable for testing)
                                if (axi_wstrb[0]) mtime[39:32] <= axi_wdata[7:0];
                                if (axi_wstrb[1]) mtime[47:40] <= axi_wdata[15:8];
                                if (axi_wstrb[2]) mtime[55:48] <= axi_wdata[23:16];
                                if (axi_wstrb[3]) mtime[63:56] <= axi_wdata[31:24];
                            end
                            default: begin
                                // Invalid address - ignore
                            end
                        endcase

                        write_state <= WRITE_RESP;
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
                        case (axi_araddr[15:0])
                            16'h0000: axi_ardata <= {31'd0, msip};
                            16'h4000: axi_ardata <= mtimecmp[31:0];
                            16'h4004: axi_ardata <= mtimecmp[63:32];
                            16'hBFF8: axi_ardata <= mtime[31:0];
                            16'hBFFC: axi_ardata <= mtime[63:32];
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
