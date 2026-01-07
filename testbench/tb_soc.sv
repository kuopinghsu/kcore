// Testbench for RISC-V SoC with Verilator
// Instantiates SoC and external AXI memory module

module tb_soc #(
    parameter ADDR_WIDTH = 32,         // AXI address width
    parameter DATA_WIDTH = 32,         // AXI data width
    parameter MEM_SIZE = 2 * 1024 * 1024,   // Memory size in bytes (2MB for arch tests)
    parameter MEM_READ_LATENCY = 1,    // Memory read latency in cycles
    parameter MEM_WRITE_LATENCY = 1,   // Memory write latency in cycles
    parameter ENABLE_MEM_TRACE = 0,    // Enable memory transaction trace logging (0=off, 1=on)
    parameter MEM_DUAL_PORT = 1        // 1=Dual-port (best performance), 0=One-port (with arbitration)
) (
    input  logic        clk,
    input  logic        rst_n,

    // UART external interface
    output logic        uart_tx,
    input  logic        uart_rx,

    // Performance counters
    output logic [63:0] cycle_count,
    output logic [63:0] instret_count,
    output logic [63:0] stall_count,

    // Debug AXI signals (for testbench visibility)
    output logic [31:0] axi_araddr,
    output logic        axi_arvalid,
    output logic        axi_arready,
    output logic        axi_rvalid,
    output logic        axi_rready,

    // Debug CPU state
    output logic [1:0]  cpu_if_state,
    output logic [2:0]  mem_state,
    output logic        mem_op_done,
    output logic [4:0]  if_id_valid_chain,

    // Debug instruction fetch
    output logic [31:0] cpu_pc,
    output logic [31:0] cpu_fetched_instr,
    output logic [31:0] axi_rdata,
    output logic        cpu_branch_taken,
    output logic [31:0] cpu_branch_target,
    output logic        cpu_exception,
    output logic        cpu_interrupt,
    output logic [31:0] cpu_mtvec,
    output logic        cpu_is_illegal,

    // WB stage (for trace recording)
    output logic [31:0] wb_pc,
    output logic [31:0] wb_instr,
    output logic        wb_valid,
    output logic        wb_instr_retired,  // Pulse when instruction completes
    output logic [4:0]  wb_rd,
    output logic [31:0] wb_rd_data,
    output logic        wb_rd_write,
    output logic [6:0]  wb_opcode,

    // Memory operations (for trace recording)
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    output logic [31:0] mem_rdata,
    output logic        mem_write,
    output logic        mem_read,
    output logic        mem_valid,

    // CSR operations (for trace recording)
    output logic        csr_valid,
    output logic [11:0] csr_addr,
    output logic [31:0] csr_wdata,
    output logic [31:0] csr_rdata,

    // Exit signal (magic address write detection)
    output logic        exit_request,
    output logic [31:0] exit_code
);

    // AXI Memory Interface signals
    logic [31:0] mem_axi_awaddr;
    logic        mem_axi_awvalid;
    logic        mem_axi_awready;
    logic [31:0] mem_axi_wdata;
    logic [3:0]  mem_axi_wstrb;
    logic        mem_axi_wvalid;
    logic        mem_axi_wready;
    logic [1:0]  mem_axi_bresp;
    logic        mem_axi_bvalid;
    logic        mem_axi_bready;
    logic [31:0] mem_axi_araddr;
    logic        mem_axi_arvalid;
    logic        mem_axi_arready;
    logic [31:0] mem_axi_ardata;
    logic [1:0]  mem_axi_rresp;
    logic        mem_axi_rvalid;
    logic        mem_axi_rready;

    // ========================================================================
    // SoC Instance
    // ========================================================================

    soc_top #(
        .ENABLE_MEM_TRACE(ENABLE_MEM_TRACE)
    ) u_soc (
        .clk              (clk),
        .rst_n            (rst_n),
        .uart_tx          (uart_tx),
        .uart_rx          (uart_rx),
        .mem_axi_awaddr   (mem_axi_awaddr),
        .mem_axi_awvalid  (mem_axi_awvalid),
        .mem_axi_awready  (mem_axi_awready),
        .mem_axi_wdata    (mem_axi_wdata),
        .mem_axi_wstrb    (mem_axi_wstrb),
        .mem_axi_wvalid   (mem_axi_wvalid),
        .mem_axi_wready   (mem_axi_wready),
        .mem_axi_bresp    (mem_axi_bresp),
        .mem_axi_bvalid   (mem_axi_bvalid),
        .mem_axi_bready   (mem_axi_bready),
        .mem_axi_araddr   (mem_axi_araddr),
        .mem_axi_arvalid  (mem_axi_arvalid),
        .mem_axi_arready  (mem_axi_arready),
        .mem_axi_ardata   (mem_axi_ardata),
        .mem_axi_rresp    (mem_axi_rresp),
        .mem_axi_rvalid   (mem_axi_rvalid),
        .mem_axi_rready   (mem_axi_rready),
        .cycle_count      (cycle_count),
        .instret_count    (instret_count),
        .stall_count      (stall_count),
        .exit_request     (exit_request),
        .exit_code        (exit_code)
    );

    // ========================================================================
    // External AXI Memory Module (2MB with configurable read/write latency)
    // ========================================================================

    axi_memory #(
        .ADDR_WIDTH       (ADDR_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .MEM_SIZE         (MEM_SIZE),
        .MEM_READ_LATENCY (MEM_READ_LATENCY),
        .MEM_WRITE_LATENCY(MEM_WRITE_LATENCY),
        .ENABLE_MEM_TRACE (ENABLE_MEM_TRACE),
        .MEM_DUAL_PORT    (MEM_DUAL_PORT)
    ) u_memory (
        .clk           (clk),
        .rst_n         (rst_n),
        .axi_awaddr    (mem_axi_awaddr),
        .axi_awvalid   (mem_axi_awvalid),
        .axi_awready   (mem_axi_awready),
        .axi_wdata     (mem_axi_wdata),
        .axi_wstrb     (mem_axi_wstrb),
        .axi_wvalid    (mem_axi_wvalid),
        .axi_wready    (mem_axi_wready),
        .axi_bresp     (mem_axi_bresp),
        .axi_bvalid    (mem_axi_bvalid),
        .axi_bready    (mem_axi_bready),
        .axi_araddr    (mem_axi_araddr),
        .axi_arvalid   (mem_axi_arvalid),
        .axi_arready   (mem_axi_arready),
        .axi_rdata     (mem_axi_ardata),
        .axi_rresp     (mem_axi_rresp),
        .axi_rvalid    (mem_axi_rvalid),
        .axi_rready    (mem_axi_rready)
    );

    // Expose AXI signals for debugging
    assign axi_araddr = mem_axi_araddr;
    assign axi_arvalid = mem_axi_arvalid;
    assign axi_arready = mem_axi_arready;
    assign axi_rvalid = mem_axi_rvalid;
    assign axi_rready = mem_axi_rready;
    assign cpu_if_state = u_soc.u_cpu.if_state;
    assign mem_state = u_memory.state;
    assign mem_op_done = u_soc.u_cpu.mem_operation_done;
    assign if_id_valid_chain = {u_soc.u_cpu.if_id_reg.valid, u_soc.u_cpu.id_ex_reg.valid,
                                 u_soc.u_cpu.ex_mem_reg.valid, u_soc.u_cpu.mem_wb_reg.valid,
                                 u_soc.u_cpu.if_instr_valid};
    assign cpu_pc = u_soc.u_cpu.pc;
    assign cpu_fetched_instr = u_soc.u_cpu.if_instr_buf;
    assign axi_rdata = mem_axi_ardata;
    assign cpu_branch_taken = u_soc.u_cpu.ex_mem_reg.branch_taken;
    assign cpu_branch_target = u_soc.u_cpu.ex_mem_reg.branch_target;
    assign cpu_exception = u_soc.u_cpu.exception_triggered;
    assign cpu_interrupt = u_soc.u_cpu.interrupt_taken;
    assign cpu_mtvec = u_soc.u_cpu.mtvec;
    assign cpu_is_illegal = u_soc.u_cpu.is_illegal_instr;

    // WB stage signals for trace - all from WB stage (mem_wb_reg)
    // instret increments when mem_wb_reg.valid, so trace must use WB stage values
    assign wb_pc = u_soc.u_cpu.mem_wb_reg.pc;
    assign wb_instr = u_soc.u_cpu.mem_wb_reg.instr;
    // Use mem_wb_valid_reg directly to avoid struct packing issues
    assign wb_valid = u_soc.u_cpu.mem_wb_valid_reg;
    assign wb_instr_retired = u_soc.u_cpu.mem_wb_instr_retired;  // Pulse signal for trace

    // Extract rd and opcode fields from instruction to avoid struct packing issues
    assign wb_rd = wb_instr[11:7];
    assign wb_opcode = wb_instr[6:0];

    // Register write data (what gets written to regfile)
    // This mirrors the WB stage logic in kcore.sv
    assign wb_rd_data = (wb_opcode == 7'b0000011 || wb_opcode == 7'b0101111) ?  // OP_LOAD or OP_AMO
                         u_soc.u_cpu.mem_wb_reg.mem_data :
                         u_soc.u_cpu.mem_wb_reg.alu_result;
    assign wb_rd_write = u_soc.u_cpu.mem_wb_valid_reg && (wb_rd != 5'd0);

    // Memory operation signals - track completed operations at WB stage
    // Extract opcode from wb_instr to avoid struct packing issues
    logic [6:0] wb_mem_opcode;
    assign wb_mem_opcode = wb_instr[6:0];
    assign mem_addr = u_soc.u_cpu.mem_wb_reg.alu_result;  // For load/store, alu_result is the address
    assign mem_wdata = u_soc.u_cpu.mem_wb_reg.store_data;  // Store data saved in pipeline
    assign mem_rdata = u_soc.u_cpu.mem_wb_reg.mem_data;  // Load data
    assign mem_write = (wb_mem_opcode == 7'b0100011) && u_soc.u_cpu.mem_wb_valid_reg;  // OP_STORE
    assign mem_read = (wb_mem_opcode == 7'b0000011) && u_soc.u_cpu.mem_wb_valid_reg;  // OP_LOAD
    assign mem_valid = u_soc.u_cpu.mem_wb_valid_reg &&
                       ((wb_mem_opcode == 7'b0000011) ||  // LOAD
                        (wb_mem_opcode == 7'b0100011));   // STORE

    // CSR operation signals - track CSR accesses at WB stage
    logic [2:0] wb_funct3;
    logic [11:0] wb_csr_addr;
    assign wb_funct3 = wb_instr[14:12];
    assign wb_csr_addr = u_soc.u_cpu.mem_wb_reg.csr_addr;
    assign csr_valid = u_soc.u_cpu.mem_wb_valid_reg &&
                       (wb_mem_opcode == 7'b1110011) &&  // OP_SYSTEM
                       (wb_funct3 != 3'b000);  // Not ECALL/EBREAK/MRET
    assign csr_addr = wb_csr_addr;
    // For CSR operations, wb_rd_data contains the old CSR value (what was read)
    assign csr_rdata = wb_rd_data;
    // CSR write data was saved in the pipeline
    assign csr_wdata = u_soc.u_cpu.mem_wb_reg.csr_wdata_saved;

    // Exit detection is now handled in soc_top module

endmodule
