// RISC-V CSR (Control and Status Register) Module
// Implements machine-mode CSRs and CSR instructions

module csr (
    input  logic        clk,
    input  logic        rst_n,

    // CSR read/write interface
    input  logic        csr_read,
    input  logic        csr_write,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    input  logic [2:0]  csr_op,        // CSR operation: 001=RW, 010=RS, 011=RC
    output logic [31:0] csr_rdata,
    output logic        csr_illegal,   // Illegal CSR access

    // Exception/Interrupt interface
    input  logic        exception_trigger,
    input  logic [31:0] exception_pc,
    input  logic [31:0] exception_code,
    input  logic [31:0] exception_tval,

    input  logic        interrupt_trigger,
    input  logic [31:0] interrupt_pc,
    input  logic [31:0] interrupt_code,

    input  logic        mret_trigger,

    // Interrupt pending signals
    input  logic        timer_irq,
    input  logic        software_irq,
    input  logic        external_irq,
    output logic        interrupt_pending,

    // Counter updates
    input  logic        count_cycle,
    input  logic        count_instret,

    // CSR values exposed to CPU
    output logic [31:0] mstatus,
    output logic [31:0] mtvec,
    output logic [31:0] mepc,
    output logic [31:0] mie,
    output logic [31:0] mip
);

    // ========================================================================
    // CSR Address Definitions
    // ========================================================================

    // Machine Information Registers
    localparam CSR_MVENDORID = 12'hF11;
    localparam CSR_MARCHID   = 12'hF12;
    localparam CSR_MIMPID    = 12'hF13;
    localparam CSR_MHARTID   = 12'hF14;

    // Machine Trap Setup
    localparam CSR_MSTATUS   = 12'h300;
    localparam CSR_MISA      = 12'h301;
    localparam CSR_MIE       = 12'h304;
    localparam CSR_MTVEC     = 12'h305;

    // Machine Trap Handling
    localparam CSR_MSCRATCH  = 12'h340;
    localparam CSR_MEPC      = 12'h341;
    localparam CSR_MCAUSE    = 12'h342;
    localparam CSR_MTVAL     = 12'h343;
    localparam CSR_MIP       = 12'h344;

    // Machine Counter/Timers
    localparam CSR_MCYCLE    = 12'hB00;
    localparam CSR_MINSTRET  = 12'hB02;
    localparam CSR_MCYCLEH   = 12'hB80;
    localparam CSR_MINSTRETH = 12'hB82;

    // User-accessible counter aliases
    localparam CSR_CYCLE     = 12'hC00;
    localparam CSR_TIME      = 12'hC01;
    localparam CSR_INSTRET   = 12'hC02;
    localparam CSR_CYCLEH    = 12'hC80;
    localparam CSR_TIMEH     = 12'hC81;
    localparam CSR_INSTRETH  = 12'hC82;

    // ========================================================================
    // CSR Registers
    // ========================================================================

    // Machine Information (read-only)
    logic [31:0] mvendorid;
    logic [31:0] marchid;
    logic [31:0] mimpid;
    logic [31:0] mhartid;
    logic [31:0] misa;

    // Machine Trap Setup
    // mstatus, mie, mtvec declared as outputs

    // Machine Trap Handling
    logic [31:0] mscratch;
    // mepc, mip declared as outputs
    logic [31:0] mcause;
    logic [31:0] mtval;

    // Machine Counters
    logic [63:0] mcycle;
    logic [63:0] minstret;

    // ========================================================================
    // CSR Read Logic
    // ========================================================================

    always_comb begin
        csr_rdata = 32'd0;
        csr_illegal = 1'b0;

        // Always read CSRs regardless of csr_read signal (for debugging)
        case (csr_addr)
            // Machine Information Registers
            CSR_MVENDORID: csr_rdata = mvendorid;
            CSR_MARCHID:   csr_rdata = marchid;
                CSR_MIMPID:    csr_rdata = mimpid;
                CSR_MHARTID:   csr_rdata = mhartid;
                CSR_MISA:      csr_rdata = misa;

                // Machine Trap Setup
                CSR_MSTATUS:   csr_rdata = mstatus;
                CSR_MIE:       csr_rdata = mie;
                CSR_MTVEC:     csr_rdata = mtvec;

                // Machine Trap Handling
                CSR_MSCRATCH:  csr_rdata = mscratch;
                CSR_MEPC:      csr_rdata = mepc;
                CSR_MCAUSE:    csr_rdata = mcause;
                CSR_MTVAL:     csr_rdata = mtval;
                CSR_MIP:       csr_rdata = mip;

                // Machine Counters
                CSR_MCYCLE:    csr_rdata = mcycle[31:0];
                CSR_MCYCLEH:   csr_rdata = mcycle[63:32];
                CSR_MINSTRET:  csr_rdata = minstret[31:0];
                CSR_MINSTRETH: csr_rdata = minstret[63:32];

                // User-accessible counter aliases
                CSR_CYCLE:     csr_rdata = mcycle[31:0];
                CSR_CYCLEH:    csr_rdata = mcycle[63:32];
                CSR_INSTRET:   csr_rdata = minstret[31:0];
                CSR_INSTRETH:  csr_rdata = minstret[63:32];
                CSR_TIME:      csr_rdata = mcycle[31:0];  // Use cycle as time
                CSR_TIMEH:     csr_rdata = mcycle[63:32];

                default: begin
                    csr_rdata = 32'd0;
                    csr_illegal = 1'b1;  // Illegal CSR address
                end
            endcase
    end

    // ========================================================================
    // CSR Write Logic
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Machine Information (read-only, hardwired)
            mvendorid <= 32'd0;
            marchid   <= 32'd0;
            mimpid    <= 32'd0;
            mhartid   <= 32'd0;
            misa      <= 32'h40000100;  // RV32I base ISA

            // Machine Trap Setup
            mstatus   <= 32'h00001800;  // MPP=11 (machine mode)
            mie       <= 32'd0;
            mtvec     <= 32'h80000100;  // Default trap vector

            // Machine Trap Handling
            mscratch  <= 32'd0;
            mepc      <= 32'd0;
            mcause    <= 32'd0;
            mtval     <= 32'd0;
            mip       <= 32'd0;

            // Machine Counters
            mcycle    <= 64'd0;
            minstret  <= 64'd0;

        end else begin
            // Update interrupt pending bits
            mip[3]  <= software_irq;   // MSIP - Machine software interrupt pending
            mip[7]  <= timer_irq;      // MTIP - Machine timer interrupt pending
            mip[11] <= external_irq;   // MEIP - Machine external interrupt pending

            // Handle cycle and instruction counters
            if (count_cycle) begin
                mcycle <= mcycle + 64'd1;
            end

            if (count_instret) begin
                minstret <= minstret + 64'd1;
            end

            // Handle exceptions
            if (exception_trigger) begin
                mepc <= exception_pc;
                mcause <= exception_code;
                mtval <= exception_tval;
                mstatus <= {mstatus[31:13], mstatus[12:11], mstatus[10:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};  // MPIE <= MIE, MIE <= 0
            end
            // Handle interrupts
            else if (interrupt_trigger) begin
                mepc <= interrupt_pc;
                mcause <= interrupt_code;
                mtval <= 32'd0;
                mstatus <= {mstatus[31:13], mstatus[12:11], mstatus[10:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};  // MPIE <= MIE, MIE <= 0
            end
            // Handle MRET
            else if (mret_trigger) begin
                mstatus <= {mstatus[31:13], mstatus[12:11], mstatus[10:8], 1'b1, mstatus[6:4], mstatus[7], mstatus[2:0]};  // MIE <= MPIE, MPIE <= 1
            end
            // Handle CSR writes
            else if (csr_write && !csr_illegal) begin
                case (csr_addr)
                    CSR_MSTATUS: begin
                        // Only allow writing to specific fields
                        mstatus <= {mstatus[31:13], csr_wdata[12:11], mstatus[10:8], csr_wdata[7], mstatus[6:4], csr_wdata[3], mstatus[2:0]};
                    end

                    CSR_MIE: begin
                        mie[3]  <= csr_wdata[3];   // MSIE - Machine software interrupt enable
                        mie[7]  <= csr_wdata[7];   // MTIE - Machine timer interrupt enable
                        mie[11] <= csr_wdata[11];  // MEIE - Machine external interrupt enable
                    end

                    CSR_MTVEC: begin
                        mtvec <= {csr_wdata[31:2], 2'b00};  // Must be 4-byte aligned
                    end

                    CSR_MSCRATCH: begin
                        mscratch <= csr_wdata;
                    end

                    CSR_MEPC: begin
                        mepc <= {csr_wdata[31:2], 2'b00};  // Must be 4-byte aligned
                    end

                    CSR_MCAUSE: begin
                        mcause <= csr_wdata;
                    end

                    CSR_MTVAL: begin
                        mtval <= csr_wdata;
                    end

                    CSR_MIP: begin
                        // MIP bits are read-only (set by hardware)
                        // No write action
                    end

                    CSR_MCYCLE: begin
                        mcycle[31:0] <= csr_wdata;
                    end

                    CSR_MCYCLEH: begin
                        mcycle[63:32] <= csr_wdata;
                    end

                    CSR_MINSTRET: begin
                        minstret[31:0] <= csr_wdata;
                    end

                    CSR_MINSTRETH: begin
                        minstret[63:32] <= csr_wdata;
                    end

                    default: begin
                        // Illegal CSR write - no action
                    end
                endcase
            end
        end
    end

    // ========================================================================
    // Interrupt Pending Logic
    // ========================================================================

    assign interrupt_pending = (mstatus[3]) &&  // MIE bit set
                               ((mie[3] && mip[3]) ||   // Software interrupt
                                (mie[7] && mip[7]) ||   // Timer interrupt
                                (mie[11] && mip[11]));  // External interrupt

endmodule
