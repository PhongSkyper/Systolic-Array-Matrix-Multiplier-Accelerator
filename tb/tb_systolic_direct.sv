`timescale 1ns/1ps
module tb_systolic_direct();

    localparam int N           = 4;
    localparam int IN_WIDTH    = 8;
    localparam int ACC_WIDTH   = 32;
    localparam int DONE_TIMEOUT = (3*N+3+N+20) * 2;

    logic clk = 0;
    logic rst_n;
    logic start;
    logic is_signed;
    logic [IN_WIDTH-1:0]  data_a [0:N-1];
    logic [IN_WIDTH-1:0]  data_b [0:N-1];
    logic [ACC_WIDTH-1:0] result [0:N-1][0:N-1];
    logic done;

    always #5 clk = ~clk;

    systolic_array_top #(.N(N), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .is_signed(is_signed),
        .data_a(data_a), .data_b(data_b),
        .result(result), .done(done)
    );

    int pass_cnt = 0;
    int fail_cnt = 0;

    logic signed [IN_WIDTH-1:0]  A [0:N-1][0:N-1];
    logic signed [IN_WIDTH-1:0]  B [0:N-1][0:N-1];
    logic signed [ACC_WIDTH-1:0] C_exp [0:N-1][0:N-1];

    task do_reset();
        start = 0; is_signed = 0;
        for (int i = 0; i < N; i++) begin
            data_a[i] = 0;
            data_b[i] = 0;
        end
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);
    endtask

    task pump_and_wait(input logic sgn);
        int timeout_cnt;
        is_signed = sgn;

        // Assert start 1 cycle
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        // Wait 2 extra cycles before pumping k=0 so PE[0][0] en_all_bus is high
        // Cycle 0: start=1, controller IDLE->INIT
        // Cycle 1: INIT (clear fires), en_all_comb=0
        // Cycle 2: COMPUTE, en_all_comb=1, en_all_bus still 0 (registered)
        // Cycle 3: en_all_bus=1 -> pump k=0 here
        repeat(2) @(negedge clk);

        // Pump N column-slices of A and row-slices of B
        for (int k = 0; k < N; k++) begin
            @(negedge clk);
            for (int i = 0; i < N; i++) begin
                data_a[i] = IN_WIDTH'(A[i][k]);
                data_b[i] = IN_WIDTH'(B[k][i]);
            end
        end

        // Zero inputs
        @(negedge clk);
        for (int i = 0; i < N; i++) begin
            data_a[i] = 0;
            data_b[i] = 0;
        end

        // Wait for done
        timeout_cnt = 0;
        while (!done) begin
            @(posedge clk);
            timeout_cnt++;
            if (timeout_cnt > DONE_TIMEOUT) begin
                $display("  [TIMEOUT] done never asserted");
                return;
            end
        end
        @(posedge clk);
    endtask

    task compute_expected(input logic sgn);
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                C_exp[r][c] = 0;
                for (int k = 0; k < N; k++) begin
                    if (sgn)
                        C_exp[r][c] += $signed(A[r][k]) * $signed(B[k][c]);
                    else
                        C_exp[r][c] += $unsigned(A[r][k]) * $unsigned(B[k][c]);
                end
            end
    endtask

    task check_all(input string tc_name);
        int errs;
        errs = 0;
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                if ($signed(result[r][c]) !== C_exp[r][c]) begin
                    errs++;
                    fail_cnt++;
                    $display("  [FAIL] %s C[%0d][%0d] got=%0d exp=%0d",
                             tc_name, r, c, $signed(result[r][c]), C_exp[r][c]);
                end else begin
                    pass_cnt++;
                end
            end
        if (errs == 0)
            $display("  [PASS] %s all %0d elements correct", tc_name, N*N);
        else
            $display("  [FAIL] %s %0d element(s) wrong", tc_name, errs);
    endtask

    initial begin
        $display("====================================================");
        $display("  SYSTOLIC DIRECT TESTBENCH  N=%0d  IN=%0d  ACC=%0d",
                 N, IN_WIDTH, ACC_WIDTH);
        $display("====================================================");

        // TC1: Identity x Identity = Identity
        $display("\n--- TC1: Identity x Identity ---");
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = (r == c) ? 1 : 0;
                B[r][c] = (r == c) ? 1 : 0;
            end
        compute_expected(0);
        pump_and_wait(0);
        check_all("TC1");

        // TC2: All-1 x All-1 = All-N
        $display("\n--- TC2: All-1 x All-1 = All-%0d ---", N);
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = 1;
                B[r][c] = 1;
            end
        compute_expected(0);
        pump_and_wait(0);
        check_all("TC2");

        // TC3: All-1 x All-2 = All-2N
        $display("\n--- TC3: All-1 x All-2 = All-%0d ---", N*2);
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = 1;
                B[r][c] = 2;
            end
        compute_expected(0);
        pump_and_wait(0);
        check_all("TC3");

        // TC4: Diagonal A x All-ones B
        $display("\n--- TC4: Diag(1..N) x All-1 ---");
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = (r == c) ? (r+1) : 0;
                B[r][c] = 1;
            end
        compute_expected(0);
        pump_and_wait(0);
        check_all("TC4");

        // TC5: Signed all-(-1) x all-2 = all-(-2N)
        $display("\n--- TC5: All-(-1) x All-2 signed = All-%0d ---", -N*2);
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = -1;
                B[r][c] = 2;
            end
        compute_expected(1);
        pump_and_wait(1);
        check_all("TC5");

        // TC6: Unsigned 127x127
        $display("\n--- TC6: All-127 x All-127 (unsigned) ---");
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = 8'd127;
                B[r][c] = 8'd127;
            end
        compute_expected(0);
        pump_and_wait(0);
        check_all("TC6");

        // TC7: Signed boundary 127 x (-128)
        $display("\n--- TC7: All-127 x All-(-128) (signed boundary) ---");
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = 127;
                B[r][c] = -128;
            end
        compute_expected(1);
        pump_and_wait(1);
        check_all("TC7");

        // TC8: Fixed pattern
        $display("\n--- TC8: Fixed pattern ---");
        do_reset();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                A[r][c] = (r*N + c + 1) % 64;
                B[r][c] = (c*N + r + 1) % 64;
            end
        compute_expected(0);
        pump_and_wait(0);
        check_all("TC8");

        $display("\n====================================================");
        $display("  RESULT:  PASS=%0d  FAIL=%0d  (total=%0d)",
                 pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        if (fail_cnt == 0)
            $display("  >> ALL TESTS PASSED <<");
        else
            $display("  >> %0d FAILURE(S) <<", fail_cnt);
        $display("====================================================\n");
        #50 $finish;
    end

endmodule
