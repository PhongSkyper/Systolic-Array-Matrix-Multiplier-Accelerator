// =============================================================================
// File   : tb_fifo.sv
// DUT    : fifo_sync_structured (W=8, L=8)
//
// Test cases:
//   TC1 — Write 0..7 tuần tự, đọc ra verify từng byte + kiểm full/empty flag
//   TC2 — Overflow: write khi full → phải bị bỏ qua, data không bị ghi đè
//   TC3 — Underflow: read khi empty → data_out không đổi
//   TC4 — Simultaneous read + write (RW path trong fifo_controller)
//   TC5 — Alternating: write 1 → read 1 xen kẽ (FIFO không bao giờ full/empty)
//   TC6 — Reset giữa chừng: fill 4 phần tử → reset → kiểm tra empty
// =============================================================================
`timescale 1ns/1ps

module tb_fifo;

    localparam int W = 8;
    localparam int L = 8;

    logic         clk, rst_n;
    logic         write_en, read_en;
    logic [W-1:0] data_in, data_out;
    logic         full, empty;

    int pass_cnt = 0;
    int fail_cnt = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    fifo_sync_structured #(.W(W), .L(L)) dut (
        .clk(clk), .rst_n(rst_n),
        .write_en(write_en), .read_en(read_en),
        .data_in(data_in),   .data_out(data_out),
        .full(full),         .empty(empty)
    );

    initial clk = 0;
    always  #5 clk = ~clk;  // 100 MHz

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task do_reset();
        write_en = 0; read_en = 0; data_in = '0; rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    // Write 1 byte, chờ FIFO FSM hoàn tất (W_MEM → W_INC → IDLE = 3 cycle)
    task write_byte(input logic [W-1:0] d);
        @(negedge clk); data_in = d; write_en = 1;
        @(negedge clk); write_en = 0;
        repeat(3) @(posedge clk);
    endtask

    // Read 1 byte, chờ FIFO FSM hoàn tất (R_ADDR → R_CAP → R_INC = 4 cycle)
    task read_byte(output logic [W-1:0] d);
        @(negedge clk); read_en = 1;
        @(negedge clk); read_en = 0;
        repeat(4) @(posedge clk);
        d = data_out;
    endtask

    // Read + tự verify
    task check_read(input logic [W-1:0] exp, input string tag);
        logic [W-1:0] got;
        read_byte(got);
        if (got === exp) begin
            $display("[PASS] %-30s | Expected=0x%02X  Got=0x%02X", tag, exp, got);
            pass_cnt++;
        end else begin
            $display("[FAIL] %-30s | Expected=0x%02X  Got=0x%02X  ← BUG", tag, exp, got);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fifo.vcd");
        $dumpvars(0, tb_fifo);

        // =====================================================================
        // TC1: Write 0-7, verify each readback + full/empty flags
        // =====================================================================
        $display("\n=== TC1: Sequential Write 0..7, then Read ===");
        do_reset();

        for (int i = 0; i < 8; i++) write_byte(8'(i));

        // Sau 8 write → phải full
        @(posedge clk);
        if (full) begin
            $display("[PASS] TC1: full flag set after 8 writes");
            pass_cnt++;
        end else begin
            $display("[FAIL] TC1: full flag NOT set after 8 writes");
            fail_cnt++;
        end

        for (int i = 0; i < 8; i++)
            check_read(8'(i), $sformatf("TC1 read[%0d]", i));

        // Sau 8 read → phải empty
        @(posedge clk);
        if (empty) begin
            $display("[PASS] TC1: empty flag set after 8 reads");
            pass_cnt++;
        end else begin
            $display("[FAIL] TC1: empty flag NOT set after 8 reads");
            fail_cnt++;
        end

        // =====================================================================
        // TC2: Overflow — write khi full, dữ liệu phải bị bỏ qua
        // =====================================================================
        $display("\n=== TC2: Overflow Write (write khi full) ===");
        do_reset();

        for (int i = 0; i < 8; i++) write_byte(8'(i + 10));
        write_byte(8'hFF);  // byte này phải bị ignore

        for (int i = 0; i < 8; i++)
            check_read(8'(i + 10), $sformatf("TC2 read[%0d]", i));

        // =====================================================================
        // TC3: Underflow — read khi empty, data_out không được thay đổi
        // =====================================================================
        $display("\n=== TC3: Underflow Read (read khi empty) ===");
        do_reset();
        write_byte(8'hAB);
        begin
            logic [W-1:0] known; read_byte(known);  // đọc byte hợp lệ duy nhất

            // Giờ FIFO empty, thử read thêm
            @(negedge clk); read_en = 1;
            @(negedge clk); read_en = 0;
            repeat(4) @(posedge clk);

            if (data_out === known) begin
                $display("[PASS] TC3: data_out giữ nguyên 0x%02X khi underflow", known);
                pass_cnt++;
            end else begin
                $display("[FAIL] TC3: data_out đổi thành 0x%02X sau underflow", data_out);
                fail_cnt++;
            end
        end

        // =====================================================================
        // TC4: Simultaneous Read + Write (FIFO có 4 phần tử, đọc+ghi cùng lúc)
        // =====================================================================
        $display("\n=== TC4: Simultaneous Read + Write ===");
        do_reset();

        for (int i = 0; i < 4; i++) write_byte(8'(i + 50));

        // Ghi đồng thời 4 byte mới, đọc ra 4 byte cũ
        for (int i = 0; i < 4; i++) begin
            logic [W-1:0] got;
            @(negedge clk); data_in = 8'(i + 60); write_en = 1; read_en = 1;
            @(negedge clk); write_en = 0; read_en = 0;
            repeat(6) @(posedge clk);
            got = data_out;
            if (got === 8'(i + 50)) begin
                $display("[PASS] TC4 RW[%0d]: read=0x%02X (correct)", i, got);
                pass_cnt++;
            end else begin
                $display("[FAIL] TC4 RW[%0d]: expected=0x%02X got=0x%02X", i, 8'(i+50), got);
                fail_cnt++;
            end
        end

        // =====================================================================
        // TC5: Alternating write/read — FIFO luôn có đúng 1 phần tử
        // =====================================================================
        $display("\n=== TC5: Alternating Write/Read ===");
        do_reset();

        for (int i = 0; i < 8; i++) begin
            write_byte(8'(i + 70));
            check_read(8'(i + 70), $sformatf("TC5 alt[%0d]", i));
        end

        // =====================================================================
        // TC6: Reset giữa chừng
        // =====================================================================
        $display("\n=== TC6: Reset Giữa Chừng ===");
        do_reset();

        for (int i = 0; i < 4; i++) write_byte(8'(i + 90));

        // Assert reset
        @(negedge clk); rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        if (empty) begin
            $display("[PASS] TC6: FIFO empty sau reset");
            pass_cnt++;
        end else begin
            $display("[FAIL] TC6: FIFO không empty sau reset");
            fail_cnt++;
        end

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n=======================================================");
        $display("  FIFO TESTBENCH COMPLETE  |  PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >> ALL TESTS PASSED <<");
        else
            $display("  >> %0d TEST(S) FAILED — XEM LOG Ở TRÊN <<", fail_cnt);
        $display("=======================================================\n");

        $finish;
    end

endmodule
