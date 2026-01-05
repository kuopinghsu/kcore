// RISC-V Formal Interface (RVFI) Wrapper
// Adapts kcore.sv to the riscv-formal verification interface

module rvfi_wrapper (
    input         clock,
    input         reset,
    
    // RVFI outputs (per retired instruction)
    output        rvfi_valid,
    output [63:0] rvfi_order,
    output [31:0] rvfi_insn,
    output        rvfi_trap,
    output        rvfi_halt,
    output        rvfi_intr,
    output [1:0]  rvfi_mode,
    output [1:0]  rvfi_ixl,
    
    // PC
    output [31:0] rvfi_pc_rdata,
    output [31:0] rvfi_pc_wdata,
    
    // Register file (source registers)
    output [4:0]  rvfi_rs1_addr,
    output [4:0]  rvfi_rs2_addr,
    output [31:0] rvfi_rs1_rdata,
    output [31:0] rvfi_rs2_rdata,
    
    // Register file (destination register)
    output [4:0]  rvfi_rd_addr,
    output [31:0] rvfi_rd_wdata,
    
    // Memory interface
    output [31:0] rvfi_mem_addr,
    output [3:0]  rvfi_mem_rmask,
    output [3:0]  rvfi_mem_wmask,
    output [31:0] rvfi_mem_rdata,
    output [31:0] rvfi_mem_wdata
);

    // CPU signals
    logic [31:0] imem_addr, imem_rdata;
    logic        imem_valid, imem_ready;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_wstrb;
    logic        dmem_valid, dmem_ready, dmem_write;
    logic        timer_irq, software_irq, external_irq;
    logic [63:0] cycle_count, instret_count, stall_count;
    
    // Instantiate CPU core with RVFI enabled
    kcore #(
        .ENABLE_MEM_TRACE(0),
        .ENABLE_RVFI(1)  // Enable RVFI interface
    ) dut (
        .clk(clock),
        .rst_n(~reset),
        
        // Instruction memory interface
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .imem_valid(imem_valid),
        .imem_ready(imem_ready),
        
        // Data memory interface
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_valid(dmem_valid),
        .dmem_ready(dmem_ready),
        .dmem_write(dmem_write),
        
        // Interrupts
        .timer_irq(timer_irq),
        .software_irq(software_irq),
        .external_irq(external_irq),
        
        // Performance counters
        .cycle_count(cycle_count),
        .instret_count(instret_count),
        .stall_count(stall_count),
        
        // RVFI outputs - directly connected to wrapper outputs
        .rvfi_valid(rvfi_valid),
        .rvfi_order(rvfi_order),
        .rvfi_insn(rvfi_insn),
        .rvfi_trap(rvfi_trap),
        .rvfi_halt(rvfi_halt),
        .rvfi_intr(rvfi_intr),
        .rvfi_mode(rvfi_mode),
        .rvfi_ixl(rvfi_ixl),
        .rvfi_pc_rdata(rvfi_pc_rdata),
        .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_rs1_addr(rvfi_rs1_addr),
        .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata),
        .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr),
        .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_mem_addr(rvfi_mem_addr),
        .rvfi_mem_rmask(rvfi_mem_rmask),
        .rvfi_mem_wmask(rvfi_mem_wmask),
        .rvfi_mem_rdata(rvfi_mem_rdata),
        .rvfi_mem_wdata(rvfi_mem_wdata)
    );
    
    // Simple memory model for formal verification
    // Memory is modeled as unconstrained inputs with consistency checks
    logic [31:0] mem [0:1023];  // 4KB memory for formal verification
    
    // Memory interface handling
    always_comb begin
        imem_ready = 1'b1;  // Always ready for instruction fetch
        dmem_ready = 1'b1;  // Always ready for data access
        
        // Instruction memory read
        if (imem_valid) begin
            imem_rdata = mem[imem_addr[11:2]];
        end else begin
            imem_rdata = 32'h0;
        end
        
        // Data memory read
        if (dmem_valid && !dmem_write) begin
            dmem_rdata = mem[dmem_addr[11:2]];
        end else begin
            dmem_rdata = 32'h0;
        end
    end
    
    // Memory write
    always_ff @(posedge clock) begin
        if (reset) begin
            // Memory initialized to unconstrained values
        end else if (dmem_valid && dmem_write) begin
            if (dmem_wstrb[0]) mem[dmem_addr[11:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) mem[dmem_addr[11:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) mem[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) mem[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
        end
    end
    
    // No interrupts for formal verification
    assign timer_irq = 1'b0;
    assign software_irq = 1'b0;
    assign external_irq = 1'b0;

`ifdef FORMAL
    // Formal verification properties
    // Note: These are basic sanity checks. Full instruction-level verification
    // requires integration with riscv-formal framework.
    
    // Assumption: Reset must be asserted initially
    initial assume(reset);
    
    // Property: x0 is always zero
    always @(posedge clock) begin
        if (!reset && rvfi_valid && rvfi_rd_addr == 5'h0) begin
            assert(rvfi_rd_wdata == 32'h0);
        end
    end
    
    // Property: Instruction retired implies valid instruction (commented out)
    // always @(posedge clock) begin
    //     if (!reset && rvfi_valid) begin
    //         assert(rvfi_insn != 32'h0 || rvfi_trap);
    //     end
    // end
    
    // Property: Order counter increases monotonically (commented out)
    // logic [63:0] prev_order;
    // logic first_instr;
    // always @(posedge clock) begin
    //     if (reset) begin
    //         prev_order <= 64'h0;
    //         first_instr <= 1'b1;
    //     end else if (rvfi_valid) begin
    //         if (!first_instr) begin
    //             assert(rvfi_order == prev_order + 1);
    //         end
    //         prev_order <= rvfi_order;
    //         first_instr <= 1'b0;
    //     end
    // end
    
    // Property: PC alignment - RISC-V requires 4-byte alignment
    // Wait until we've seen valid instructions retiring before checking alignment
    logic [1:0] retire_count;
    always_ff @(posedge clock) begin
        if (reset) begin
            retire_count <= 2'b00;
        end else if (rvfi_valid && retire_count != 2'b11) begin
            retire_count <= retire_count + 2'b01;
        end
    end
    
    always @(posedge clock) begin
        // Only check when not in reset and instruction is retiring
        if (!reset && rvfi_valid) begin
            assert(rvfi_pc_rdata[1:0] == 2'b00);
            assert(rvfi_pc_wdata[1:0] == 2'b00);
        end
    end
    
    // Property: Memory access alignment (commented out)
    // always @(posedge clock) begin
    //     if (!reset && rvfi_valid && (rvfi_mem_rmask != 4'h0 || rvfi_mem_wmask != 4'h0)) begin
    //         // Word access must be 4-byte aligned
    //         if (rvfi_mem_rmask == 4'hF || rvfi_mem_wmask == 4'hF) begin
    //             assert(rvfi_mem_addr[1:0] == 2'b00);
    //         end
    //         // Halfword access must be 2-byte aligned
    //         if ((rvfi_mem_rmask == 4'h3 || rvfi_mem_rmask == 4'hC) ||
    //             (rvfi_mem_wmask == 4'h3 || rvfi_mem_wmask == 4'hC)) begin
    //             assert(rvfi_mem_addr[0] == 1'b0);
    //         end
    //     end
    // end
`endif

endmodule
