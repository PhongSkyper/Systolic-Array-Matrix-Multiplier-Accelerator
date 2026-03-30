`timescale 1ns/1ps

module tb_systolic();

    localparam int N         = 8;  
    localparam int IN_WIDTH  = 8;
    localparam int ACC_WIDTH = 32;

    logic clk, rst_n, start, done;

    logic [IN_WIDTH-1:0] data_a [0:N-1];
    logic [IN_WIDTH-1:0] data_b [0:N-1];
    logic [ACC_WIDTH-1:0] result   [0:N-1][0:N-1];

    logic [IN_WIDTH-1:0]  mat_a    [0:N-1][0:N-1];
    logic [IN_WIDTH-1:0]  mat_b    [0:N-1][0:N-1];
    logic signed [ACC_WIDTH-1:0] expected [0:N-1][0:N-1];

    int pass_cnt = 0;
    int fail_cnt = 0;
    int i, j, k, t;

    // -------------------------------------------------------------------------
    // Reference model (Đã thêm $signed để tính toán chính xác số âm)
    // -------------------------------------------------------------------------
    task calc_expected();
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) begin
                expected[i][j] = 0;
                for (k = 0; k < N; k++)
                    expected[i][j] += $signed(mat_a[i][k]) * $signed(mat_b[k][j]);
            end
    endtask

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    systolic_array_top #(.N(N), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .is_signed(1'b1), // BẬT CHẾ ĐỘ SIGNED ĐỂ BOOTH MULTIPLIER CHẠY ĐÚNG
        .data_a(data_a), .data_b(data_b),
        .result(result),  .done(done)
    );

    initial clk = 0;
    always  #5 clk = ~clk;  

    // -------------------------------------------------------------------------
    // Task: chạy 1 lần tính và verify kết quả
    // -------------------------------------------------------------------------
    task run_and_check(input string tc_name);
        @(negedge clk); rst_n = 0;
        for (i = 0; i < N; i++) begin data_a[i] = 0; data_b[i] = 0; end
        repeat(4) @(negedge clk);
        rst_n = 1;

        calc_expected();

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        @(negedge clk);
        @(negedge clk);

        for (t = 0; t < N; t++) begin
            for (i = 0; i < N; i++) begin
                data_a[i] = mat_a[i][t];
                data_b[i] = mat_b[t][i];
            end
            @(negedge clk);
        end

        for (i = 0; i < N; i++) begin data_a[i] = 0; data_b[i] = 0; end

        wait(done);
        repeat(3) @(posedge clk);

        $display("\n--- %s ---", tc_name);
        $display("  [row][col]  |   Expected   |     DUT      | Status");
        $display("  ------------|--------------|--------------|--------");
        begin
            int local_err = 0;
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++) begin
                    if (result[i][j] === expected[i][j]) begin
                        // Chỉ hiển thị 1 vài kết quả đúng để tránh spam log
                        if (i==0 && j<3) $display("   [%0d][%0d]    | %12d | %12d | PASS", i, j, $signed(expected[i][j]), $signed(result[i][j]));
                        pass_cnt++;
                    end else begin
                        $display("   [%0d][%0d]    | %12d | %12d | FAIL <- BUG", i, j, $signed(expected[i][j]), $signed(result[i][j]));
                        fail_cnt++;
                        local_err++;
                    end
                end
            if (local_err == 0)
                $display("  => %s: 100%% PASS (%0d/%0d)", tc_name, N*N, N*N);
            else
                $display("  => %s: %0d FAIL(S)", tc_name, local_err);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    initial begin
        start = 0; rst_n = 1;

        $display("\n====================================================");
        $display("    SYSTOLIC ARRAY 8x8 TESTBENCH (SIGNED MODE)");
        $display("====================================================");

        // TC1: Ma trận hỗn hợp 8x8 (giữ nguyên vì các giá trị đều < 127)
        mat_a[0] = '{8'd0, 8'd0, 8'd0, 8'd0, 8'd1, 8'd2, 8'd3, 8'd4};
        mat_a[1] = '{8'd1, 8'd5, 8'd2, 8'd3, 8'd0, 8'd0, 8'd0, 8'd0};
        mat_a[2] = '{8'd0, 8'd0, 8'd0, 8'd0, 8'd2, 8'd1, 8'd0, 8'd1};
        mat_a[3] = '{8'd4, 8'd3, 8'd2, 8'd1, 8'd0, 8'd0, 8'd0, 8'd0};
        mat_a[4] = '{8'd1, 8'd1, 8'd1, 8'd1, 8'd2, 8'd2, 8'd2, 8'd2};
        mat_a[5] = '{8'd0, 8'd2, 8'd4, 8'd6, 8'd8, 8'd10,8'd12,8'd14};
        mat_a[6] = '{8'd3, 8'd0, 8'd3, 8'd0, 8'd3, 8'd0, 8'd3, 8'd0};
        mat_a[7] = '{8'd1, 8'd2, 8'd1, 8'd2, 8'd1, 8'd2, 8'd1, 8'd2};

        mat_b[0] = '{8'd1, 8'd2, 8'd3, 8'd4, 8'd0, 8'd0, 8'd0, 8'd0};
        mat_b[1] = '{8'd0, 8'd1, 8'd0, 8'd2, 8'd1, 8'd1, 8'd1, 8'd1};
        mat_b[2] = '{8'd2, 8'd0, 8'd1, 8'd1, 8'd2, 8'd2, 8'd2, 8'd2};
        mat_b[3] = '{8'd1, 8'd1, 8'd0, 8'd1, 8'd3, 8'd3, 8'd3, 8'd3};
        mat_b[4] = '{8'd0, 8'd0, 8'd0, 8'd0, 8'd4, 8'd4, 8'd4, 8'd4};
        mat_b[5] = '{8'd1, 8'd0, 8'd1, 8'd0, 8'd1, 8'd0, 8'd1, 8'd0};
        mat_b[6] = '{8'd0, 8'd2, 8'd0, 8'd2, 8'd0, 8'd2, 8'd0, 8'd2};
        mat_b[7] = '{8'd3, 8'd3, 8'd3, 8'd3, 8'd0, 8'd0, 8'd0, 8'd0};

        run_and_check("TC1: Mixed matrix 8x8");

        // TC2: Identity x Identity = Identity
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) begin
                mat_a[i][j] = (i == j) ? 8'd1 : 8'd0;
                mat_b[i][j] = (i == j) ? 8'd1 : 8'd0;
            end
        run_and_check("TC2: Identity x Identity = Identity");

        // TC3: All-ones x All-twos
        for (i = 0; i < N; i++)
            for (j = 0; j < N; j++) begin
                mat_a[i][j] = 8'd1;
                mat_b[i][j] = 8'd2;
            end
        run_and_check("TC3: All-1 x All-2 = All-16");

        // =================================================================
        // TC4: Giá trị có dấu (âm và dương từ -128 đến 127)
        // =================================================================
        mat_a[0] = '{8'd100, -8'd50,  8'd25, -8'd10,  8'd5,  -8'd2,   8'd1,   8'd0};
        mat_a[1] = '{-8'd120, 8'd100,-8'd50,  8'd25, -8'd12,  8'd6,  -8'd3,   8'd1};
        mat_a[2] = '{8'd10,   8'd20,  8'd30,  8'd40,  8'd50,  8'd60,  8'd70,  8'd80};
        mat_a[3] = '{-8'd5,  -8'd10, -8'd15, -8'd20, -8'd25, -8'd30, -8'd35, -8'd40};
        mat_a[4] = '{8'd120,  8'd110, 8'd100, 8'd90,  8'd80,  8'd70,  8'd60,  8'd50};
        mat_a[5] = '{-8'd128,-8'd120,-8'd100,-8'd90, -8'd80, -8'd70, -8'd60, -8'd50};
        mat_a[6] = '{8'd11,   8'd22,  8'd33,  8'd44,  8'd55,  8'd66,  8'd77,  8'd88};
        mat_a[7] = '{-8'd128, 8'd64, -8'd32,  8'd16, -8'd8,   8'd4,  -8'd2,   8'd1};

        mat_b[0] = '{8'd1,  -8'd2,   8'd3,  -8'd4,   8'd5,  -8'd6,   8'd7,  -8'd8};
        mat_b[1] = '{8'd5,   8'd6,   8'd7,   8'd8,   8'd9,   8'd10,  8'd11,  8'd12};
        mat_b[2] = '{-8'd9, -8'd10, -8'd11, -8'd12, -8'd13, -8'd14, -8'd15, -8'd16};
        mat_b[3] = '{8'd13,  8'd14,  8'd15,  8'd16,  8'd17,  8'd18,  8'd19,  8'd20};
        mat_b[4] = '{-8'd20,-8'd19, -8'd18, -8'd17, -8'd16, -8'd15, -8'd14, -8'd13};
        mat_b[5] = '{8'd100, 8'd90,  8'd80,  8'd70,  8'd60,  8'd50,  8'd40,  8'd30};
        mat_b[6] = '{-8'd2,  8'd4,  -8'd8,   8'd16, -8'd32,  8'd64, -8'd128, 8'd120};
        mat_b[7] = '{-8'd1, -8'd2,  -8'd3,  -8'd4,  -8'd5,  -8'd6,  -8'd7,  -8'd8};

        run_and_check("TC4: Signed values test (-128 to 127)");

        $display("\n====================================================");
        $display("  SYSTOLIC TB COMPLETE  |  PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  >> ALL TESTS PASSED <<");
        else               $display("  >> %0d TEST(S) FAILED <<", fail_cnt);
        $display("====================================================\n");

        #50 $finish;
    end
endmodule