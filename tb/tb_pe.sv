// =============================================================================
// FILE     : tb_pe_fixed.sv
// DUT      : pe (Processing Element)
//
// FIX      : Pipeline latency corrected từ 2 → 4 cycles
//
// PIPELINE pe.sv (v4.0) — 4 stages:
//   Stage 1a [clk]: pp_reg, neg_reg        ← Booth encode + PPG
//   Stage 1b [clk]: wt_sum_reg, wt_carry_reg ← Wallace Tree
//   Stage 1c [clk]: mul_reg                ← KSA-16 final adder
//   Stage 2  [clk]: acc_reg                ← KSA-32 accumulate
//   c_out = acc_reg                        ← combinational assign
//
// → Sau khi bơm input lần cuối, cần flush thêm PIPE_DEPTH=4 cycle
//   mới đọc được c_out chính xác.
//
// TIMING MODEL (ví dụ bơm 1 cặp a=v, b=v tại negedge cycle T):
//   T+1 clk: pp_reg   ← Booth(v,v)
//   T+2 clk: wt_reg   ← Wallace(pp_reg)
//   T+3 clk: mul_reg  ← KSA16(wt_reg)
//   T+4 clk: acc_reg  ← acc_reg + mul_reg   ← c_out phản ánh tại đây
// =============================================================================
`timescale 1ns/1ps
module tb_pe_fixed();
    localparam int IN_WIDTH   = 8;
    localparam int ACC_WIDTH  = 32;
    localparam int PIPE_DEPTH = 4;   // ← KEY FIX: đúng với pe.sv v4.0

    logic clk, rst_n, en, clear, is_signed;
    logic [IN_WIDTH-1:0]  a_in,  b_in;
    logic [IN_WIDTH-1:0]  a_out, b_out;
    logic [ACC_WIDTH-1:0] c_out;

    int pass_cnt = 0;
    int fail_cnt = 0;

    // -------------------------------------------------------------------------
    // DUT — chỉ truyền 2 parameter thật sự (MUL_WIDTH là localparam trong pe)
    // -------------------------------------------------------------------------
    pe #(.IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .en(en), .clear(clear), .is_signed(is_signed),
        .a_in(a_in),   .b_in(b_in),
        .a_out(a_out), .b_out(b_out),
        .c_out(c_out)
    );

    initial clk = 0;
    always  #5 clk = ~clk;  // 100 MHz

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task do_reset();
        @(negedge clk);
        rst_n = 0; en = 0; clear = 0; is_signed = 0;
        a_in = 0; b_in = 0;
        repeat(3) @(negedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    // Flush pipeline: bơm PIPE_DEPTH zero cycles để drain kết quả cuối ra c_out
    task flush_pipeline();
        repeat(PIPE_DEPTH) begin
            @(negedge clk);
            a_in = 0;
            b_in = 0;
        end
        @(posedge clk);
    endtask

    task check_acc(input logic signed [ACC_WIDTH-1:0] exp, input string tag);
        if (c_out === ACC_WIDTH'(exp)) begin
            $display("[PASS] %-45s | Expected=%0d  Got=%0d", tag, exp, $signed(c_out));
            pass_cnt++;
        end else begin
            $display("[FAIL] %-45s | Expected=%0d  Got=%0d  ← BUG", tag, exp, $signed(c_out));
            fail_cnt++;
        end
    endtask

    task check_fwd(
        input logic [IN_WIDTH-1:0] exp_a,
        input logic [IN_WIDTH-1:0] exp_b,
        input string tag
    );
        if (a_out === exp_a && b_out === exp_b) begin
            $display("[PASS] %-45s | a_out=%0d b_out=%0d", tag, a_out, b_out);
            pass_cnt++;
        end else begin
            $display("[FAIL] %-45s | Exp a=%0d b=%0d  Got a=%0d b=%0d  ← BUG",
                     tag, exp_a, exp_b, a_out, b_out);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    initial begin
        $display("\n====================================================");
        $display("   PROCESSING ELEMENT (PE) TESTBENCH  [FIXED v2]");
        $display("   Pipeline depth = %0d stages", PIPE_DEPTH);
        $display("====================================================");

        // =====================================================================
        // TC1: Accumulate 4 cycles — Σ(i²) for i=1..4 = 1+4+9+16 = 30
        //
        // Timing: bơm (1,1),(2,2),(3,3),(4,4) → flush PIPE_DEPTH zeros
        // → c_out đọc sau posedge cuối flush = 30
        // =====================================================================
        $display("\n--- TC1: Accumulate i*i for i=1..4 ---");
        do_reset();
        en = 1; is_signed = 0;
        for (int v = 1; v <= 4; v++) begin
            @(negedge clk);
            a_in = IN_WIDTH'(v);
            b_in = IN_WIDTH'(v);
        end
        flush_pipeline();
        check_acc(32'd30, "TC1: acc (1+4+9+16=30)");

        // =====================================================================
        // TC2: Clear giữa chừng
        //   Phase A: bơm (1,2),(2,3) → flush → kiểm tra acc=8
        //   Clear  : assert clear 1 cycle → kiểm tra acc=0
        //   Phase B: bơm (3,4),(4,5) → flush → kiểm tra acc=32
        // =====================================================================
        $display("\n--- TC2: Clear giữa chừng ---");
        do_reset();
        en = 1; is_signed = 0;

        @(negedge clk); a_in = 1; b_in = 2;   // 1*2=2
        @(negedge clk); a_in = 2; b_in = 3;   // 2*3=6
        flush_pipeline();
        check_acc(32'd8, "TC2-A: before clear (2+6=8)");

        // Clear: assert 1 cycle, clear_reg propagates đến acc_reg ngay cycle đó
        @(negedge clk); clear = 1; a_in = 0; b_in = 0;
        @(negedge clk); clear = 0;
        // acc_reg đã bị clear tại posedge khi clear=1 → có thể đọc ngay
        @(posedge clk);
        check_acc(32'd0, "TC2-B: after clear (acc=0)");

        // Phase B tiếp tục
        @(negedge clk); a_in = 3; b_in = 4;   // 3*4=12
        @(negedge clk); a_in = 4; b_in = 5;   // 4*5=20
        flush_pipeline();
        check_acc(32'd32, "TC2-C: after clear+resume (12+20=32)");

        // =====================================================================
        // TC3: Data forwarding — a_out/b_out = a_in/b_in delayed 1 clock
        // (free-running FF, không có en gate theo pe.sv v3.1)
        // =====================================================================
        $display("\n--- TC3: Data forwarding (a_out, b_out) ---");
        do_reset();
        en = 1; is_signed = 0;

        @(negedge clk); a_in = 8'd42; b_in = 8'd99;
        @(posedge clk); @(posedge clk);
        check_fwd(8'd42, 8'd99, "TC3: a_out=42 b_out=99 (1 cycle delay)");

        @(negedge clk); a_in = 8'd7; b_in = 8'd13;
        @(posedge clk); @(posedge clk);
        check_fwd(8'd7, 8'd13, "TC3: a_out=7 b_out=13");

        // =====================================================================
        // TC4: Signed multiply — (-5)*3 = -15, accumulated 2 lần = -30
        // =====================================================================
        $display("\n--- TC4: Signed multiply -5*3 accumulated 2x = -30 ---");
        do_reset();
        en = 1; is_signed = 1;

        @(negedge clk); a_in = 8'(-5); b_in = 8'd3;
        @(negedge clk); a_in = 8'(-5); b_in = 8'd3;
        flush_pipeline();
        check_acc(-32'd30, "TC4: signed (-5)*3 + (-5)*3 = -30");

        // =====================================================================
        // TC5: en=0 → PE không accumulate dù có input
        // =====================================================================
        $display("\n--- TC5: en=0, PE không accumulate ---");
        do_reset();
        en = 0; is_signed = 0;

        @(negedge clk); a_in = 8'd10; b_in = 8'd10;
        @(negedge clk); a_in = 8'd10; b_in = 8'd10;
        flush_pipeline();
        check_acc(32'd0, "TC5: c_out=0 khi en=0");

        // =====================================================================
        // TC6 (BONUS): Single multiply — 7*8 = 56
        // Kiểm tra trường hợp bơm 1 cặp duy nhất
        // =====================================================================
        $display("\n--- TC6 (bonus): Single multiply 7*8=56 ---");
        do_reset();
        en = 1; is_signed = 0;

        @(negedge clk); a_in = 8'd7; b_in = 8'd8;
        flush_pipeline();
        check_acc(32'd56, "TC6: single 7*8=56");

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n====================================================");
        $display("  PE TB COMPLETE  |  PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >> ALL TESTS PASSED <<");
        else
            $display("  >> %0d TEST(S) FAILED <<", fail_cnt);
        $display("====================================================\n");

        #50 $finish;
    end
endmodule