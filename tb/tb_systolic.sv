// =============================================================================
// File   : tb_systolic.sv  (v4 — PE[0][0] slice-0 timing fix)
// DUT    : systolic_array_top (N=4, IN_WIDTH=8, ACC_WIDTH=32)
//
// ROOT CAUSE of [0][0] failure in v3:
//
//   en_all_bus is a REGISTERED FF in the fanout tree (global_controller.sv).
//   en_all_comb is evaluated from current_state BEFORE the posedge update.
//
//   Posedge sequence after start is asserted:
//     Posedge 1: start sampled, IDLE→INIT
//                en_all_comb(IDLE)=0  → en_all_bus latches 0
//                clear_pe_comb(IDLE)=0→ clear_pe_bus latches 0
//
//     Posedge 2: INIT→COMPUTE
//                en_all_comb(INIT)=0  → en_all_bus latches 0   ← still 0!
//                clear_pe_comb(INIT)=1→ clear_pe_bus latches 1
//
//     Posedge 3: COMPUTE (counter 0→1)
//                PEs see clear=1 (clear_pe_bus from pos2) → acc_reg=0 ✓
//                PEs see en=0   (en_all_bus from pos2)   → no latch
//                en_all_comb(COMPUTE)=1 → en_all_bus latches 1
//
//     Posedge 4: PEs see en=1 ← FIRST real enable
//                data_a/b for slice 0 must be valid HERE
//                → must be driven at negedge BETWEEN posedge 3 and 4
//
//   v3 drove slice 0 at negedge between posedge 2 and 3 → 1 cycle too early.
//   PE[0][0] (no delay_line) saw data at posedge 3 with en=0 → MISSED.
//   PE[r>0] have delay_line[r≥1] so their data arrived 1+ cycles later
//   → coincidentally landed at posedge 4+ where en=1 → passed.
//
//   FIX: add one more negedge wait before pumping.
//   After deasserting start:
//     @(negedge clk) — skip over posedge 2 (INIT, en still 0)
//     @(negedge clk) — skip over posedge 3 (COMPUTE entered, en_all_bus latching 1)
//     pump slice 0   — valid at posedge 4 where en_all_bus=1 ✓
// =============================================================================
`timescale 1ns/1ps

module tb_systolic();

    localparam int N         = 4;
    localparam int IN_WIDTH  = 8;
    localparam int ACC_WIDTH = 32;

    logic clk, rst_n, start, done;

    logic [IN_WIDTH-1:0]  data_a   [0:N-1];
    logic [IN_WIDTH-1:0]  data_b   [0:N-1];
    logic [ACC_WIDTH-1:0] result   [0:N-1][0:N-1];

    logic [IN_WIDTH-1:0]  mat_a    [0:N-1][0:N-1];
    logic [IN_WIDTH-1:0]  mat_b    [0:N-1][0:N-1];
    logic [ACC_WIDTH-1:0] expected [0:N-1][0:N-1];

    int pass_cnt = 0;
    int fail_cnt = 0;

    // -------------------------------------------------------------------------
    // Reference model
    // -------------------------------------------------------------------------
    task automatic calc_expected();
        int i, j, k;
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) begin
                expected[i][j] = 0;
                for (k = 0; k < N; k++)
                    expected[i][j] += mat_a[i][k] * mat_b[k][j];
            end
    endtask

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    systolic_array_top #(.N(N), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .is_signed(1'b0),
        .data_a(data_a), .data_b(data_b),
        .result(result), .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // -------------------------------------------------------------------------
    // Task: run_and_check
    // -------------------------------------------------------------------------
    task automatic run_and_check(input string tc_name);
        int i, j, t;
        int local_err;

        // Reset
        @(negedge clk);
        rst_n = 0; start = 0;
        for (i = 0; i < N; i++) begin
            data_a[i] = '0;
            data_b[i] = '0;
        end
        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        calc_expected();

        // Assert start 1 cycle
        @(negedge clk); start = 1;   // → posedge samples start, IDLE→INIT
        @(negedge clk); start = 0;   // → posedge: INIT→COMPUTE, clear_pe_bus=1
        @(negedge clk);              // → posedge: COMPUTE, PEs cleared, en_all_bus latches 1
        @(negedge clk);              // → posedge: en_all_bus=1 arrives at PEs ← FIRST ENABLE
                                     //   pump slice 0 driven here, valid at this posedge

        // Pump N slices
        for (t = 0; t < N; t++) begin
            for (i = 0; i < N; i++) begin
                data_a[i] = mat_a[i][t];
                data_b[i] = mat_b[t][i];
            end
            @(negedge clk);
        end

        // Flush
        for (i = 0; i < N; i++) begin
            data_a[i] = '0;
            data_b[i] = '0;
        end

        // Wait for done
        wait(done === 1'b1);
        @(posedge clk); #1;

        // Scoreboard
        local_err = 0;
        $display("\n--- %s ---", tc_name);
        $display("  [row][col] |  Expected  |    DUT     | Status");
        $display("  ----------|------------|------------|--------");
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) begin
                if (result[i][j] === expected[i][j]) begin
                    $display("   [%0d][%0d]   | %10d | %10d | PASS",
                             i, j, expected[i][j], result[i][j]);
                    pass_cnt++;
                end else begin
                    $display("   [%0d][%0d]   | %10d | %10d | FAIL",
                             i, j, expected[i][j], result[i][j]);
                    fail_cnt++;
                    local_err++;
                end
            end

        if (local_err == 0)
            $display("  => %s: ALL PASS (%0d/%0d)", tc_name, N*N, N*N);
        else
            $display("  => %s: %0d FAIL(S)", tc_name, local_err);

        repeat(10) @(negedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    initial begin
        start = 0; rst_n = 1;

        $display("\n====================================================");
        $display("   SYSTOLIC ARRAY 4x4 TESTBENCH (v4 - timing fix)");
        $display("====================================================");

        // TC1: Mixed matrix
        mat_a[0] = '{8'd0, 8'd0, 8'd0, 8'd0};
        mat_a[1] = '{8'd1, 8'd5, 8'd2, 8'd3};
        mat_a[2] = '{8'd0, 8'd0, 8'd0, 8'd0};
        mat_a[3] = '{8'd4, 8'd3, 8'd2, 8'd1};
        mat_b[0] = '{8'd1, 8'd2, 8'd3, 8'd4};
        mat_b[1] = '{8'd0, 8'd1, 8'd0, 8'd2};
        mat_b[2] = '{8'd2, 8'd0, 8'd1, 8'd1};
        mat_b[3] = '{8'd1, 8'd1, 8'd0, 8'd1};
        run_and_check("TC1: Mixed matrix");

        // TC2: Identity x Identity
        begin
            int ii, jj;
            for (ii = 0; ii < N; ii++)
                for (jj = 0; jj < N; jj++) begin
                    mat_a[ii][jj] = (ii == jj) ? 8'd1 : 8'd0;
                    mat_b[ii][jj] = (ii == jj) ? 8'd1 : 8'd0;
                end
        end
        run_and_check("TC2: Identity x Identity");

        // TC3: All-1 x All-2 = All-8
        begin
            int ii, jj;
            for (ii = 0; ii < N; ii++)
                for (jj = 0; jj < N; jj++) begin
                    mat_a[ii][jj] = 8'd1;
                    mat_b[ii][jj] = 8'd2;
                end
        end
        run_and_check("TC3: All-1 x All-2 = All-8");

        // TC4: Large values
        mat_a[0] = '{8'd100, 8'd50,  8'd25,  8'd10};
        mat_a[1] = '{8'd200, 8'd100, 8'd50,  8'd25};
        mat_a[2] = '{8'd10,  8'd20,  8'd30,  8'd40};
        mat_a[3] = '{8'd5,   8'd10,  8'd15,  8'd20};
        mat_b[0] = '{8'd1,  8'd2,  8'd3,  8'd4};
        mat_b[1] = '{8'd5,  8'd6,  8'd7,  8'd8};
        mat_b[2] = '{8'd9,  8'd10, 8'd11, 8'd12};
        mat_b[3] = '{8'd13, 8'd14, 8'd15, 8'd16};
        run_and_check("TC4: Large values (>15)");

        // TC5: Diagonal x Dense
        mat_a[0] = '{8'd2, 8'd0, 8'd0, 8'd0};
        mat_a[1] = '{8'd0, 8'd3, 8'd0, 8'd0};
        mat_a[2] = '{8'd0, 8'd0, 8'd4, 8'd0};
        mat_a[3] = '{8'd0, 8'd0, 8'd0, 8'd5};
        mat_b[0] = '{8'd10, 8'd20, 8'd30, 8'd40};
        mat_b[1] = '{8'd10, 8'd20, 8'd30, 8'd40};
        mat_b[2] = '{8'd10, 8'd20, 8'd30, 8'd40};
        mat_b[3] = '{8'd10, 8'd20, 8'd30, 8'd40};
        run_and_check("TC5: Diagonal x Dense");

        // TC6: Consecutive run with same matrices (tests re-trigger)
        run_and_check("TC6: Consecutive same matrices");

        // Summary
        $display("\n====================================================");
        $display("  COMPLETE  |  PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >> ALL TESTS PASSED <<");
        else
            $display("  >> %0d TEST(S) FAILED <<", fail_cnt);
        $display("====================================================\n");

        #50 $finish;
    end

endmodule