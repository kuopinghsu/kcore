// RISC-V SoC Top Module
// Integrates CPU core, CLINT, UART and AXI interconnect
// Memory Map:
//   0x8000_0000 - 0x801F_FFFF: RAM (2MB) - External AXI Memory
//   0x0200_0000 - 0x0200_FFFF: CLINT
//   0x1000_0000 - 0x1000_0FFF: UART
// Magic Addresses:
//   0xFFFF_FFF0: Exit request (write exit code)
//   0xFFFF_FFF4: Console output (write character)

// DPI-C import for console output
import "DPI-C" function void console_putchar(input byte c);

module soc_top #(
    parameter ENABLE_MEM_TRACE = 0  // Enable memory transaction trace logging (0=off, 1=on)
) (
    input  logic        clk,
    input  logic        rst_n,

    // UART external interface
    output logic        uart_tx,
    input  logic        uart_rx,

    // External AXI Memory Interface (Slave)
    // Write Address Channel
    output logic [31:0] mem_axi_awaddr,
    output logic        mem_axi_awvalid,
    input  logic        mem_axi_awready,

    // Write Data Channel
    output logic [31:0] mem_axi_wdata,
    output logic [3:0]  mem_axi_wstrb,
    output logic        mem_axi_wvalid,
    input  logic        mem_axi_wready,

    // Write Response Channel
    input  logic [1:0]  mem_axi_bresp,
    input  logic        mem_axi_bvalid,
    output logic        mem_axi_bready,

    // Read Address Channel
    output logic [31:0] mem_axi_araddr,
    output logic        mem_axi_arvalid,
    input  logic        mem_axi_arready,

    // Read Data Channel
    input  logic [31:0] mem_axi_ardata,
    input  logic [1:0]  mem_axi_rresp,
    input  logic        mem_axi_rvalid,
    output logic        mem_axi_rready,

    // Performance counters
    output logic [63:0] cycle_count,
    output logic [63:0] instret_count,
    output logic [63:0] stall_count,

    // Exit detection
    output logic        exit_request,
    output logic [31:0] exit_code,

    // Tohost address from ELF (0 = disabled, use magic address only)
    input  logic [31:0] tohost_addr
);

    // CPU simple interface signals
    logic        cpu_imem_valid;
    logic        cpu_imem_ready;
    logic [31:0] cpu_imem_addr;
    logic [31:0] cpu_imem_rdata;
    logic        cpu_imem_flush;

    logic        cpu_dmem_valid;
    logic        cpu_dmem_ready;
    logic        cpu_dmem_write;
    logic [31:0] cpu_dmem_addr;
    logic [31:0] cpu_dmem_wdata;
    logic [3:0]  cpu_dmem_wstrb;
    logic [31:0] cpu_dmem_rdata;

    // CPU AXI Master signals (after arbitration)
    logic [31:0] cpu_axi_awaddr;
    logic        cpu_axi_awvalid;
    logic        cpu_axi_awready;
    logic [31:0] cpu_axi_wdata;
    logic [3:0]  cpu_axi_wstrb;
    logic        cpu_axi_wvalid;
    logic        cpu_axi_wready;
    logic [1:0]  cpu_axi_bresp;
    logic        cpu_axi_bvalid;
    logic        cpu_axi_bready;
    logic [31:0] cpu_axi_araddr;
    logic        cpu_axi_arvalid;
    logic        cpu_axi_arready;
    logic [31:0] cpu_axi_ardata;
    logic [1:0]  cpu_axi_rresp;
    logic        cpu_axi_rvalid;
    logic        cpu_axi_rready;

    // CLINT AXI Slave signals
    logic [31:0] clint_axi_awaddr;
    logic        clint_axi_awvalid;
    logic        clint_axi_awready;
    logic [31:0] clint_axi_wdata;
    logic [3:0]  clint_axi_wstrb;
    logic        clint_axi_wvalid;
    logic        clint_axi_wready;
    logic [1:0]  clint_axi_bresp;
    logic        clint_axi_bvalid;
    logic        clint_axi_bready;
    logic [31:0] clint_axi_araddr;
    logic        clint_axi_arvalid;
    logic        clint_axi_arready;
    logic [31:0] clint_axi_ardata;
    logic [1:0]  clint_axi_rresp;
    logic        clint_axi_rvalid;
    logic        clint_axi_rready;

    // Latched address decode for read/write transactions
    logic        sel_mem_r, sel_clint_r, sel_uart_r;
    logic        sel_mem_w, sel_clint_w, sel_uart_w;

    // UART AXI Slave signals
    logic [31:0] uart_axi_awaddr;
    logic        uart_axi_awvalid;
    logic        uart_axi_awready;
    logic [31:0] uart_axi_wdata;
    logic [3:0]  uart_axi_wstrb;
    logic        uart_axi_wvalid;
    logic        uart_axi_wready;
    logic [1:0]  uart_axi_bresp;
    logic        uart_axi_bvalid;
    logic        uart_axi_bready;
    logic [31:0] uart_axi_araddr;
    logic        uart_axi_arvalid;
    logic        uart_axi_arready;
    logic [31:0] uart_axi_ardata;
    logic [1:0]  uart_axi_rresp;
    logic        uart_axi_rvalid;
    logic        uart_axi_rready;

    // Interrupt signals
    logic        timer_irq;
    logic        software_irq;
    logic        external_irq;

    assign external_irq = 1'b0;  // Not used in this design

    // RVFI signals (unused in SoC, but need to be declared for Verilator)
    /* verilator lint_off UNUSEDSIGNAL */
    logic        rvfi_valid_unused;
    logic [63:0] rvfi_order_unused;
    logic [31:0] rvfi_insn_unused;
    logic        rvfi_trap_unused;
    logic        rvfi_halt_unused;
    logic        rvfi_intr_unused;
    logic [1:0]  rvfi_mode_unused;
    logic [1:0]  rvfi_ixl_unused;
    logic [31:0] rvfi_pc_rdata_unused;
    logic [31:0] rvfi_pc_wdata_unused;
    logic [4:0]  rvfi_rs1_addr_unused;
    logic [4:0]  rvfi_rs2_addr_unused;
    logic [31:0] rvfi_rs1_rdata_unused;
    logic [31:0] rvfi_rs2_rdata_unused;
    logic [4:0]  rvfi_rd_addr_unused;
    logic [31:0] rvfi_rd_wdata_unused;
    logic [31:0] rvfi_mem_addr_unused;
    logic [3:0]  rvfi_mem_rmask_unused;
    logic [3:0]  rvfi_mem_wmask_unused;
    logic [31:0] rvfi_mem_rdata_unused;
    logic [31:0] rvfi_mem_wdata_unused;
    /* verilator lint_on UNUSEDSIGNAL */

    // ========================================================================
    // CPU Core Instance
    // ========================================================================

    kcore #(
        .ENABLE_MEM_TRACE(ENABLE_MEM_TRACE),
        .ENABLE_RVFI(0)  // RVFI disabled in SoC (used only for formal verification)
    ) u_cpu (
        .clk             (clk),
        .rst_n           (rst_n),
        .imem_valid      (cpu_imem_valid),
        .imem_ready      (cpu_imem_ready),
        .imem_addr       (cpu_imem_addr),
        .imem_rdata      (cpu_imem_rdata),
        .imem_flush      (cpu_imem_flush),
        .dmem_valid      (cpu_dmem_valid),
        .dmem_ready      (cpu_dmem_ready),
        .dmem_write      (cpu_dmem_write),
        .dmem_addr       (cpu_dmem_addr),
        .dmem_wdata      (cpu_dmem_wdata),
        .dmem_wstrb      (cpu_dmem_wstrb),
        .dmem_rdata      (cpu_dmem_rdata),
        .timer_irq       (timer_irq),
        .software_irq    (software_irq),
        .external_irq    (external_irq),
        .cycle_count     (cycle_count),
        .instret_count   (instret_count),
        .stall_count     (stall_count),
        // RVFI signals - tied off (unused in SoC)
        .rvfi_valid      (rvfi_valid_unused),
        .rvfi_order      (rvfi_order_unused),
        .rvfi_insn       (rvfi_insn_unused),
        .rvfi_trap       (rvfi_trap_unused),
        .rvfi_halt       (rvfi_halt_unused),
        .rvfi_intr       (rvfi_intr_unused),
        .rvfi_mode       (rvfi_mode_unused),
        .rvfi_ixl        (rvfi_ixl_unused),
        .rvfi_pc_rdata   (rvfi_pc_rdata_unused),
        .rvfi_pc_wdata   (rvfi_pc_wdata_unused),
        .rvfi_rs1_addr   (rvfi_rs1_addr_unused),
        .rvfi_rs2_addr   (rvfi_rs2_addr_unused),
        .rvfi_rs1_rdata  (rvfi_rs1_rdata_unused),
        .rvfi_rs2_rdata  (rvfi_rs2_rdata_unused),
        .rvfi_rd_addr    (rvfi_rd_addr_unused),
        .rvfi_rd_wdata   (rvfi_rd_wdata_unused),
        .rvfi_mem_addr   (rvfi_mem_addr_unused),
        .rvfi_mem_rmask  (rvfi_mem_rmask_unused),
        .rvfi_mem_wmask  (rvfi_mem_wmask_unused),
        .rvfi_mem_rdata  (rvfi_mem_rdata_unused),
        .rvfi_mem_wdata  (rvfi_mem_wdata_unused)
    );

    // ========================================================================
    // AXI Interface - Independent Read and Write Channels
    // ========================================================================
    // No arbitration between read and write for best dual-port memory performance
    // Read channel handles: instruction fetch + data read
    // Write channel handles: data write (fully independent)

    // Read channel state machine (for instruction fetch and data read)
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_ARADDR,
        RD_RDATA
    } rd_state_t;
    rd_state_t rd_state, rd_state_next;

    // Write channel state machine (fully independent)
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_AWADDR,
        WR_WDATA,
        WR_BRESP
    } wr_state_t;
    wr_state_t wr_state, wr_state_next;

    // Latched signals for read channel
    logic [31:0] rd_addr_latch;
    logic        rd_is_imem;  // 1=instruction fetch, 0=data read
    logic        imem_fetch_flushed;  // Track if current IMEM fetch was flushed

    // Latched signals for write channel
    logic [31:0] wr_addr_latch;
    logic [31:0] wr_data_latch;
    logic [3:0]  wr_strb_latch;

    // Read channel sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;
            rd_addr_latch <= 32'd0;
            rd_is_imem <= 1'b0;
            imem_fetch_flushed <= 1'b0;
        end else begin
            rd_state <= rd_state_next;

            // Track if IMEM fetch is flushed during read states
            if ((rd_state == RD_ARADDR || rd_state == RD_RDATA) && rd_is_imem && cpu_imem_flush) begin
                imem_fetch_flushed <= 1'b1;
            end else if (rd_state == RD_RDATA && cpu_axi_rvalid && cpu_axi_rready && imem_fetch_flushed) begin
                // Flushed fetch has been discarded
            end else if (rd_state == RD_IDLE && cpu_imem_valid && !cpu_imem_flush) begin
                // Clear flush flag when starting a valid new fetch
                imem_fetch_flushed <= 1'b0;
            end

            // Latch read address and type when starting transaction
            if (rd_state == RD_IDLE && rd_state_next == RD_ARADDR) begin
                if (cpu_imem_valid && !cpu_imem_flush) begin
                    rd_addr_latch <= cpu_imem_addr;
                    rd_is_imem <= 1'b1;
                end else if (cpu_dmem_valid && !cpu_dmem_write) begin
                    rd_addr_latch <= cpu_dmem_addr;
                    rd_is_imem <= 1'b0;
                end
            end
        end
    end

    // Write channel sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
            wr_addr_latch <= 32'd0;
            wr_data_latch <= 32'd0;
            wr_strb_latch <= 4'd0;
        end else begin
            wr_state <= wr_state_next;

            // Latch write signals when starting transaction
            if (wr_state == WR_IDLE && wr_state_next == WR_AWADDR) begin
                wr_addr_latch <= cpu_dmem_addr;
                wr_data_latch <= cpu_dmem_wdata;
                wr_strb_latch <= cpu_dmem_wstrb;
            end
        end
    end

    // Read channel combinational logic
    always_comb begin
        rd_state_next = rd_state;

        // Default values for CPU interface (read)
        cpu_imem_ready = 1'b0;
        cpu_imem_rdata = 32'd0;

        // Default values for AXI read channel
        cpu_axi_araddr = rd_addr_latch;
        cpu_axi_arvalid = 1'b0;
        cpu_axi_rready = 1'b0;

        case (rd_state)
            RD_IDLE: begin
                // Priority: instruction fetch > data read
                if (cpu_imem_valid && !cpu_imem_flush) begin
                    rd_state_next = RD_ARADDR;
                end else if (cpu_dmem_valid && !cpu_dmem_write) begin
                    rd_state_next = RD_ARADDR;
                end
            end

            RD_ARADDR: begin
                cpu_axi_araddr = rd_addr_latch;
                cpu_axi_arvalid = 1'b1;

                if (cpu_axi_arvalid && cpu_axi_arready) begin
                    rd_state_next = RD_RDATA;
                end
            end

            RD_RDATA: begin
                cpu_axi_rready = 1'b1;

                if (cpu_axi_rvalid && cpu_axi_rready) begin
                    if (rd_is_imem) begin
                        // Instruction fetch completion
                        if (!imem_fetch_flushed && !cpu_imem_flush) begin
                            cpu_imem_ready = 1'b1;
                            cpu_imem_rdata = cpu_axi_ardata;
                        end
                    end
                    rd_state_next = RD_IDLE;
                end
            end

            default: rd_state_next = RD_IDLE;
        endcase
    end

    // Write channel combinational logic
    always_comb begin
        wr_state_next = wr_state;

        // Default values for AXI write channel
        cpu_axi_awaddr = wr_addr_latch;
        cpu_axi_awvalid = 1'b0;
        cpu_axi_wdata = wr_data_latch;
        cpu_axi_wstrb = wr_strb_latch;
        cpu_axi_wvalid = 1'b0;
        cpu_axi_bready = 1'b0;

        case (wr_state)
            WR_IDLE: begin
                // Handle magic addresses immediately (exit and console)
                if (cpu_dmem_valid && cpu_dmem_write &&
                    (cpu_dmem_addr == 32'hFFFFFFF0 || cpu_dmem_addr == 32'hFFFFFFF4)) begin
                    // Magic addresses handled outside AXI
                    // Don't start AXI transaction
                end else if (cpu_dmem_valid && cpu_dmem_write) begin
                    wr_state_next = WR_AWADDR;
                end
            end

            WR_AWADDR: begin
                cpu_axi_awaddr = wr_addr_latch;
                cpu_axi_awvalid = 1'b1;

                if (cpu_axi_awvalid && cpu_axi_awready) begin
                    wr_state_next = WR_WDATA;
                end
            end

            WR_WDATA: begin
                cpu_axi_wdata = wr_data_latch;
                cpu_axi_wstrb = wr_strb_latch;
                cpu_axi_wvalid = 1'b1;

                if (cpu_axi_wvalid && cpu_axi_wready) begin
                    wr_state_next = WR_BRESP;
                end
            end

            WR_BRESP: begin
                cpu_axi_bready = 1'b1;

                if (cpu_axi_bvalid && cpu_axi_bready) begin
                    wr_state_next = WR_IDLE;
                end
            end

            default: wr_state_next = WR_IDLE;
        endcase
    end

    // Data memory ready signal - combines read and write completion
    logic dmem_read_ready;
    logic dmem_write_ready;
    logic magic_write_ready;

    // Read completion (from read channel)
    assign dmem_read_ready = (rd_state == RD_RDATA) && !rd_is_imem &&
                             cpu_axi_rvalid && cpu_axi_rready;

    // Write completion (from write channel)
    assign dmem_write_ready = (wr_state == WR_BRESP) &&
                              cpu_axi_bvalid && cpu_axi_bready;

    // Magic address write (completes immediately)
    assign magic_write_ready = cpu_dmem_valid && cpu_dmem_write &&
                               (cpu_dmem_addr == 32'hFFFFFFF0 || cpu_dmem_addr == 32'hFFFFFFF4);

    assign cpu_dmem_ready = dmem_read_ready || dmem_write_ready || magic_write_ready;
    assign cpu_dmem_rdata = (rd_state == RD_RDATA && !rd_is_imem) ? cpu_axi_ardata : 32'd0;

    // ========================================================================
    // CLINT Instance
    // ========================================================================

    clint u_clint (
        .clk             (clk),
        .rst_n           (rst_n),
        .axi_awaddr      (clint_axi_awaddr),
        .axi_awvalid     (clint_axi_awvalid),
        .axi_awready     (clint_axi_awready),
        .axi_wdata       (clint_axi_wdata),
        .axi_wstrb       (clint_axi_wstrb),
        .axi_wvalid      (clint_axi_wvalid),
        .axi_wready      (clint_axi_wready),
        .axi_bresp       (clint_axi_bresp),
        .axi_bvalid      (clint_axi_bvalid),
        .axi_bready      (clint_axi_bready),
        .axi_araddr      (clint_axi_araddr),
        .axi_arvalid     (clint_axi_arvalid),
        .axi_arready     (clint_axi_arready),
        .axi_ardata      (clint_axi_ardata),
        .axi_rresp       (clint_axi_rresp),
        .axi_rvalid      (clint_axi_rvalid),
        .axi_rready      (clint_axi_rready),
        .timer_irq       (timer_irq),
        .software_irq    (software_irq)
    );

    // ========================================================================
    // UART Instance
    // ========================================================================

    uart #(
        .CLK_FREQ        (50_000_000),
        .BAUD_RATE       (12_500_000)  // 12.5 Mbaud (4 cycles/bit, BAUD_DIV=4)
    ) u_uart (
        .clk             (clk),
        .rst_n           (rst_n),
        .axi_awaddr      (uart_axi_awaddr),
        .axi_awvalid     (uart_axi_awvalid),
        .axi_awready     (uart_axi_awready),
        .axi_wdata       (uart_axi_wdata),
        .axi_wstrb       (uart_axi_wstrb),
        .axi_wvalid      (uart_axi_wvalid),
        .axi_wready      (uart_axi_wready),
        .axi_bresp       (uart_axi_bresp),
        .axi_bvalid      (uart_axi_bvalid),
        .axi_bready      (uart_axi_bready),
        .axi_araddr      (uart_axi_araddr),
        .axi_arvalid     (uart_axi_arvalid),
        .axi_arready     (uart_axi_arready),
        .axi_ardata      (uart_axi_ardata),
        .axi_rresp       (uart_axi_rresp),
        .axi_rvalid      (uart_axi_rvalid),
        .axi_rready      (uart_axi_rready),
        .uart_tx         (uart_tx),
        .uart_rx         (uart_rx)
    );

    // ========================================================================
    // Exit Detection - Magic Address Writes
    // ========================================================================
    // Detect writes to magic exit address 0xFFFFFFF0 or tohost variable
    // The CPU writes exit code to signal program completion

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exit_request <= 1'b0;
            exit_code <= 32'h0;
        end else begin
            // Detect write completion (valid && ready) to exit address
            if (cpu_dmem_valid && cpu_dmem_ready && cpu_dmem_write) begin
                // Check magic address or tohost address
                if (cpu_dmem_addr == 32'hFFFFFFF0 ||
                    (tohost_addr != 32'h0 && cpu_dmem_addr == tohost_addr)) begin
                    exit_request <= 1'b1;
                    // For tohost protocol, extract exit code from (value >> 1)
                    if (cpu_dmem_addr == tohost_addr) begin
                        exit_code <= cpu_dmem_wdata >> 1;
                    end else begin
                        exit_code <= cpu_dmem_wdata;
                    end
                end
            end
        end
    end

    // ========================================================================
    // Console Output - Magic Address Write (0xFFFFFFF4)
    // ========================================================================
    // Detect writes to console magic address and output character via DPI

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // No state needed
        end else begin
            // Output character when write completes (valid && ready handshake)
            if (cpu_dmem_valid && cpu_dmem_ready && cpu_dmem_write &&
                (cpu_dmem_addr & 32'hFFFFFFFC) == 32'hFFFFFFF4) begin
                // For word-aligned address, character is in byte 0
                console_putchar(cpu_dmem_wdata[7:0]);
            end
        end
    end

    // ========================================================================
    // AXI Interconnect (Simple Address Decoder)
    // ========================================================================

    // Address decode - latch on address handshake
    logic sel_mem, sel_clint, sel_uart;

    // Latch read address decode when AR handshake completes
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel_mem_r <= 1'b0;
            sel_clint_r <= 1'b0;
            sel_uart_r <= 1'b0;
        end else if (cpu_axi_arvalid && cpu_axi_arready) begin
            // Latch decode on read address handshake
            if (cpu_axi_araddr[31:28] == 4'h8) begin
                sel_mem_r <= 1'b1;
                sel_clint_r <= 1'b0;
                sel_uart_r <= 1'b0;
            end else if (cpu_axi_araddr[31:24] == 8'h02) begin
                sel_mem_r <= 1'b0;
                sel_clint_r <= 1'b1;
                sel_uart_r <= 1'b0;
            end else if (cpu_axi_araddr[31:24] == 8'h10) begin
                sel_mem_r <= 1'b0;
                sel_clint_r <= 1'b0;
                sel_uart_r <= 1'b1;
            end else begin
                sel_mem_r <= 1'b0;
                sel_clint_r <= 1'b0;
                sel_uart_r <= 1'b0;
            end
        end else if ((cpu_axi_rvalid && cpu_axi_rready) || (rd_state == RD_IDLE && wr_state == WR_IDLE)) begin
            // Clear after read data handshake completes OR when both channels idle
            sel_mem_r <= 1'b0;
            sel_clint_r <= 1'b0;
            sel_uart_r <= 1'b0;
        end
    end

    // Latch write address decode when AW handshake completes
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel_mem_w <= 1'b0;
            sel_clint_w <= 1'b0;
            sel_uart_w <= 1'b0;
        end else if (cpu_axi_awvalid && cpu_axi_awready) begin
            // Latch decode on write address handshake
            if (cpu_axi_awaddr[31:28] == 4'h8) begin
                sel_mem_w <= 1'b1;
                sel_clint_w <= 1'b0;
                sel_uart_w <= 1'b0;
            end else if (cpu_axi_awaddr[31:24] == 8'h02) begin
                sel_mem_w <= 1'b0;
                sel_clint_w <= 1'b1;
                sel_uart_w <= 1'b0;
            end else if (cpu_axi_awaddr[31:24] == 8'h10) begin
                sel_mem_w <= 1'b0;
                sel_clint_w <= 1'b0;
                sel_uart_w <= 1'b1;
            end else begin
                sel_mem_w <= 1'b0;
                sel_clint_w <= 1'b0;
                sel_uart_w <= 1'b0;
            end
        end else if (cpu_axi_bvalid && cpu_axi_bready) begin
            // Clear after write response handshake completes
            sel_mem_w <= 1'b0;
            sel_clint_w <= 1'b0;
            sel_uart_w <= 1'b0;
        end
    end

    // Error response for unmapped addresses
    logic unmapped_write_pending;
    logic unmapped_read_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            unmapped_write_pending <= 1'b0;
            unmapped_read_pending <= 1'b0;
        end else begin
            // Set unmapped write when AW handshake to unmapped address
            if (cpu_axi_awvalid && cpu_axi_awready && !sel_mem && !sel_clint && !sel_uart) begin
                unmapped_write_pending <= 1'b1;
            end else if (cpu_axi_bvalid && cpu_axi_bready && !sel_mem_w && !sel_clint_w && !sel_uart_w) begin
                unmapped_write_pending <= 1'b0;
            end

            // Set unmapped read when AR handshake to unmapped address
            if (cpu_axi_arvalid && cpu_axi_arready && !sel_mem && !sel_clint && !sel_uart) begin
                unmapped_read_pending <= 1'b1;
            end else if (cpu_axi_rvalid && cpu_axi_rready && !sel_mem_r && !sel_clint_r && !sel_uart_r) begin
                unmapped_read_pending <= 1'b0;
            end
        end
    end

    // Combinational decode for AR/AW channels (before handshake)
    always_comb begin
        sel_mem = 1'b0;
        sel_clint = 1'b0;
        sel_uart = 1'b0;

        // Decode based on CPU address
        if (cpu_axi_arvalid) begin
            if (cpu_axi_araddr[31:28] == 4'h8) begin
                sel_mem = 1'b1;  // 0x8000_0000 - 0x8FFF_FFFF
            end else if (cpu_axi_araddr[31:24] == 8'h02) begin
                sel_clint = 1'b1;  // 0x0200_0000 - 0x02FF_FFFF
            end else if (cpu_axi_araddr[31:24] == 8'h10) begin
                sel_uart = 1'b1;  // 0x1000_0000 - 0x10FF_FFFF
            end
        end else if (cpu_axi_awvalid) begin
            if (cpu_axi_awaddr[31:28] == 4'h8) begin
                sel_mem = 1'b1;
            end else if (cpu_axi_awaddr[31:24] == 8'h02) begin
                sel_clint = 1'b1;
            end else if (cpu_axi_awaddr[31:24] == 8'h10) begin
                sel_uart = 1'b1;
            end
        end
    end

    // Write channel routing
    always_comb begin
        // Default values
        mem_axi_awaddr = cpu_axi_awaddr;
        mem_axi_awvalid = 1'b0;
        mem_axi_wdata = cpu_axi_wdata;
        mem_axi_wstrb = cpu_axi_wstrb;
        mem_axi_wvalid = 1'b0;
        mem_axi_bready = 1'b0;

        clint_axi_awaddr = cpu_axi_awaddr;
        clint_axi_awvalid = 1'b0;
        clint_axi_wdata = cpu_axi_wdata;
        clint_axi_wstrb = cpu_axi_wstrb;
        clint_axi_wvalid = 1'b0;
        clint_axi_bready = 1'b0;

        uart_axi_awaddr = cpu_axi_awaddr;
        uart_axi_awvalid = 1'b0;
        uart_axi_wdata = cpu_axi_wdata;
        uart_axi_wstrb = cpu_axi_wstrb;
        uart_axi_wvalid = 1'b0;
        uart_axi_bready = 1'b0;

        cpu_axi_awready = 1'b0;
        cpu_axi_wready = 1'b0;
        cpu_axi_bresp = 2'b00;
        cpu_axi_bvalid = 1'b0;

        // AW channel routing uses combinational decode
        if (sel_mem) begin
            mem_axi_awvalid = cpu_axi_awvalid;
            cpu_axi_awready = mem_axi_awready;
        end else if (sel_clint) begin
            clint_axi_awvalid = cpu_axi_awvalid;
            cpu_axi_awready = clint_axi_awready;
        end else if (sel_uart) begin
            uart_axi_awvalid = cpu_axi_awvalid;
            cpu_axi_awready = uart_axi_awready;
        end else begin
            // Unmapped address - accept immediately with error
            cpu_axi_awready = cpu_axi_awvalid;
        end

        // W channel routing uses latched decode (sel_mem_w)
        if (sel_mem_w) begin
            mem_axi_wvalid = cpu_axi_wvalid;
            cpu_axi_wready = mem_axi_wready;
        end else if (sel_clint_w) begin
            clint_axi_wvalid = cpu_axi_wvalid;
            cpu_axi_wready = clint_axi_wready;
        end else if (sel_uart_w) begin
            uart_axi_wvalid = cpu_axi_wvalid;
            cpu_axi_wready = uart_axi_wready;
        end else if (unmapped_write_pending) begin
            // Unmapped write - accept immediately
            cpu_axi_wready = cpu_axi_wvalid;
        end

        // B channel routing uses latched decode
        if (sel_mem_w) begin
            mem_axi_bready = cpu_axi_bready;
            cpu_axi_bresp = mem_axi_bresp;
            cpu_axi_bvalid = mem_axi_bvalid;
        end else if (sel_clint_w) begin
            clint_axi_bready = cpu_axi_bready;
            cpu_axi_bresp = clint_axi_bresp;
            cpu_axi_bvalid = clint_axi_bvalid;
        end else if (sel_uart_w) begin
            uart_axi_bready = cpu_axi_bready;
            cpu_axi_bresp = uart_axi_bresp;
            cpu_axi_bvalid = uart_axi_bvalid;
        end else if (unmapped_write_pending) begin
            // Return error response for unmapped write
            cpu_axi_bresp = 2'b11;  // DECERR (decode error)
            cpu_axi_bvalid = 1'b1;
        end
    end

    // Read channel routing
    always_comb begin
        // Default values
        mem_axi_araddr = cpu_axi_araddr;
        mem_axi_arvalid = 1'b0;
        mem_axi_rready = 1'b0;

        clint_axi_araddr = cpu_axi_araddr;
        clint_axi_arvalid = 1'b0;
        clint_axi_rready = 1'b0;

        uart_axi_araddr = cpu_axi_araddr;
        uart_axi_arvalid = 1'b0;
        uart_axi_rready = 1'b0;

        cpu_axi_arready = 1'b0;
        cpu_axi_ardata = 32'd0;
        cpu_axi_rresp = 2'b00;
        cpu_axi_rvalid = 1'b0;

        // AR channel routing uses combinational decode
        if (sel_mem) begin
            mem_axi_arvalid = cpu_axi_arvalid;
            cpu_axi_arready = mem_axi_arready;
        end else if (sel_clint) begin
            clint_axi_arvalid = cpu_axi_arvalid;
            cpu_axi_arready = clint_axi_arready;
        end else if (sel_uart) begin
            uart_axi_arvalid = cpu_axi_arvalid;
            cpu_axi_arready = uart_axi_arready;
        end else begin
            // Unmapped address - accept immediately with error
            cpu_axi_arready = cpu_axi_arvalid;
        end

        // R channel routing uses latched decode
        if (sel_mem_r) begin
            mem_axi_rready = cpu_axi_rready;
            cpu_axi_ardata = mem_axi_ardata;
            cpu_axi_rresp = mem_axi_rresp;
            cpu_axi_rvalid = mem_axi_rvalid;
        end else if (sel_clint_r) begin
            clint_axi_rready = cpu_axi_rready;
            cpu_axi_ardata = clint_axi_ardata;
            cpu_axi_rresp = clint_axi_rresp;
            cpu_axi_rvalid = clint_axi_rvalid;
        end else if (sel_uart_r) begin
            uart_axi_rready = cpu_axi_rready;
            cpu_axi_ardata = uart_axi_ardata;
            cpu_axi_rresp = uart_axi_rresp;
            cpu_axi_rvalid = uart_axi_rvalid;
        end else if (unmapped_read_pending) begin
            // Return error response for unmapped read
            cpu_axi_ardata = 32'hDEADBEEF;
            cpu_axi_rresp = 2'b11;  // DECERR (decode error)
            cpu_axi_rvalid = 1'b1;
        end
    end

    // ========================================================================
    // Waveform Dump for Non-Verilator Simulators
    // ========================================================================

`ifndef VERILATOR
    initial begin
        // Check for waveform dump command line arguments
        if ($test$plusargs("VCD")) begin
            $dumpfile("dump.vcd");
            $dumpvars(0, soc_top);
            $display("VCD waveform dump enabled: dump.vcd");
        end else if ($test$plusargs("FST")) begin
            // FST format (for some simulators that support it)
            $dumpfile("dump.fst");
            $dumpvars(0, soc_top);
            $display("FST waveform dump enabled: dump.fst");
        end else if ($test$plusargs("WAVE")) begin
            // Default to VCD if just +WAVE is specified
            $dumpfile("dump.vcd");
            $dumpvars(0, soc_top);
            $display("Waveform dump enabled: dump.vcd");
        end
    end
`endif

endmodule
