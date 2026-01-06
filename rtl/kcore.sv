// RISC-V 32-bit IMA 5-Stage Pipelined Processor Core
// Supports RV32IMA (Base, Multiply/Divide, Atomic)

module kcore #(
    parameter ENABLE_MEM_TRACE = 0,  // Enable memory transaction trace logging (0=off, 1=on)
    parameter ENABLE_RVFI = 0        // Enable RISC-V Formal Interface (0=off, 1=on)
) (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction port (simple interface)
    output logic        imem_valid,
    input  logic        imem_ready,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic        imem_flush,  // Signal that current IMEM fetch should be discarded

    // Data port (simple interface)
    output logic        dmem_valid,
    input  logic        dmem_ready,
    output logic        dmem_write,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wstrb,
    input  logic [31:0] dmem_rdata,

    // Interrupt inputs
    input  logic        timer_irq,
    input  logic        software_irq,
    input  logic        external_irq,

    // Performance counters output
    output logic [63:0] cycle_count,
    output logic [63:0] instret_count,
    output logic [63:0] stall_count,

    // RISC-V Formal Interface (RVFI) - enabled when ENABLE_RVFI=1
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic        rvfi_trap,
    output logic        rvfi_halt,
    output logic        rvfi_intr,
    output logic [1:0]  rvfi_mode,
    output logic [1:0]  rvfi_ixl,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [4:0]  rvfi_rs1_addr,
    output logic [4:0]  rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [4:0]  rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [3:0]  rvfi_mem_rmask,
    output logic [3:0]  rvfi_mem_wmask,
    output logic [31:0] rvfi_mem_rdata,
    output logic [31:0] rvfi_mem_wdata
);

    // Pipeline stage registers
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic        valid;
    } if_id_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rd;
        logic [31:0] imm;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [6:0]  opcode;
        logic [2:0]  funct3;
        logic [6:0]  funct7;
        logic        valid;
    } id_ex_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] alu_result;
        logic [31:0] rs2_data;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [31:0] rs1_data;
        logic [4:0]  rd;
        logic [6:0]  opcode;
        logic [2:0]  funct3;
        logic [6:0]  funct7;
        logic        valid;
        logic        branch_taken;
        logic [31:0] branch_target;
    } ex_mem_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] alu_result;
        logic [31:0] mem_data;
        logic [31:0] store_data;  // For trace: store value written to memory
        logic [11:0] csr_addr;    // For trace: CSR address accessed
        logic [31:0] csr_wdata_saved;   // For trace: CSR write data
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [4:0]  rd;
        logic [6:0]  opcode;
        logic        valid;
    } mem_wb_t;

    if_id_t  if_id_reg, if_id_next;
    id_ex_t  id_ex_reg, id_ex_next;
    ex_mem_t ex_mem_reg, ex_mem_next;
    mem_wb_t mem_wb_reg, mem_wb_next;

    // Separate valid signals to avoid Verilator packed struct issues
    logic mem_wb_valid_reg;
    logic mem_wb_instr_retired;  // One-cycle pulse when instruction retires to WB

    // ========================================================================
    // CSR Module Instance
    // ========================================================================

    // Determine interrupt code based on which interrupt is pending (priority: software > timer > external)
    logic [31:0] interrupt_code;
    always_comb begin
        if (software_irq)
            interrupt_code = {1'b1, 31'd3};  // Machine software interrupt
        else if (timer_irq)
            interrupt_code = {1'b1, 31'd7};  // Machine timer interrupt
        else if (external_irq)
            interrupt_code = {1'b1, 31'd11}; // Machine external interrupt
        else
            interrupt_code = {1'b1, 31'd0};  // Default (shouldn't happen)
    end

    csr u_csr (
        .clk                (clk),
        .rst_n              (rst_n),
        .csr_read           (csr_read),
        .csr_write          (csr_write),
        .csr_addr           (csr_addr),
        .csr_wdata          (csr_wdata),
        .csr_op             (csr_op),
        .csr_rdata          (csr_rdata),
        .csr_illegal        (csr_illegal),
        .exception_trigger  (exception_triggered),
        .exception_pc       (exception_pc),
        .exception_code     (exception_code),
        .exception_tval     (exception_tval),
        .interrupt_trigger  (interrupt_taken),
        .interrupt_pc       (interrupt_pc_saved),  // Use saved PC, not current pc
        .interrupt_code     (interrupt_code),  // Dynamic interrupt code
        .mret_trigger       (mret_detected),   // MRET instruction detected in WB stage
        .timer_irq          (timer_irq),
        .software_irq       (software_irq),
        .external_irq       (external_irq),
        .interrupt_pending  (interrupt_pending),
        .count_cycle        (1'b1),  // Count every cycle
        .count_instret      (mem_wb_reg.valid),  // Count when instruction retires
        .mstatus            (mstatus),
        .mtvec              (mtvec),
        .mepc               (mepc),
        .mie                (mie),
        .mip                (mip)
    );

    // Register file
    logic [31:0] regfile [32];

    // PC and control signals
    logic [31:0] pc, pc_next;
    logic        stall_if, stall_id, stall_ex, stall_mem;
    logic        flush_if, flush_id, flush_ex;

    // CSR interface signals
    logic        csr_read, csr_write;
    logic [11:0] csr_addr;
    logic [31:0] csr_wdata;
    logic [2:0]  csr_op;
    logic [31:0] csr_rdata;
    logic        csr_illegal;

    // CSR outputs from module
    logic [31:0] mstatus, mtvec, mepc, mie, mip;
    logic        interrupt_pending;

    // Performance counters (exposed from CSR module)
    logic [63:0] mcycle, minstret;

    // Instruction fetch state machine
    typedef enum logic [1:0] {
        IF_IDLE,
        IF_WAIT
    } if_state_t;
    if_state_t if_state, if_state_next;
    logic        if_ignore_next_ready;  // Ignore next imem_ready (for flushed fetches)

    logic [31:0] if_instr_buf;
    logic        if_instr_valid;

    // Memory access state machine
    typedef enum logic [2:0] {
        MEM_IDLE,
        MEM_READ_WAIT,
        MEM_WRITE_WAIT,
        MEM_AMO_READ,
        MEM_AMO_WRITE
    } mem_state_t;
    mem_state_t mem_state, mem_state_next;

    logic [31:0] mem_read_data;
    logic        mem_operation_done;
    logic [31:0] amo_read_data;  // Store loaded value for atomic operations
    logic [31:0] amo_result;     // Computed result for atomic write

    // Forwarding logic
    logic [31:0] fwd_rs1_data, fwd_rs2_data;
    logic [1:0]  fwd_rs1_sel, fwd_rs2_sel;

    // Branch prediction
    logic        branch_predict_taken;
    logic [31:0] branch_predict_target;

    // Exception handling
    logic        exception_triggered;
    logic [31:0] exception_code;
    logic [31:0] exception_pc;
    logic [31:0] exception_tval;

    // Exception detection signals
    logic        illegal_instr_exception;
    logic        instr_misaligned_exception;
    logic        load_misaligned_exception;
    logic        store_misaligned_exception;
    logic        ecall_exception;
    logic        ebreak_exception;

    // Exception codes (RISC-V standard)
    localparam CAUSE_INSTR_MISALIGNED = 32'd0;
    localparam CAUSE_ILLEGAL_INSTR = 32'd2;
    localparam CAUSE_BREAKPOINT = 32'd3;
    localparam CAUSE_LOAD_MISALIGNED = 32'd4;
    localparam CAUSE_STORE_MISALIGNED = 32'd6;
    localparam CAUSE_ECALL_M = 32'd11;  // Environment call from M-mode

    // Interrupt handling (interrupt_pending comes from CSR module)
    logic        interrupt_taken;
    logic        interrupt_latched;  // Latched interrupt to hold until trap taken
    logic [31:0] interrupt_pc_saved;  // PC value when interrupt is latched

    // Performance counters
    logic        pipeline_stall;

    // Opcodes
    localparam OP_LOAD     = 7'b0000011;
    localparam OP_STORE    = 7'b0100011;
    localparam OP_BRANCH   = 7'b1100011;
    localparam OP_JAL      = 7'b1101111;
    localparam OP_JALR     = 7'b1100111;
    localparam OP_IMM      = 7'b0010011;
    localparam OP_REG      = 7'b0110011;
    localparam OP_LUI      = 7'b0110111;
    localparam OP_AUIPC    = 7'b0010111;
    localparam OP_SYSTEM   = 7'b1110011;
    localparam OP_AMO      = 7'b0101111;
    localparam OP_FENCE    = 7'b0001111;

    // ========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h8000_0000;  // Boot address
            if_state <= IF_IDLE;
            if_instr_buf <= 32'd0;
            if_ignore_next_ready <= 1'b0;
        end else begin
            if (!stall_if) begin
                pc <= pc_next;
            end
            if_state <= if_state_next;

            // Set flag to ignore next imem_ready if flush happens during a fetch
            if ((if_state == IF_WAIT) && (flush_if || interrupt_taken || exception_triggered)) begin
                if_ignore_next_ready <= 1'b1;
            end else if (if_ignore_next_ready && imem_ready) begin
                // Clear flag after ignoring one imem_ready
                if_ignore_next_ready <= 1'b0;
            end

            // Clear instruction buffer on flush to prevent stale data
            if (flush_if) begin
                if_instr_buf <= 32'd0;
            // Capture instruction when ready is asserted (only if not flushing and not ignoring)
            end else if (if_state == IF_WAIT && imem_ready && !if_ignore_next_ready) begin
                if_instr_buf <= imem_rdata;
            end
        end
    end

    always_comb begin
        if_state_next = if_state;

        case (if_state)
            IF_IDLE: begin
                // Start new fetch when not stalled
                // After a flush (branch/exception/interrupt), we should start fetching from the new PC
                // Allow IF to proceed even when MEM is busy - independent instruction fetch
                if (!stall_id) begin
                    if_state_next = IF_WAIT;
                end
            end
            IF_WAIT: begin
                // Abort current fetch on flush OR if interrupt/exception is triggered
                if (flush_if || interrupt_taken || exception_triggered) begin
                    // Abort current fetch, will restart from new PC in next cycle
                    if_state_next = IF_IDLE;
                end else if (imem_ready) begin
                    if_state_next = IF_IDLE;
                end
            end
            default: if_state_next = IF_IDLE;
        endcase
    end

    // Instruction memory interface
    assign imem_addr = pc;
    assign imem_valid = (if_state == IF_WAIT);
    assign imem_flush = flush_if;  // Expose flush signal to arbiter
    // Prevent instruction from being valid if any control flow change is happening
    // ALSO reject if we're ignoring this ready (for flushed fetches)
    assign if_instr_valid = (if_state == IF_WAIT) && imem_ready && !flush_if && !interrupt_taken && !exception_triggered && !if_ignore_next_ready;

    // PC calculation
    always_comb begin
        pc_next = pc;

        if (mret_detected) begin
            // MRET restores PC from mepc
            pc_next = {mepc[31:2], 2'b00};  // mepc must be 4-byte aligned
        end else if (exception_triggered) begin
            pc_next = mtvec;
        end else if (interrupt_taken) begin
            pc_next = mtvec;
        end else if (take_branch) begin
            pc_next = branch_target;  // Use current branch_target for all taken branches
        end else if (if_id_reg.valid && !stall_ex && !flush_ex &&
                     // Don't increment PC if an unconditional jump is in ID stage (will be resolved in next cycle)
                     !(decoded_opcode == OP_JAL || decoded_opcode == OP_JALR)) begin
            // Increment PC when instruction advances from ID to EX stage
            // This ensures PC only increments once per instruction consumed by the pipeline
            pc_next = pc + 32'd4;
        end
    end

    // ========================================================================
    // IF/ID Pipeline Register
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_reg <= '0;
        end else begin
            if (flush_id) begin
                if_id_reg <= '0;  // Clear entire register on flush, not just valid bit
            end else if (!stall_id) begin
                if_id_reg <= if_id_next;
            end
        end
    end

    always_comb begin
        if_id_next = '0;  // Default to all zeros
        if_id_next.valid = if_instr_valid;

        if (if_instr_valid) begin
            // Save the PC of the fetched instruction (current PC, not next PC)
            if_id_next.pc = pc;
            // Use imem_rdata directly since it's valid when if_instr_valid is true
            if_id_next.instr = imem_rdata;
        end
    end

    // ========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // ========================================================================

    // Instruction decode
    // No compressed instruction support - use instruction directly
    logic [31:0] decoded_instr;
    assign decoded_instr = if_id_reg.instr;

    // Instruction decode fields
    logic [4:0]  decoded_rs1, decoded_rs2, decoded_rd;
    logic [6:0]  decoded_opcode, decoded_funct7;
    logic [2:0]  decoded_funct3;
    logic [31:0] decoded_imm;
    logic        is_illegal_instr;

    assign decoded_opcode = decoded_instr[6:0];
    assign decoded_rd = decoded_instr[11:7];
    assign decoded_funct3 = decoded_instr[14:12];
    assign decoded_rs1 = decoded_instr[19:15];
    assign decoded_rs2 = decoded_instr[24:20];
    assign decoded_funct7 = decoded_instr[31:25];

    // Immediate generation
    always_comb begin
        decoded_imm = 32'd0;
        case (decoded_opcode)
            OP_IMM, OP_LOAD, OP_JALR, OP_SYSTEM: begin
                decoded_imm = {{20{decoded_instr[31]}}, decoded_instr[31:20]};
            end
            OP_STORE: begin
                decoded_imm = {{20{decoded_instr[31]}}, decoded_instr[31:25], decoded_instr[11:7]};
            end
            OP_BRANCH: begin
                decoded_imm = {{20{decoded_instr[31]}}, decoded_instr[31], decoded_instr[7], decoded_instr[30:25], decoded_instr[11:8], 1'b0};
            end
            OP_LUI, OP_AUIPC: begin
                decoded_imm = {decoded_instr[31:12], 12'd0};
            end
            OP_JAL: begin
                decoded_imm = {{11{decoded_instr[31]}}, decoded_instr[31], decoded_instr[19:12], decoded_instr[20], decoded_instr[30:21], 1'b0};
            end
            default: decoded_imm = 32'd0;
        endcase
    end

    // Check for illegal instructions
    always_comb begin
        is_illegal_instr = 1'b0;

        begin
            case (decoded_opcode)
                OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL, OP_JALR,
                OP_IMM, OP_REG, OP_LUI, OP_AUIPC, OP_SYSTEM,
                OP_AMO, OP_FENCE: begin
                    // Valid opcode, could add more detailed checking
                end
                default: is_illegal_instr = 1'b1;
            endcase
        end
    end

    // Register file read
    logic [31:0] rf_rs1_data, rf_rs2_data;
    assign rf_rs1_data = (decoded_rs1 == 5'd0) ? 32'd0 : regfile[decoded_rs1];
    assign rf_rs2_data = (decoded_rs2 == 5'd0) ? 32'd0 : regfile[decoded_rs2];

    // ========================================================================
    // ID/EX Pipeline Register
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_reg <= '0;
        end else begin
            if (flush_ex) begin
                id_ex_reg <= '0;  // Clear entire register on flush
            end else if (!stall_ex) begin
                id_ex_reg <= id_ex_next;
            end
        end
    end

    always_comb begin
        id_ex_next.pc = if_id_reg.pc;
        id_ex_next.instr = decoded_instr;
        id_ex_next.rs1 = decoded_rs1;
        id_ex_next.rs2 = decoded_rs2;
        id_ex_next.rd = decoded_rd;
        id_ex_next.imm = decoded_imm;
        id_ex_next.rs1_data = rf_rs1_data;
        id_ex_next.rs2_data = rf_rs2_data;
        id_ex_next.opcode = decoded_opcode;
        id_ex_next.funct3 = decoded_funct3;
        id_ex_next.funct7 = decoded_funct7;
        id_ex_next.valid = if_id_reg.valid && !is_illegal_instr;
    end

    // ========================================================================
    // STAGE 3: EXECUTE (EX)
    // ========================================================================

    // CSR read/write control
    always_comb begin
        csr_read = 1'b0;
        csr_write = 1'b0;
        csr_addr = id_ex_reg.imm[11:0];  // CSR address from immediate field
        csr_wdata = 32'd0;
        csr_op = id_ex_reg.funct3;

        if (id_ex_reg.valid && id_ex_reg.opcode == OP_SYSTEM) begin
            case (id_ex_reg.funct3)
                3'b001: begin  // CSRRW
                    csr_read = 1'b1;
                    csr_write = 1'b1;
                    csr_wdata = fwd_rs1_data;
                end
                3'b010: begin  // CSRRS
                    csr_read = 1'b1;
                    csr_write = (id_ex_reg.rs1 != 5'd0);  // Only write if rs1 != x0
                    csr_wdata = csr_rdata | fwd_rs1_data;
                end
                3'b011: begin  // CSRRC
                    csr_read = 1'b1;
                    csr_write = (id_ex_reg.rs1 != 5'd0);  // Only write if rs1 != x0
                    csr_wdata = csr_rdata & ~fwd_rs1_data;
                end
                3'b101: begin  // CSRRWI
                    csr_read = 1'b1;
                    csr_write = 1'b1;
                    csr_wdata = {27'd0, id_ex_reg.rs1};  // Zero-extend uimm
                end
                3'b110: begin  // CSRRSI
                    csr_read = 1'b1;
                    csr_write = (id_ex_reg.rs1 != 5'd0);  // Only write if uimm != 0
                    csr_wdata = csr_rdata | {27'd0, id_ex_reg.rs1};
                end
                3'b111: begin  // CSRRCI
                    csr_read = 1'b1;
                    csr_write = (id_ex_reg.rs1 != 5'd0);  // Only write if uimm != 0
                    csr_wdata = csr_rdata & ~{27'd0, id_ex_reg.rs1};
                end
                default: begin
                    csr_read = 1'b0;
                    csr_write = 1'b0;
                end
            endcase
        end
    end

    // Forwarding logic
    always_comb begin
        // Forward from MEM stage
        if (ex_mem_reg.valid && ex_mem_reg.rd != 5'd0 && ex_mem_reg.rd == id_ex_reg.rs1) begin
            fwd_rs1_sel = 2'd1;
            fwd_rs1_data = ex_mem_reg.alu_result;
        end
        // Forward from WB stage
        else if (mem_wb_reg.valid && mem_wb_reg.rd != 5'd0 && mem_wb_reg.rd == id_ex_reg.rs1) begin
            fwd_rs1_sel = 2'd2;
            if (mem_wb_reg.opcode == OP_LOAD) begin
                fwd_rs1_data = mem_wb_reg.mem_data;
            end else begin
                fwd_rs1_data = mem_wb_reg.alu_result;
            end
        end else begin
            fwd_rs1_sel = 2'd0;
            fwd_rs1_data = id_ex_reg.rs1_data;
        end

        // RS2 forwarding
        if (ex_mem_reg.valid && ex_mem_reg.rd != 5'd0 && ex_mem_reg.rd == id_ex_reg.rs2) begin
            fwd_rs2_sel = 2'd1;
            fwd_rs2_data = ex_mem_reg.alu_result;
        end else if (mem_wb_reg.valid && mem_wb_reg.rd != 5'd0 && mem_wb_reg.rd == id_ex_reg.rs2) begin
            fwd_rs2_sel = 2'd2;
            if (mem_wb_reg.opcode == OP_LOAD) begin
                fwd_rs2_data = mem_wb_reg.mem_data;
            end else begin
                fwd_rs2_data = mem_wb_reg.alu_result;
            end
        end else begin
            fwd_rs2_sel = 2'd0;
            fwd_rs2_data = id_ex_reg.rs2_data;
        end
    end

    // ALU
    logic [31:0] alu_result;
    logic [31:0] alu_op1, alu_op2;
    logic        alu_branch_taken;

    assign alu_op1 = fwd_rs1_data;
    assign alu_op2 = (id_ex_reg.opcode == OP_REG || id_ex_reg.opcode == OP_BRANCH || id_ex_reg.opcode == OP_AMO) ? fwd_rs2_data : id_ex_reg.imm;

    // M extension multiply/divide results (with proper sign/zero extension)
    logic [63:0] result_mul;
    logic [63:0] result_mulu;
    logic [63:0] result_mulsu;
    logic [31:0] result_div;
    logic [31:0] result_divu;
    logic [31:0] result_rem;
    logic [31:0] result_remu;

    assign result_mul[63:0]    = $signed  ({{32{alu_op1[31]}}, alu_op1[31:0]}) *
                                 $signed  ({{32{alu_op2[31]}}, alu_op2[31:0]});
    assign result_mulu[63:0]   = $unsigned({{32{1'b0}},        alu_op1[31:0]}) *
                                 $unsigned({{32{1'b0}},        alu_op2[31:0]});
    assign result_mulsu[63:0]  = $signed  ({{32{alu_op1[31]}}, alu_op1[31:0]}) *
                                 $unsigned({{32{1'b0}},        alu_op2[31:0]});

    // Division and remainder with proper edge case handling
    // The result of divided by zero and (-MAX / -1) cannot be represented in twos complement.
    assign result_div[31:0]    = (alu_op2 == 32'h00000000) ? 32'hffffffff :
                                 ((alu_op1 == 32'h80000000) && (alu_op2 == 32'hffffffff)) ?
                                 32'h80000000 :
                                 $signed  ($signed  (alu_op1) / $signed  (alu_op2));
    assign result_divu[31:0]   = (alu_op2 == 32'h00000000) ? 32'hffffffff :
                                 $unsigned($unsigned(alu_op1) / $unsigned(alu_op2));
    assign result_rem[31:0]    = (alu_op2 == 32'h00000000) ? alu_op1 :
                                 ((alu_op1 == 32'h80000000) && (alu_op2 == 32'hffffffff)) ?
                                 32'h00000000 :
                                 $signed  ($signed  (alu_op1) % $signed  (alu_op2));
    assign result_remu[31:0]   = (alu_op2 == 32'h00000000) ? alu_op1 :
                                 $unsigned($unsigned(alu_op1) % $unsigned(alu_op2));

    always_comb begin
        alu_result = 32'd0;
        alu_branch_taken = 1'b0;

        case (id_ex_reg.opcode)
            OP_LUI: begin
                alu_result = id_ex_reg.imm;
            end
            OP_AUIPC: begin
                alu_result = id_ex_reg.pc + id_ex_reg.imm;
            end
            OP_JAL: begin
                alu_result = id_ex_reg.pc + 32'd4;
            end
            OP_JALR: begin
                alu_result = id_ex_reg.pc + 32'd4;
            end
            OP_BRANCH: begin
                case (id_ex_reg.funct3)
                    3'b000: alu_branch_taken = (alu_op1 == alu_op2);  // BEQ
                    3'b001: alu_branch_taken = (alu_op1 != alu_op2);  // BNE
                    3'b100: alu_branch_taken = ($signed(alu_op1) < $signed(alu_op2));  // BLT
                    3'b101: alu_branch_taken = ($signed(alu_op1) >= $signed(alu_op2));  // BGE
                    3'b110: alu_branch_taken = (alu_op1 < alu_op2);  // BLTU
                    3'b111: alu_branch_taken = (alu_op1 >= alu_op2);  // BGEU
                    default: alu_branch_taken = 1'b0;
                endcase
            end
            OP_LOAD, OP_STORE: begin
                alu_result = alu_op1 + alu_op2;
            end
            OP_IMM, OP_REG: begin
                case (id_ex_reg.funct3)
                    3'b000: begin  // ADD/SUB
                        if (id_ex_reg.opcode == OP_REG && id_ex_reg.funct7[5]) begin
                            alu_result = alu_op1 - alu_op2;
                        end else begin
                            alu_result = alu_op1 + alu_op2;
                        end
                    end
                    3'b001: alu_result = alu_op1 << alu_op2[4:0];  // SLL
                    3'b010: alu_result = ($signed(alu_op1) < $signed(alu_op2)) ? 32'd1 : 32'd0;  // SLT
                    3'b011: alu_result = (alu_op1 < alu_op2) ? 32'd1 : 32'd0;  // SLTU
                    3'b100: alu_result = alu_op1 ^ alu_op2;  // XOR
                    3'b101: begin  // SRL/SRA
                        if (id_ex_reg.funct7[5]) begin
                            alu_result = $signed(alu_op1) >>> alu_op2[4:0];
                        end else begin
                            alu_result = alu_op1 >> alu_op2[4:0];
                        end
                    end
                    3'b110: alu_result = alu_op1 | alu_op2;  // OR
                    3'b111: alu_result = alu_op1 & alu_op2;  // AND
                endcase

                // M extension (multiply/divide)
                if (id_ex_reg.opcode == OP_REG && id_ex_reg.funct7 == 7'b0000001) begin
                    case (id_ex_reg.funct3)
                        3'b000: alu_result = result_mul[31:0];   // MUL
                        3'b001: alu_result = result_mul[63:32];  // MULH
                        3'b010: alu_result = result_mulsu[63:32]; // MULHSU
                        3'b011: alu_result = result_mulu[63:32]; // MULHU
                        3'b100: alu_result = result_div;         // DIV
                        3'b101: alu_result = result_divu;        // DIVU
                        3'b110: alu_result = result_rem;         // REM
                        3'b111: alu_result = result_remu;        // REMU
                    endcase
                end
            end
            OP_SYSTEM: begin
                // CSR operations - read CSR value
                case (id_ex_reg.funct3)
                    3'b001, 3'b010, 3'b011: begin  // CSRRW, CSRRS, CSRRC
                        alu_result = csr_rdata;  // Return old CSR value
                    end
                    3'b101, 3'b110, 3'b111: begin  // CSRRWI, CSRRSI, CSRRCI
                        alu_result = csr_rdata;  // Return old CSR value
                    end
                    default: alu_result = csr_rdata;
                endcase
            end
            OP_AMO: begin
                // Atomic operations - address calculation
                // For atomics, rs1 contains the address
                alu_result = alu_op1;  // Address for memory access
            end
            default: alu_result = 32'd0;
        endcase
    end

    // Branch target calculation
    logic [31:0] branch_target;
    logic [31:0] target_addr;

    always_comb begin
        if (id_ex_reg.opcode == OP_JAL) begin
            target_addr = id_ex_reg.pc + id_ex_reg.imm;
        end else if (id_ex_reg.opcode == OP_JALR) begin
            target_addr = alu_op1 + id_ex_reg.imm;
        end else begin
            target_addr = id_ex_reg.pc + id_ex_reg.imm;  // Default for branch
        end
    end

    always_comb begin
        branch_target = {target_addr[31:1], 1'b0};  // Force 2-byte alignment (mask bit [0])
    end

    // synthesis translate_off
    // Debug: DPI-C export function to dump registers (can be called from testbench)
    export "DPI-C" task dump_registers;

    task dump_registers(input int unsigned dump_pc);
        $display("=== Register Dump at PC=0x%08h ===", dump_pc);
        $display("zero: 0x%08h  ra: 0x%08h  sp: 0x%08h  gp: 0x%08h",
                 regfile[0], regfile[1], regfile[2], regfile[3]);
        $display("tp: 0x%08h  t0: 0x%08h  t1: 0x%08h  t2: 0x%08h",
                 regfile[4], regfile[5], regfile[6], regfile[7]);
        $display("s0: 0x%08h  s1: 0x%08h  a0: 0x%08h  a1: 0x%08h",
                 regfile[8], regfile[9], regfile[10], regfile[11]);
        $display("a2: 0x%08h  a3: 0x%08h  a4: 0x%08h  a5: 0x%08h",
                 regfile[12], regfile[13], regfile[14], regfile[15]);
        $display("a6: 0x%08h  a7: 0x%08h  s2: 0x%08h  s3: 0x%08h",
                 regfile[16], regfile[17], regfile[18], regfile[19]);
        $display("s4: 0x%08h  s5: 0x%08h  s6: 0x%08h  s7: 0x%08h",
                 regfile[20], regfile[21], regfile[22], regfile[23]);
        $display("s8: 0x%08h  s9: 0x%08h  s10: 0x%08h  s11: 0x%08h",
                 regfile[24], regfile[25], regfile[26], regfile[27]);
        $display("t3: 0x%08h  t4: 0x%08h  t5: 0x%08h  t6: 0x%08h",
                 regfile[28], regfile[29], regfile[30], regfile[31]);
        $display("PC: 0x%08h", dump_pc);
        $display("======================================");
    endtask
    // synthesis translate_on

    // Detect instruction misalignment exception for 4-byte alignment requirement
    // Only check bit [1] as bit [0] is allowed for compressed instructions (RV32C)
    // Since we don't support compressed, we require 4-byte alignment (bits [1:0] == 00)
    always_comb begin
        instr_misaligned_exception = 1'b0;
        if (id_ex_reg.valid && |target_addr[1:0]) begin
            if ((id_ex_reg.opcode == OP_JAL) ||
                (id_ex_reg.opcode == OP_JALR) ||
                (id_ex_reg.opcode == OP_BRANCH && alu_branch_taken)) begin
                instr_misaligned_exception = 1'b1;
            end
        end
    end

    logic take_branch;
    logic prev_flush_ex;  // Track previous cycle's flush

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_flush_ex <= 1'b0;
        end else begin
            prev_flush_ex <= flush_ex;
        end
    end

    // Don't take branch if we just flushed in the previous cycle (avoid acting on stale instruction)
    assign take_branch = id_ex_reg.valid && !prev_flush_ex && !instr_misaligned_exception && (
                        (id_ex_reg.opcode == OP_JAL) ||
                        (id_ex_reg.opcode == OP_JALR) ||
                        (id_ex_reg.opcode == OP_BRANCH && alu_branch_taken)
                        );

    // ========================================================================
    // EX/MEM Pipeline Register
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_reg <= '0;
        end else begin
            if (!stall_mem) begin
                ex_mem_reg <= ex_mem_next;
            end
        end
    end

    always_comb begin
        ex_mem_next.pc = id_ex_reg.pc;
        ex_mem_next.instr = id_ex_reg.instr;
        ex_mem_next.alu_result = alu_result;
        ex_mem_next.rs2_data = fwd_rs2_data;
        ex_mem_next.rs1 = id_ex_reg.rs1;
        ex_mem_next.rs2 = id_ex_reg.rs2;
        ex_mem_next.rs1_data = fwd_rs1_data;
        ex_mem_next.rd = id_ex_reg.rd;
        ex_mem_next.opcode = id_ex_reg.opcode;
        ex_mem_next.funct3 = id_ex_reg.funct3;
        ex_mem_next.funct7 = id_ex_reg.funct7;
        ex_mem_next.valid = id_ex_reg.valid;
        ex_mem_next.branch_taken = take_branch;
        ex_mem_next.branch_target = branch_target;
    end

    // ========================================================================
    // STAGE 4: MEMORY ACCESS (MEM)
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_state <= MEM_IDLE;
        end else begin
            mem_state <= mem_state_next;
        end
    end

    always_comb begin
        logic mem_misaligned;

        mem_state_next = mem_state;
        dmem_addr = ex_mem_reg.alu_result;
        dmem_valid = 1'b0;
        dmem_write = 1'b0;
        dmem_wdata = 32'd0;
        dmem_wstrb = 4'b0000;
        mem_operation_done = 1'b0;
        mem_read_data = 32'd0;

        // Check for misalignment locally in MEM stage
        mem_misaligned = 1'b0;
        if (ex_mem_reg.valid) begin
            if (ex_mem_reg.opcode == OP_LOAD) begin
                case (ex_mem_reg.funct3[1:0])
                    2'b01: mem_misaligned = (ex_mem_reg.alu_result[0] != 1'b0); // LH, LHU
                    2'b10: mem_misaligned = (ex_mem_reg.alu_result[1:0] != 2'b00); // LW
                    default: mem_misaligned = 1'b0; // LB, LBU - no alignment requirement
                endcase
            end else if (ex_mem_reg.opcode == OP_STORE) begin
                case (ex_mem_reg.funct3[1:0])
                    2'b01: mem_misaligned = (ex_mem_reg.alu_result[0] != 1'b0); // SH
                    2'b10: mem_misaligned = (ex_mem_reg.alu_result[1:0] != 2'b00); // SW
                    default: mem_misaligned = 1'b0; // SB - no alignment requirement
                endcase
            end
        end

        case (mem_state)
            MEM_IDLE: begin
                if (ex_mem_reg.valid && !mem_misaligned) begin
                    if (ex_mem_reg.opcode == OP_LOAD) begin
                        mem_state_next = MEM_READ_WAIT;
                    end else if (ex_mem_reg.opcode == OP_STORE) begin
                        mem_state_next = MEM_WRITE_WAIT;
                    end else if (ex_mem_reg.opcode == OP_AMO) begin
                        mem_state_next = MEM_AMO_READ;
                    end else begin
                        mem_operation_done = 1'b1;
                    end
                end else begin
                    mem_operation_done = 1'b1;
                end
            end
            MEM_READ_WAIT: begin
                dmem_valid = 1'b1;
                dmem_write = 1'b0;

                if (dmem_ready) begin
                    mem_read_data = dmem_rdata;
                    mem_operation_done = 1'b1;
                    mem_state_next = MEM_IDLE;
                end
            end
            MEM_WRITE_WAIT: begin
                dmem_valid = 1'b1;
                dmem_write = 1'b1;

                case (ex_mem_reg.funct3[1:0])
                    2'b00: begin  // SB
                        case (ex_mem_reg.alu_result[1:0])
                            2'b00: begin
                                dmem_wdata = {24'd0, ex_mem_reg.rs2_data[7:0]};
                                dmem_wstrb = 4'b0001;
                            end
                            2'b01: begin
                                dmem_wdata = {16'd0, ex_mem_reg.rs2_data[7:0], 8'd0};
                                dmem_wstrb = 4'b0010;
                            end
                            2'b10: begin
                                dmem_wdata = {8'd0, ex_mem_reg.rs2_data[7:0], 16'd0};
                                dmem_wstrb = 4'b0100;
                            end
                            2'b11: begin
                                dmem_wdata = {ex_mem_reg.rs2_data[7:0], 24'd0};
                                dmem_wstrb = 4'b1000;
                            end
                        endcase
                    end
                    2'b01: begin  // SH
                        if (ex_mem_reg.alu_result[1] == 1'b0) begin
                            dmem_wdata = {16'd0, ex_mem_reg.rs2_data[15:0]};
                            dmem_wstrb = 4'b0011;
                        end else begin
                            dmem_wdata = {ex_mem_reg.rs2_data[15:0], 16'd0};
                            dmem_wstrb = 4'b1100;
                        end
                    end
                    2'b10: begin  // SW
                        dmem_wdata = ex_mem_reg.rs2_data;
                        dmem_wstrb = 4'b1111;
                    end
                    default: begin
                        dmem_wdata = ex_mem_reg.rs2_data;
                        dmem_wstrb = 4'b1111;
                    end
                endcase

                if (dmem_ready) begin
                    mem_operation_done = 1'b1;
                    mem_state_next = MEM_IDLE;
                end
            end
            MEM_AMO_READ: begin
                dmem_valid = 1'b1;
                dmem_write = 1'b0;
                dmem_wstrb = 4'b1111;

                if (dmem_ready) begin
                    mem_read_data = dmem_rdata;
                    mem_state_next = MEM_AMO_WRITE;
                end
            end
            MEM_AMO_WRITE: begin
                dmem_valid = 1'b1;
                dmem_write = 1'b1;
                dmem_wdata = amo_result;
                dmem_wstrb = 4'b1111;

                if (dmem_ready) begin
                    mem_operation_done = 1'b1;
                    mem_state_next = MEM_IDLE;
                end
            end
            default: mem_state_next = MEM_IDLE;
        endcase
    end

    // Store atomic read data
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            amo_read_data <= 32'd0;
        end else if (mem_state == MEM_AMO_READ && dmem_ready) begin
            amo_read_data <= dmem_rdata;
        end
    end

    // Compute atomic operation result
    always_comb begin
        amo_result = amo_read_data;

        if (ex_mem_reg.opcode == OP_AMO) begin
            case (ex_mem_reg.funct7[6:2])  // funct5 encodes the operation
                5'b00010: amo_result = amo_read_data + ex_mem_reg.rs2_data;  // AMOADD
                5'b00001: amo_result = ex_mem_reg.rs2_data;                  // AMOSWAP
                5'b00000: amo_result = amo_read_data + ex_mem_reg.rs2_data;  // AMOADD (LR/SC use this)
                5'b01100: amo_result = amo_read_data & ex_mem_reg.rs2_data;  // AMOAND
                5'b01000: amo_result = amo_read_data | ex_mem_reg.rs2_data;  // AMOOR
                5'b00100: amo_result = amo_read_data ^ ex_mem_reg.rs2_data;  // AMOXOR
                5'b10000: begin  // AMOMAX (signed)
                    if ($signed(ex_mem_reg.rs2_data) > $signed(amo_read_data))
                        amo_result = ex_mem_reg.rs2_data;
                    else
                        amo_result = amo_read_data;
                end
                5'b10100: begin  // AMOMIN (signed)
                    if ($signed(ex_mem_reg.rs2_data) < $signed(amo_read_data))
                        amo_result = ex_mem_reg.rs2_data;
                    else
                        amo_result = amo_read_data;
                end
                5'b11000: begin  // AMOMAXU (unsigned)
                    if (ex_mem_reg.rs2_data > amo_read_data)
                        amo_result = ex_mem_reg.rs2_data;
                    else
                        amo_result = amo_read_data;
                end
                5'b11100: begin  // AMOMINU (unsigned)
                    if (ex_mem_reg.rs2_data < amo_read_data)
                        amo_result = ex_mem_reg.rs2_data;
                    else
                        amo_result = amo_read_data;
                end
                default: amo_result = amo_read_data;
            endcase
        end
    end

    // Load data alignment
    logic [31:0] aligned_load_data;
    always_comb begin
        // For atomic operations, return the original memory value
        if (ex_mem_reg.opcode == OP_AMO) begin
            aligned_load_data = amo_read_data;
        end else begin
            aligned_load_data = mem_read_data;

            if (ex_mem_reg.opcode == OP_LOAD) begin
                case (ex_mem_reg.funct3)
                3'b000: begin  // LB
                    case (ex_mem_reg.alu_result[1:0])
                        2'b00: aligned_load_data = {{24{mem_read_data[7]}}, mem_read_data[7:0]};
                        2'b01: aligned_load_data = {{24{mem_read_data[15]}}, mem_read_data[15:8]};
                        2'b10: aligned_load_data = {{24{mem_read_data[23]}}, mem_read_data[23:16]};
                        2'b11: aligned_load_data = {{24{mem_read_data[31]}}, mem_read_data[31:24]};
                    endcase
                end
                3'b001: begin  // LH
                    if (ex_mem_reg.alu_result[1] == 1'b0) begin
                        aligned_load_data = {{16{mem_read_data[15]}}, mem_read_data[15:0]};
                    end else begin
                        aligned_load_data = {{16{mem_read_data[31]}}, mem_read_data[31:16]};
                    end
                end
                3'b010: begin  // LW
                    aligned_load_data = mem_read_data;
                end
                3'b100: begin  // LBU
                    case (ex_mem_reg.alu_result[1:0])
                        2'b00: aligned_load_data = {24'd0, mem_read_data[7:0]};
                        2'b01: aligned_load_data = {24'd0, mem_read_data[15:8]};
                        2'b10: aligned_load_data = {24'd0, mem_read_data[23:16]};
                        2'b11: aligned_load_data = {24'd0, mem_read_data[31:24]};
                    endcase
                end
                3'b101: begin  // LHU
                    if (ex_mem_reg.alu_result[1] == 1'b0) begin
                        aligned_load_data = {16'd0, mem_read_data[15:0]};
                    end else begin
                        aligned_load_data = {16'd0, mem_read_data[31:16]};
                    end
                end
                default: aligned_load_data = mem_read_data;
            endcase
            end
        end
    end

    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_reg <= '0;
            mem_wb_valid_reg <= 1'b0;
            mem_wb_instr_retired <= 1'b0;
        end else begin
            if (mem_operation_done) begin
                mem_wb_reg <= mem_wb_next;
                mem_wb_valid_reg <= mem_wb_next.valid;
                mem_wb_instr_retired <= mem_wb_next.valid;  // Pulse for one cycle
            end else begin
                mem_wb_instr_retired <= 1'b0;  // Clear pulse
            end
        end
    end

    always_comb begin
        mem_wb_next.pc = ex_mem_reg.pc;
        mem_wb_next.instr = ex_mem_reg.instr;
        mem_wb_next.alu_result = ex_mem_reg.alu_result;
        mem_wb_next.mem_data = aligned_load_data;
        mem_wb_next.store_data = ex_mem_reg.rs2_data;  // Original store value
        mem_wb_next.csr_addr = ex_mem_reg.instr[31:20];  // CSR address from instruction
        mem_wb_next.csr_wdata_saved = csr_wdata;  // CSR write data from EX stage
        mem_wb_next.rs1 = ex_mem_reg.rs1;
        mem_wb_next.rs2 = ex_mem_reg.rs2;
        mem_wb_next.rs1_data = ex_mem_reg.rs1_data;
        mem_wb_next.rs2_data = ex_mem_reg.rs2_data;
        mem_wb_next.rd = ex_mem_reg.rd;
        mem_wb_next.opcode = ex_mem_reg.opcode;
        mem_wb_next.valid = ex_mem_reg.valid;
    end

    // ========================================================================
    // STAGE 5: WRITE BACK (WB)
    // ========================================================================

    logic [31:0] wb_data;
    logic        wb_enable;
    logic        mret_detected;

    // Detect MRET instruction (0x30200073)
    assign mret_detected = mem_wb_valid_reg &&
                           (mem_wb_reg.opcode == OP_SYSTEM) &&
                           (mem_wb_reg.instr[31:20] == 12'h302);

    always_comb begin
        // Only enable register write for instructions that actually write to rd
        // STORE and BRANCH instructions don't write to rd (bits[11:7] are used for immediate)
        wb_enable = mem_wb_valid_reg && (mem_wb_reg.rd != 5'd0) &&
                    (mem_wb_reg.opcode != OP_STORE) &&
                    (mem_wb_reg.opcode != OP_BRANCH);

        case (mem_wb_reg.opcode)
            OP_LOAD: wb_data = mem_wb_reg.mem_data;
            OP_AMO: wb_data = mem_wb_reg.mem_data;  // Return original memory value
            default: wb_data = mem_wb_reg.alu_result;
        endcase
    end

    // Register file write
    always_ff @(posedge clk) begin
        if (wb_enable) begin
            regfile[mem_wb_reg.rd] <= wb_data;
        end
        regfile[0] <= 32'd0;  // x0 is always 0
    end

    // ========================================================================
    // Exception Detection and Handling
    // ========================================================================

    // Detect illegal instruction in ID stage
    assign illegal_instr_exception = if_id_reg.valid && is_illegal_instr;

    // Detect misaligned memory accesses in EX stage
    always_comb begin
        load_misaligned_exception = 1'b0;
        store_misaligned_exception = 1'b0;

        if (id_ex_reg.valid) begin
            case (id_ex_reg.opcode)
                OP_LOAD: begin
                    case (id_ex_reg.funct3[1:0])
                        2'b01: begin // LH, LHU - must be 2-byte aligned
                            if (alu_result[0] != 1'b0) begin
                                load_misaligned_exception = 1'b1;
                            end
                        end
                        2'b10: begin // LW - must be 4-byte aligned
                            if (alu_result[1:0] != 2'b00) begin
                                load_misaligned_exception = 1'b1;
                            end
                        end
                        default: ; // LB, LBU - no alignment required
                    endcase
                end
                OP_STORE: begin
                    case (id_ex_reg.funct3[1:0])
                        2'b01: begin // SH - must be 2-byte aligned
                            if (alu_result[0] != 1'b0) begin
                                store_misaligned_exception = 1'b1;
                            end
                        end
                        2'b10: begin // SW - must be 4-byte aligned
                            if (alu_result[1:0] != 2'b00) begin
                                store_misaligned_exception = 1'b1;
                            end
                        end
                        default: ; // SB - no alignment required
                    endcase
                end
                default: ; // No alignment check for other opcodes
            endcase
        end
    end

    // ECALL detection (OP_SYSTEM with funct3=000 and imm=000000000000)
    assign ecall_exception = id_ex_reg.valid &&
                            (id_ex_reg.opcode == OP_SYSTEM) &&
                            (id_ex_reg.funct3 == 3'b000) &&
                            (id_ex_reg.imm[11:0] == 12'h000);

    // EBREAK detection (OP_SYSTEM with funct3=000 and imm=000000000001)
    assign ebreak_exception = id_ex_reg.valid &&
                            (id_ex_reg.opcode == OP_SYSTEM) &&
                            (id_ex_reg.funct3 == 3'b000) &&
                            (id_ex_reg.imm[11:0] == 12'h001);

    // Exception priority and encoding
    always_comb begin
        exception_triggered = 1'b0;
        exception_code = 32'd0;
        exception_pc = 32'd0;
        exception_tval = 32'd0;

        // Check exceptions in priority order (per RISC-V spec)
        // Instruction address misaligned has highest priority
        if (instr_misaligned_exception) begin
            exception_triggered = 1'b1;
            exception_code = CAUSE_INSTR_MISALIGNED;
            exception_pc = id_ex_reg.pc;
            exception_tval = target_addr;  // The misaligned target address
        end else if (illegal_instr_exception) begin
            exception_triggered = 1'b1;
            exception_code = CAUSE_ILLEGAL_INSTR;
            exception_pc = if_id_reg.pc;
            exception_tval = if_id_reg.instr;
        end else if (ebreak_exception) begin
            exception_triggered = 1'b1;
            exception_code = CAUSE_BREAKPOINT;
            exception_pc = id_ex_reg.pc;
            exception_tval = 32'd0;  // EBREAK has no tval
        end else if (ecall_exception) begin
            exception_triggered = 1'b1;
            exception_code = CAUSE_ECALL_M;
            exception_pc = id_ex_reg.pc;
            exception_tval = 32'd0;  // ECALL has no tval
        end else if (load_misaligned_exception) begin
            exception_triggered = 1'b1;
            exception_code = CAUSE_LOAD_MISALIGNED;
            exception_pc = id_ex_reg.pc;
            exception_tval = alu_result;
        end else if (store_misaligned_exception) begin
            exception_triggered = 1'b1;
            exception_code = CAUSE_STORE_MISALIGNED;
            exception_pc = id_ex_reg.pc;
            exception_tval = alu_result;
        end
    end

    // ========================================================================
    // Hazard Detection and Pipeline Control
    // ========================================================================

    always_comb begin
        stall_if = 1'b0;  // Never stall IF - it will naturally wait in IF_WAIT state
        stall_id = (if_state == IF_WAIT) && !if_instr_valid;  // Stall ID when IF is fetching but instruction not ready
        stall_ex = !mem_operation_done;
        stall_mem = !mem_operation_done;

        // Flush when branch is taken in EX stage (not when it's in MEM stage)
        // Also flush on exception/interrupt/MRET
        flush_if = take_branch || exception_triggered || interrupt_taken || mret_detected;
        flush_id = take_branch || exception_triggered || interrupt_taken || mret_detected;
        flush_ex = take_branch || exception_triggered || interrupt_taken || mret_detected;

        pipeline_stall = stall_id || stall_ex || stall_mem;
    end

    // ========================================================================
    // Performance Counters
    // ========================================================================

    // mcycle and minstret are now managed by CSR module
    // Keep only the non-CSR performance counters here
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 64'd0;
            instret_count <= 64'd0;
            stall_count <= 64'd0;
        end else begin
            cycle_count <= cycle_count + 64'd1;

            if (mem_wb_instr_retired) begin
                instret_count <= instret_count + 64'd1;
            end

            if (pipeline_stall) begin
                stall_count <= stall_count + 64'd1;
            end
        end
    end

    // Interrupt handling - check for pending interrupts on every cycle
    // Latch interrupt when pending and hold until trap is fully handled
    logic interrupt_in_progress;  // Track if we're currently handling an interrupt

    // Detect any SYSTEM instruction in EX stage (to prevent interrupt during system instruction execution)
    logic system_in_ex;
    assign system_in_ex = id_ex_reg.valid && (id_ex_reg.opcode == OP_SYSTEM);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interrupt_latched <= 1'b0;
            interrupt_pc_saved <= 32'd0;
            interrupt_in_progress <= 1'b0;
        end else begin
            // Set in-progress when we start taking the interrupt (when it gets latched and causes flush)
            if (interrupt_taken && !interrupt_in_progress) begin
                interrupt_in_progress <= 1'b1;
            end

            // Clear latched signal one cycle after interrupt_taken is asserted
            // This allows the flush to propagate and PC to jump to mtvec
            if (interrupt_latched) begin
                interrupt_latched <= 1'b0;
            end

            // Clear in-progress flag when MRET is executed (returning from trap)
            if (interrupt_in_progress && mret_detected) begin
                interrupt_in_progress <= 1'b0;
            end

            // Latch new interrupt if not already handling one
            // Do NOT latch on the same cycle as MRET to avoid PC corruption
            // Do NOT latch while EX stage contains a SYSTEM instruction
            if (interrupt_pending && !interrupt_latched && !interrupt_taken &&
                !interrupt_in_progress && !mret_detected && !system_in_ex &&
                !flush_ex && !take_branch && !exception_triggered) begin
                interrupt_latched <= 1'b1;
                interrupt_pc_saved <= pc;  // Save current PC
            end
        end
    end

    // Interrupt taken signal - remains high until trap vector is fetched
    assign interrupt_taken = interrupt_latched;

    // Memory transaction trace logging (optional)
    generate
        if (ENABLE_MEM_TRACE) begin : gen_mem_trace
            // Instruction memory interface logging
            always @(posedge clk) begin
                if (imem_valid && imem_ready) begin
                    $display("[CPU_IMEM READ ] addr=0x%08x data=0x%08x",
                             imem_addr, imem_rdata);
                end
            end

            // Data memory interface logging
            always @(posedge clk) begin
                if (dmem_valid && dmem_ready) begin
                    if (dmem_write) begin
                        $display("[CPU_DMEM WRITE] addr=0x%08x data=0x%08x strb=0x%x",
                                 dmem_addr, dmem_wdata, dmem_wstrb);
                    end else begin
                        $display("[CPU_DMEM READ ] addr=0x%08x data=0x%08x",
                                 dmem_addr, dmem_rdata);
                    end
                end
            end
        end
    endgenerate

    // ========================================================================
    // RISC-V Formal Interface (RVFI) - Optional
    // ========================================================================

    generate
        if (ENABLE_RVFI) begin : gen_rvfi
            // Order counter - monotonically increasing instruction retirement counter
            logic [63:0] rvfi_order_reg;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    rvfi_order_reg <= 64'h0;
                end else if (mem_wb_instr_retired) begin
                    rvfi_order_reg <= rvfi_order_reg + 64'h1;
                end
            end

            // RVFI outputs - capture retired instruction information
            assign rvfi_valid = mem_wb_instr_retired;
            assign rvfi_order = rvfi_order_reg;
            assign rvfi_insn = mem_wb_reg.instr;
            assign rvfi_trap = exception_triggered;  // Set when exception occurs
            assign rvfi_halt = 1'b0;  // No halt instruction in this implementation
            assign rvfi_intr = interrupt_taken;  // Set when interrupt is taken
            assign rvfi_mode = 2'b11;  // Always M-mode (machine mode)
            assign rvfi_ixl = 2'b01;   // XLEN=32 (RV32)

            // PC values
            assign rvfi_pc_rdata = mem_wb_reg.pc;
            // Next PC calculation - account for branches/jumps
            logic [31:0] next_pc;
            logic [31:0] branch_target_from_ex_mem;
            always_comb begin
                // Get branch_target from ex_mem_reg which was calculated in ID/EX stage
                branch_target_from_ex_mem = ex_mem_reg.branch_target;

                case (mem_wb_reg.opcode)
                    OP_JAL, OP_JALR: next_pc = {branch_target_from_ex_mem[31:2], 2'b00};  // Jump target (force align)
                    OP_BRANCH: begin
                        if (ex_mem_reg.branch_taken && ex_mem_reg.pc == mem_wb_reg.pc) begin
                            next_pc = {branch_target_from_ex_mem[31:2], 2'b00};  // Branch target (force align)
                        end else begin
                            next_pc = mem_wb_reg.pc + 32'd4;
                        end
                    end
                    OP_SYSTEM: begin
                        // MRET or exception return - use mepc (already aligned per RISC-V spec)
                        if (mem_wb_reg.instr[31:20] == 12'h302) begin
                            next_pc = {mepc[31:2], 2'b00};  // Force align
                        end else begin
                            next_pc = mem_wb_reg.pc + 32'd4;
                        end
                    end
                    default: next_pc = mem_wb_reg.pc + 32'd4;
                endcase
            end
            assign rvfi_pc_wdata = next_pc;

            // Register file source operands (as read at decode time)
            assign rvfi_rs1_addr = mem_wb_reg.rs1;
            assign rvfi_rs2_addr = mem_wb_reg.rs2;
            assign rvfi_rs1_rdata = mem_wb_reg.rs1_data;
            assign rvfi_rs2_rdata = mem_wb_reg.rs2_data;

            // Register file destination (what was written, if anything)
            assign rvfi_rd_addr = mem_wb_reg.rd;
            assign rvfi_rd_wdata = wb_enable ? wb_data : 32'h0;

            // Memory interface - capture actual memory transactions
            logic [31:0] mem_addr_captured;
            logic [3:0]  mem_rmask_captured, mem_wmask_captured;
            logic [31:0] mem_rdata_captured, mem_wdata_captured;

            always_comb begin
                mem_addr_captured = 32'h0;
                mem_rmask_captured = 4'h0;
                mem_wmask_captured = 4'h0;
                mem_rdata_captured = 32'h0;
                mem_wdata_captured = 32'h0;

                if (mem_wb_reg.valid) begin
                    case (mem_wb_reg.opcode)
                        OP_LOAD: begin
                            mem_addr_captured = mem_wb_reg.alu_result;
                            mem_rdata_captured = mem_wb_reg.mem_data;
                            // Calculate mask based on funct3 (load type)
                            case (mem_wb_reg.instr[14:12])  // funct3
                                3'b000, 3'b100: begin  // LB, LBU
                                    case (mem_wb_reg.alu_result[1:0])
                                        2'b00: mem_rmask_captured = 4'b0001;
                                        2'b01: mem_rmask_captured = 4'b0010;
                                        2'b10: mem_rmask_captured = 4'b0100;
                                        2'b11: mem_rmask_captured = 4'b1000;
                                    endcase
                                end
                                3'b001, 3'b101: begin  // LH, LHU
                                    mem_rmask_captured = mem_wb_reg.alu_result[1] ? 4'b1100 : 4'b0011;
                                end
                                3'b010: mem_rmask_captured = 4'b1111;  // LW
                                default: mem_rmask_captured = 4'b0000;
                            endcase
                        end
                        OP_STORE: begin
                            mem_addr_captured = mem_wb_reg.alu_result;
                            mem_wdata_captured = mem_wb_reg.store_data;
                            // Calculate mask based on funct3 (store type)
                            case (mem_wb_reg.instr[14:12])  // funct3
                                3'b000: begin  // SB
                                    case (mem_wb_reg.alu_result[1:0])
                                        2'b00: mem_wmask_captured = 4'b0001;
                                        2'b01: mem_wmask_captured = 4'b0010;
                                        2'b10: mem_wmask_captured = 4'b0100;
                                        2'b11: mem_wmask_captured = 4'b1000;
                                    endcase
                                end
                                3'b001: begin  // SH
                                    mem_wmask_captured = mem_wb_reg.alu_result[1] ? 4'b1100 : 4'b0011;
                                end
                                3'b010: mem_wmask_captured = 4'b1111;  // SW
                                default: mem_wmask_captured = 4'b0000;
                            endcase
                        end
                        default: begin
                            mem_addr_captured = 32'h0;
                            mem_rmask_captured = 4'h0;
                            mem_wmask_captured = 4'h0;
                            mem_rdata_captured = 32'h0;
                            mem_wdata_captured = 32'h0;
                        end
                    endcase
                end
            end

            assign rvfi_mem_addr = mem_addr_captured;
            assign rvfi_mem_rmask = mem_rmask_captured;
            assign rvfi_mem_wmask = mem_wmask_captured;
            assign rvfi_mem_rdata = mem_rdata_captured;
            assign rvfi_mem_wdata = mem_wdata_captured;

        end else begin : gen_no_rvfi
            // When RVFI is disabled, tie outputs to zero
            assign rvfi_valid = 1'b0;
            assign rvfi_order = 64'h0;
            assign rvfi_insn = 32'h0;
            assign rvfi_trap = 1'b0;
            assign rvfi_halt = 1'b0;
            assign rvfi_intr = 1'b0;
            assign rvfi_mode = 2'b00;
            assign rvfi_ixl = 2'b00;
            assign rvfi_pc_rdata = 32'h0;
            assign rvfi_pc_wdata = 32'h0;
            assign rvfi_rs1_addr = 5'h0;
            assign rvfi_rs2_addr = 5'h0;
            assign rvfi_rs1_rdata = 32'h0;
            assign rvfi_rs2_rdata = 32'h0;
            assign rvfi_rd_addr = 5'h0;
            assign rvfi_rd_wdata = 32'h0;
            assign rvfi_mem_addr = 32'h0;
            assign rvfi_mem_rmask = 4'h0;
            assign rvfi_mem_wmask = 4'h0;
            assign rvfi_mem_rdata = 32'h0;
            assign rvfi_mem_wdata = 32'h0;
        end
    endgenerate

endmodule
