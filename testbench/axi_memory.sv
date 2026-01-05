// AXI4-Lite Memory Module
// Supports one-port or dual-port memory configurations with pipelined design
// Memory size: 2MB (configurable)
// Separate read and write latency support
// No state machines - uses pipelined architecture for best performance

module axi_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_SIZE = 2 * 1024 * 1024,     // 2MB
    parameter BASE_ADDR = 32'h80000000,       // Base address for memory mapping
    parameter MEM_READ_LATENCY = 1,      // Read latency in cycles (1 to 16)
    parameter MEM_WRITE_LATENCY = 1,     // Write latency in cycles (1 to 16)
    parameter ENABLE_MEM_TRACE = 0,      // Enable memory transaction trace logging (0=off, 1=on)
    parameter MEM_DUAL_PORT = 1          // 1=Dual-port (best performance), 0=One-port (with arbitration)
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // AXI4-Lite Slave Interface
    // Write Address Channel
    input  logic [ADDR_WIDTH-1:0]   axi_awaddr,
    input  logic                    axi_awvalid,
    output logic                    axi_awready,

    // Write Data Channel
    input  logic [DATA_WIDTH-1:0]   axi_wdata,
    input  logic [3:0]              axi_wstrb,
    input  logic                    axi_wvalid,
    output logic                    axi_wready,

    // Write Response Channel
    output logic [1:0]              axi_bresp,
    output logic                    axi_bvalid,
    input  logic                    axi_bready,

    // Read Address Channel
    input  logic [ADDR_WIDTH-1:0]   axi_araddr,
    input  logic                    axi_arvalid,
    output logic                    axi_arready,

    // Read Data Channel
    output logic [DATA_WIDTH-1:0]   axi_rdata,
    output logic [1:0]              axi_rresp,
    output logic                    axi_rvalid,
    input  logic                    axi_rready
);

    // Memory array
    logic [7:0] mem [MEM_SIZE];

    // ============================================================================
    // State Representation for Backward Compatibility
    // ============================================================================
    // Legacy state signal for testbench compatibility
    // Encoding: 0=IDLE, 1=WRITE_WAIT, 2=WRITE_RESP, 3=READ_WAIT, 4=READ_DATA
    logic [2:0] state;

    always_comb begin
        if (write_pipe[0].valid) begin
            state = 3'd2;  // WRITE_RESP
        end else if (write_addr_valid || (axi_awvalid && axi_awready)) begin
            state = 3'd1;  // WRITE_WAIT
        end else if (read_pipe[0].valid) begin
            state = 3'd4;  // READ_DATA
        end else if (axi_arvalid && axi_arready) begin
            state = 3'd3;  // READ_WAIT
        end else begin
            state = 3'd0;  // IDLE
        end
    end

    // ============================================================================
    // Pipeline Stage Structure
    // ============================================================================

    // Write pipeline stages (includes address and data acceptance)
    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [3:0]            strb;
        logic [1:0]            resp;
        logic                  valid;
    } write_pipeline_t;

    // Read pipeline stages
    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [1:0]            resp;
        logic                  valid;
    } read_pipeline_t;

    // Pipeline depth is max of latency values (minimum 2 to avoid Verilator warnings)
    localparam MAX_WRITE_STAGES = (MEM_WRITE_LATENCY > 16) ? 16 : ((MEM_WRITE_LATENCY < 2) ? 2 : MEM_WRITE_LATENCY);
    localparam MAX_READ_STAGES = (MEM_READ_LATENCY > 16) ? 16 : ((MEM_READ_LATENCY < 2) ? 2 : MEM_READ_LATENCY);

    write_pipeline_t write_pipe [MAX_WRITE_STAGES];
    read_pipeline_t  read_pipe  [MAX_READ_STAGES];

    // One-port arbitration signals (only used when DUAL_PORT=0)
    logic arb_write_grant;
    logic arb_read_grant;
    logic arb_last_grant_was_write;  // For fair arbitration

    // Pipeline control signals
    logic write_pipe_busy;
    logic read_pipe_busy;
    logic write_can_accept;
    logic read_can_accept;

    // ============================================================================
    // Write Channel Logic (Pipelined)
    // ============================================================================

    // Write address and data acceptance
    logic write_addr_accepted;
    logic write_data_accepted;
    logic [ADDR_WIDTH-1:0] write_addr_reg;
    logic write_addr_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr_reg <= '0;
            write_addr_valid <= 1'b0;
        end else begin
            if (axi_awvalid && axi_awready) begin
                write_addr_reg <= axi_awaddr;
                write_addr_valid <= 1'b1;
            end else if (write_addr_valid && axi_wvalid && write_can_accept) begin
                write_addr_valid <= 1'b0;  // Clear after data arrives and pipeline accepts
            end
        end
    end

    // Write pipeline full detection
    assign write_pipe_busy = write_pipe[0].valid &&
                             (MEM_WRITE_LATENCY > 1 ? write_pipe[1].valid : 1'b0);
    assign write_can_accept = MEM_DUAL_PORT ? !write_pipe_busy : (arb_write_grant && !write_pipe_busy);

    // AXI write ready signals
    assign axi_awready = !write_addr_valid && write_can_accept;
    assign axi_wready = write_addr_valid && write_can_accept;

    // Write pipeline advancement
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MAX_WRITE_STAGES; i++) begin
                write_pipe[i].valid <= 1'b0;
                write_pipe[i].addr <= '0;
                write_pipe[i].data <= '0;
                write_pipe[i].strb <= '0;
                write_pipe[i].resp <= 2'b00;
            end
        end else begin
            // Stage 0: Accept new write transaction
            if (write_addr_valid && axi_wvalid && write_can_accept) begin
                write_pipe[0].valid <= 1'b1;
                write_pipe[0].addr <= write_addr_reg;
                write_pipe[0].data <= axi_wdata;
                write_pipe[0].strb <= axi_wstrb;
                // Check address bounds
                if (write_addr_reg < BASE_ADDR || write_addr_reg >= (BASE_ADDR + MEM_SIZE)) begin
                    write_pipe[0].resp <= 2'b10;  // SLVERR
                end else begin
                    write_pipe[0].resp <= 2'b00;  // OKAY
                end
            end else if (MEM_WRITE_LATENCY > 1 && write_pipe[1].valid) begin
                // Shift from next stage
                write_pipe[0] <= write_pipe[1];
            end else if (write_pipe[0].valid && axi_bready) begin
                // Clear when response is accepted
                write_pipe[0].valid <= 1'b0;
            end

            // Pipeline stages 1 to MAX_WRITE_STAGES-1
            for (int i = 1; i < MAX_WRITE_STAGES; i++) begin
                if (i < MEM_WRITE_LATENCY - 1) begin
                    if (i == MEM_WRITE_LATENCY - 2) begin
                        // Last latency stage: perform memory write
                        if (write_pipe[i].valid) begin
                            write_pipe[i] <= write_pipe[i];  // Hold until shifted out
                        end else if (i + 1 < MAX_WRITE_STAGES && write_pipe[i+1].valid) begin
                            write_pipe[i] <= write_pipe[i+1];
                        end else if (i == 1 && write_addr_valid && axi_wvalid && write_can_accept) begin
                            write_pipe[i].valid <= 1'b1;
                            write_pipe[i].addr <= write_addr_reg;
                            write_pipe[i].data <= axi_wdata;
                            write_pipe[i].strb <= axi_wstrb;
                            if (write_addr_reg < BASE_ADDR || write_addr_reg >= (BASE_ADDR + MEM_SIZE)) begin
                                write_pipe[i].resp <= 2'b10;
                            end else begin
                                write_pipe[i].resp <= 2'b00;
                            end
                        end else begin
                            write_pipe[i].valid <= 1'b0;
                        end
                    end else begin
                        // Intermediate stages: simple shift
                        if (i + 1 < MAX_WRITE_STAGES && write_pipe[i+1].valid) begin
                            write_pipe[i] <= write_pipe[i+1];
                        end else if (i == 1 && write_addr_valid && axi_wvalid && write_can_accept) begin
                            write_pipe[i].valid <= 1'b1;
                            write_pipe[i].addr <= write_addr_reg;
                            write_pipe[i].data <= axi_wdata;
                            write_pipe[i].strb <= axi_wstrb;
                            if (write_addr_reg < BASE_ADDR || write_addr_reg >= (BASE_ADDR + MEM_SIZE)) begin
                                write_pipe[i].resp <= 2'b10;
                            end else begin
                                write_pipe[i].resp <= 2'b00;
                            end
                        end else begin
                            write_pipe[i].valid <= 1'b0;
                        end
                    end
                end else begin
                    write_pipe[i].valid <= 1'b0;
                end
            end
        end
    end

    // Memory write operation (at appropriate pipeline stage)
    always_ff @(posedge clk) begin
        if (MEM_WRITE_LATENCY == 1) begin
            // Single cycle write: perform immediately in stage 0
            if (write_addr_valid && axi_wvalid && write_can_accept &&
                write_pipe[0].resp == 2'b00) begin
                automatic logic [31:0] base_addr = ((write_addr_reg - BASE_ADDR) & (MEM_SIZE - 1)) & ~32'h3;
                if (axi_wstrb[0]) mem[base_addr] <= axi_wdata[7:0];
                if (axi_wstrb[1]) mem[(base_addr + 1) & (MEM_SIZE-1)] <= axi_wdata[15:8];
                if (axi_wstrb[2]) mem[(base_addr + 2) & (MEM_SIZE-1)] <= axi_wdata[23:16];
                if (axi_wstrb[3]) mem[(base_addr + 3) & (MEM_SIZE-1)] <= axi_wdata[31:24];

                if (ENABLE_MEM_TRACE) begin
                    $display("[AXI_MEM WRITE] addr=0x%08x data=0x%08x strb=0x%x [bytes: %02x %02x %02x %02x]",
                             write_addr_reg, axi_wdata, axi_wstrb,
                             axi_wstrb[0] ? axi_wdata[7:0] : 8'hXX,
                             axi_wstrb[1] ? axi_wdata[15:8] : 8'hXX,
                             axi_wstrb[2] ? axi_wdata[23:16] : 8'hXX,
                             axi_wstrb[3] ? axi_wdata[31:24] : 8'hXX);
                end
            end
        end else begin
            // Multi-cycle write: perform at last pipeline stage
            if (write_pipe[MEM_WRITE_LATENCY-1].valid && write_pipe[MEM_WRITE_LATENCY-1].resp == 2'b00) begin
                automatic logic [31:0] base_addr = ((write_pipe[MEM_WRITE_LATENCY-1].addr - BASE_ADDR) & (MEM_SIZE - 1)) & ~32'h3;
                if (write_pipe[MEM_WRITE_LATENCY-1].strb[0]) mem[base_addr] <= write_pipe[MEM_WRITE_LATENCY-1].data[7:0];
                if (write_pipe[MEM_WRITE_LATENCY-1].strb[1]) mem[(base_addr + 1) & (MEM_SIZE-1)] <= write_pipe[MEM_WRITE_LATENCY-1].data[15:8];
                if (write_pipe[MEM_WRITE_LATENCY-1].strb[2]) mem[(base_addr + 2) & (MEM_SIZE-1)] <= write_pipe[MEM_WRITE_LATENCY-1].data[23:16];
                if (write_pipe[MEM_WRITE_LATENCY-1].strb[3]) mem[(base_addr + 3) & (MEM_SIZE-1)] <= write_pipe[MEM_WRITE_LATENCY-1].data[31:24];

                if (ENABLE_MEM_TRACE) begin
                    $display("[AXI_MEM WRITE] addr=0x%08x data=0x%08x strb=0x%x [bytes: %02x %02x %02x %02x]",
                             write_pipe[MEM_WRITE_LATENCY-1].addr, write_pipe[MEM_WRITE_LATENCY-1].data,
                             write_pipe[MEM_WRITE_LATENCY-1].strb,
                             write_pipe[MEM_WRITE_LATENCY-1].strb[0] ? write_pipe[MEM_WRITE_LATENCY-1].data[7:0] : 8'hXX,
                             write_pipe[MEM_WRITE_LATENCY-1].strb[1] ? write_pipe[MEM_WRITE_LATENCY-1].data[15:8] : 8'hXX,
                             write_pipe[MEM_WRITE_LATENCY-1].strb[2] ? write_pipe[MEM_WRITE_LATENCY-1].data[23:16] : 8'hXX,
                             write_pipe[MEM_WRITE_LATENCY-1].strb[3] ? write_pipe[MEM_WRITE_LATENCY-1].data[31:24] : 8'hXX);
                end
            end
        end
    end

    // Write response channel
    assign axi_bvalid = write_pipe[0].valid;
    assign axi_bresp = write_pipe[0].resp;

    // ============================================================================
    // Read Channel Logic (Pipelined)
    // ============================================================================

    // Read pipeline full detection
    assign read_pipe_busy = read_pipe[0].valid &&
                            (MEM_READ_LATENCY > 1 ? read_pipe[1].valid : 1'b0);
    assign read_can_accept = MEM_DUAL_PORT ? !read_pipe_busy : (arb_read_grant && !read_pipe_busy);

    // AXI read address ready
    assign axi_arready = read_can_accept;

    // Read pipeline advancement
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MAX_READ_STAGES; i++) begin
                read_pipe[i].valid <= 1'b0;
                read_pipe[i].addr <= '0;
                read_pipe[i].data <= '0;
                read_pipe[i].resp <= 2'b00;
            end
        end else begin
            // Stage 0: Output to AXI read data channel
            if (read_pipe[0].valid && axi_rready) begin
                if (MEM_READ_LATENCY > 1 && read_pipe[1].valid) begin
                    read_pipe[0] <= read_pipe[1];
                end else begin
                    read_pipe[0].valid <= 1'b0;
                end
            end else if (!read_pipe[0].valid && MEM_READ_LATENCY > 1 && read_pipe[1].valid) begin
                read_pipe[0] <= read_pipe[1];
            end

            // Pipeline stages 1 to MAX_READ_STAGES-1
            for (int i = 1; i < MAX_READ_STAGES; i++) begin
                if (i < MEM_READ_LATENCY - 1) begin
                    if (i + 1 < MAX_READ_STAGES && write_pipe[i+1].valid) begin
                        read_pipe[i] <= read_pipe[i+1];
                    end else if (i == 1 && axi_arvalid && read_can_accept) begin
                        read_pipe[i].valid <= 1'b1;
                        read_pipe[i].addr <= axi_araddr;
                        // Check bounds and perform read at appropriate stage
                        if (axi_araddr < BASE_ADDR || axi_araddr >= (BASE_ADDR + MEM_SIZE)) begin
                            read_pipe[i].resp <= 2'b10;  // SLVERR
                            read_pipe[i].data <= 32'hDEADBEEF;
                        end else begin
                            read_pipe[i].resp <= 2'b00;  // OKAY
                        end
                    end else begin
                        read_pipe[i].valid <= 1'b0;
                    end
                end else begin
                    read_pipe[i].valid <= 1'b0;
                end
            end

            // Stage MEM_READ_LATENCY-1: Accept new read and perform memory access
            if (MEM_READ_LATENCY == 1) begin
                if (axi_arvalid && read_can_accept) begin
                    automatic logic [31:0] word_addr = ((axi_araddr - BASE_ADDR) & (MEM_SIZE - 1)) & ~32'h3;
                    automatic logic [31:0] read_value;
                    read_pipe[0].valid <= 1'b1;
                    read_pipe[0].addr <= axi_araddr;
                    if (axi_araddr < BASE_ADDR || axi_araddr >= (BASE_ADDR + MEM_SIZE)) begin
                        read_pipe[0].resp <= 2'b10;
                        read_pipe[0].data <= 32'hDEADBEEF;
                        if (ENABLE_MEM_TRACE) begin
                            $display("[AXI READ ERROR] addr=0x%08x out of range [0x%08x - 0x%08x]", axi_araddr, BASE_ADDR, BASE_ADDR + MEM_SIZE);
                        end
                    end else begin
                        read_value = {mem[(word_addr + 3) & (MEM_SIZE-1)],
                                     mem[(word_addr + 2) & (MEM_SIZE-1)],
                                     mem[(word_addr + 1) & (MEM_SIZE-1)],
                                     mem[word_addr]};
                        read_pipe[0].resp <= 2'b00;
                        read_pipe[0].data <= read_value;
                        if (ENABLE_MEM_TRACE) begin
                            $display("[AXI_MEM READ ] addr=0x%08x data=0x%08x [bytes: %02x %02x %02x %02x]",
                                     axi_araddr, read_value,
                                     mem[word_addr],
                                     mem[(word_addr + 1) & (MEM_SIZE-1)],
                                     mem[(word_addr + 2) & (MEM_SIZE-1)],
                                     mem[(word_addr + 3) & (MEM_SIZE-1)]);
                        end
                    end
                end
            end else if (axi_arvalid && read_can_accept) begin
                automatic logic [31:0] word_addr = ((axi_araddr - BASE_ADDR) & (MEM_SIZE - 1)) & ~32'h3;
                automatic logic [31:0] read_value;
                read_pipe[MEM_READ_LATENCY-1].valid <= 1'b1;
                read_pipe[MEM_READ_LATENCY-1].addr <= axi_araddr;
                if (axi_araddr < BASE_ADDR || axi_araddr >= (BASE_ADDR + MEM_SIZE)) begin
                    read_pipe[MEM_READ_LATENCY-1].resp <= 2'b10;
                    read_pipe[MEM_READ_LATENCY-1].data <= 32'hDEADBEEF;
                end else begin
                    read_value = {mem[(word_addr + 3) & (MEM_SIZE-1)],
                                 mem[(word_addr + 2) & (MEM_SIZE-1)],
                                 mem[(word_addr + 1) & (MEM_SIZE-1)],
                                 mem[word_addr]};
                    read_pipe[MEM_READ_LATENCY-1].resp <= 2'b00;
                    read_pipe[MEM_READ_LATENCY-1].data <= read_value;
                    if (ENABLE_MEM_TRACE) begin
                        $display("[AXI_MEM READ ] addr=0x%08x data=0x%08x [bytes: %02x %02x %02x %02x]",
                                 axi_araddr, read_value,
                                 mem[word_addr],
                                 mem[(word_addr + 1) & (MEM_SIZE-1)],
                                 mem[(word_addr + 2) & (MEM_SIZE-1)],
                                 mem[(word_addr + 3) & (MEM_SIZE-1)]);
                    end
                end
            end
        end
    end

    // Read data channel outputs
    assign axi_rvalid = read_pipe[0].valid;
    assign axi_rdata = read_pipe[0].data;
    assign axi_rresp = read_pipe[0].resp;

    // ============================================================================
    // One-Port Memory Arbitration (only used when DUAL_PORT=0)
    // ============================================================================

    generate
        if (!MEM_DUAL_PORT) begin : gen_oneport_arbiter
            // Request signals
            logic write_req;
            logic read_req;

            always_comb begin
                write_req = (write_addr_valid && axi_wvalid) || axi_awvalid;
                read_req = axi_arvalid;
            end

            // Fair round-robin arbitration between read and write
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    arb_write_grant <= 1'b0;
                    arb_read_grant <= 1'b0;
                    arb_last_grant_was_write <= 1'b0;
                end else begin
                    // Default: no grant
                    arb_write_grant <= 1'b0;
                    arb_read_grant <= 1'b0;

                    if (write_req && read_req) begin
                        // Both requesting: use fair arbitration
                        if (arb_last_grant_was_write) begin
                            arb_read_grant <= 1'b1;
                            arb_last_grant_was_write <= 1'b0;
                        end else begin
                            arb_write_grant <= 1'b1;
                            arb_last_grant_was_write <= 1'b1;
                        end
                    end else if (write_req) begin
                        arb_write_grant <= 1'b1;
                        arb_last_grant_was_write <= 1'b1;
                    end else if (read_req) begin
                        arb_read_grant <= 1'b1;
                        arb_last_grant_was_write <= 1'b0;
                    end
                end
            end
        end else begin : gen_dualport
            // Dual-port: always grant both
            assign arb_write_grant = 1'b1;
            assign arb_read_grant = 1'b1;
        end
    endgenerate


    // ============================================================================
    // Testbench Utility Tasks and Functions
    // ============================================================================

    // Memory initialization task (for testbench)
    // Can be called from SystemVerilog or through DPI
    task automatic load_memory(input string filename);
        integer file_handle;
        integer bytes_read;
        integer addr;
        logic [7:0] byte_data;

        file_handle = $fopen(filename, "rb");
        if (file_handle == 0) begin
            $display("Error: Could not open file %s", filename);
            return;
        end

        addr = 0;
        while (!$feof(file_handle) && addr < MEM_SIZE) begin
            bytes_read = $fread(byte_data, file_handle);
            if (bytes_read > 0) begin
                mem[addr] = byte_data;
                addr++;
            end
        end

        $fclose(file_handle);
        $display("Loaded %0d bytes from %s", addr, filename);
    endtask

    // Direct memory write (for testbench initialization)
    task automatic write_byte(input int addr, input logic [7:0] data);
        if (addr < MEM_SIZE) begin
            mem[addr] = data;
        end
    endtask

    // Direct memory read (for testbench verification)
    function automatic logic [7:0] read_byte(input int addr);
        if (addr < MEM_SIZE) begin
            return mem[addr];
        end else begin
            return 8'hFF;
        end
    endfunction

    // Memory dump task (for debugging)
    task automatic dump_memory(input string filename, input int start_addr, input int length);
        integer file_handle;
        integer i;

        file_handle = $fopen(filename, "wb");
        if (file_handle == 0) begin
            $display("Error: Could not create file %s", filename);
            return;
        end

        for (i = start_addr; i < start_addr + length && i < MEM_SIZE; i++) begin
            $fwrite(file_handle, "%c", mem[i]);
        end

        $fclose(file_handle);
        $display("Dumped %0d bytes to %s", length, filename);
    endtask

    // DPI-C exports for memory access from C++
    export "DPI-C" function mem_write_byte;
    export "DPI-C" function mem_read_byte;

    function void mem_write_byte(input int addr, input byte data);
        // Mask address to fit within memory array (same as AXI access)
        automatic int masked_addr = addr & (MEM_SIZE - 1);
        if (masked_addr >= 0 && masked_addr < MEM_SIZE) begin
            mem[masked_addr] = data;
        end else if (ENABLE_MEM_TRACE) begin
            $display("[DPI WRITE ERROR] addr=0x%08x masked=0x%08x OUT OF RANGE", addr, masked_addr);
        end
    endfunction

    function byte mem_read_byte(input int addr);
        // Mask address to fit within memory array (same as AXI access)
        automatic int masked_addr = addr & (MEM_SIZE - 1);
        if (masked_addr >= 0 && masked_addr < MEM_SIZE) begin
            return mem[masked_addr];
        end else begin
            return 8'hFF;
        end
    endfunction

endmodule
