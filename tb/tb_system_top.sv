// =============================================================================
// File   : tb_system_top.sv
// DUT    : system_top (N=4 để sim nhanh, đổi thành 8 khi test thật)
//
// Fixes so với file gốc:
//   BUG: Không verify output gì cả — chỉ #70ms rồi $finish
//   FIX: Thêm task recv_byte (clock-sync) để nhận 64 bytes qua TX
//        So sánh từng kết quả với giá trị tính tay
//
// Test cases:
//   TC1 — A=all-1, B=all-2 → mỗi phần tử C = N*1*2 = 8 (unsigned)
//   TC2 — A=identity, B=all-3 → row i của C = row i của B*3
//
// Timing:
//   CLK_PERIOD = 20 ns  (50 MHz)
//   BIT_CLKS   = 325 * 16 = 5200 clk/bit  (9600 baud, 16× oversample)
//   send_byte  : clock-synchronous (đảm bảo không lệch pha với UART RX)
//   recv_byte  : @(negedge tx) → count clocks đến giữa mỗi data bit
// =============================================================================
`timescale 1ns/1ps

module tb_system_top();

    // Đặt N=4 để simulation nhanh hơn (4×4 = 16 kết quả thay vì 8×8 = 64)
    // Đổi thành 8 và sửa DUT instantiation nếu muốn test đầy đủ
    localparam int N          = 4;
    localparam int IN_WIDTH   = 8;
    localparam int ACC_WIDTH  = 32;

    localparam int CLK_PERIOD = 20;
    localparam int BAUD_DIV   = 325;
    localparam int OVERSAMPLE = 16;
    localparam int BIT_CLKS   = BAUD_DIV * OVERSAMPLE;   // 5200 clk/bit
    localparam int HALF_BIT   = BIT_CLKS / 2;            // 2600 clk

    logic clk, rst_n, rx, tx;

    int pass_cnt = 0;
    int fail_cnt = 0;

    // -------------------------------------------------------------------------
    // DUT — override N=4 để sim nhanh
    // -------------------------------------------------------------------------
    system_top #(.N(N), .IN_WIDTH(IN_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .rx(rx), .tx(tx),
        .is_signed(1'b0)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // send_byte: clock-synchronous UART transmit
    //   Mỗi bit = BIT_CLKS chu kỳ clock (đảm bảo UART RX đọc đúng giữa bit)
    // -------------------------------------------------------------------------
    task automatic send_byte(input logic [7:0] data);
        @(posedge clk); #1;
        rx = 1'b0;                              // Start bit
        repeat(BIT_CLKS) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            rx = data[i];                       // LSB first
            repeat(BIT_CLKS) @(posedge clk);
        end
        rx = 1'b1;                              // Stop bit
        repeat(BIT_CLKS) @(posedge clk);
        repeat(BIT_CLKS) @(posedge clk);        // Inter-byte gap
    endtask

    // -------------------------------------------------------------------------
    // recv_byte: clock-synchronous UART receive từ DUT TX line
    //   Bắt cạnh xuống của start bit, đếm chính xác số clock đến giữa bit
    // -------------------------------------------------------------------------
    task automatic recv_byte(output logic [7:0] data);
        @(negedge tx);                          // Bắt cạnh đầu start bit
        // Nhảy tới giữa start bit, xác nhận vẫn là 0
        repeat(HALF_BIT) @(posedge clk);
        // Bỏ qua nửa còn lại của start bit → đến đầu bit 0
        repeat(HALF_BIT) @(posedge clk);
        // Nhảy vào giữa bit 0
        repeat(HALF_BIT) @(posedge clk);
        // Lấy mẫu 8 bit data, mỗi bit cách nhau BIT_CLKS
        for (int b = 0; b < 8; b++) begin
            data[b] = tx;
            repeat(BIT_CLKS) @(posedge clk);
        end
        // Chờ hết stop bit
        repeat(HALF_BIT) @(posedge clk);
        repeat(BIT_CLKS) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // recv_result: nhận 1 kết quả ACC_WIDTH-bit (4 bytes, LSB first)
    // -------------------------------------------------------------------------
    task automatic recv_result(output logic [ACC_WIDTH-1:0] val);
        logic [7:0] b;
        recv_byte(b); val[7:0]   = b;
        recv_byte(b); val[15:8]  = b;
        recv_byte(b); val[23:16] = b;
        recv_byte(b); val[31:24] = b;
    endtask

    // -------------------------------------------------------------------------
    // run_test: gửi A (N×N bytes) + B (N×N bytes), nhận C (N×N × 4 bytes)
    //           và verify từng phần tử so với expected[N][N]
    // -------------------------------------------------------------------------
    task automatic run_test(
        input  logic [IN_WIDTH-1:0]  A [0:N-1][0:N-1],
        input  logic [IN_WIDTH-1:0]  B [0:N-1][0:N-1],
        input  logic [ACC_WIDTH-1:0] expected [0:N-1][0:N-1],
        input  string                tc_name
    );
        logic [ACC_WIDTH-1:0] got;
        int local_err = 0;

        $display("\n--- %s ---", tc_name);
        $display("[TX] Sending %0d bytes for matrix A...", N*N);
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++)
                send_byte(A[r][c]);

        $display("[TX] Sending %0d bytes for matrix B...", N*N);
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++)
                send_byte(B[r][c]);

        $display("[RX] Receiving %0d result bytes...", N*N*4);
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                recv_result(got);
                if (got === expected[r][c]) begin
                    $display("[PASS] C[%0d][%0d] = %0d", r, c, got);
                    pass_cnt++;
                end else begin
                    $display("[FAIL] C[%0d][%0d]: expected=%0d got=%0d", r, c, expected[r][c], got);
                    fail_cnt++;
                    local_err++;
                end
            end

        if (local_err == 0)
            $display("=> %s: PASSED (%0d/%0d correct)", tc_name, N*N, N*N);
        else
            $display("=> %s: FAILED (%0d errors)", tc_name, local_err);
    endtask

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    logic [IN_WIDTH-1:0]  mat_a    [0:N-1][0:N-1];
    logic [IN_WIDTH-1:0]  mat_b    [0:N-1][0:N-1];
    logic [ACC_WIDTH-1:0] mat_exp  [0:N-1][0:N-1];

    initial begin
        rst_n = 0; rx = 1'b1;
        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        $display("\n====================================================");
        $display("   SYSTEM TOP TESTBENCH (N=%0d)", N);
        $display("====================================================");

        // =================================================================
        // TC1: A=all-1, B=all-2 → C[i][j] = N * 1 * 2 = 8
        // =================================================================
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                mat_a[r][c] = 8'd1;
                mat_b[r][c] = 8'd2;
                mat_exp[r][c] = 32'(N * 1 * 2);   // = 8 for N=4
            end

        run_test(mat_a, mat_b, mat_exp, "TC1: All-1 x All-2 = All-8");

        // =================================================================
        // TC2: A=Identity, B=all-3 → C = B*3 (mỗi hàng C[i] = hàng B[i]*3)
        //      Với identity A: C[i][j] = sum_k A[i][k]*B[k][j] = B[i][j]
        //      A[i][k] = 1 chỉ khi i==k → C[i][j] = B[i][j] = 3
        // =================================================================
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                mat_a[r][c] = (r == c) ? 8'd1 : 8'd0;  // Identity
                mat_b[r][c] = 8'd3;
                mat_exp[r][c] = 32'd3;  // C = I × B = B
            end

        run_test(mat_a, mat_b, mat_exp, "TC2: Identity x All-3 = All-3");

        // =================================================================
        // Summary
        // =================================================================
        $display("\n====================================================");
        $display("  SYSTEM TOP TB COMPLETE  |  PASS: %0d  FAIL: %0d",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >> ALL TESTS PASSED <<");
        else
            $display("  >> %0d TEST(S) FAILED <<", fail_cnt);
        $display("====================================================\n");

        $finish;
    end

    // Timeout guard (2 test cases × N×N × (N×N+N×N) bytes × 12 frame mỗi byte)
    initial begin
        #(2 * N*N*2 * 12 * BIT_CLKS * CLK_PERIOD * 2);
        $display("[TIMEOUT] Simulation took too long — check deadlock");
        $finish;
    end

endmodule
