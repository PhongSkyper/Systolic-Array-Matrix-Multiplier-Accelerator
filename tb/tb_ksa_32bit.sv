`timescale 1ns/1ps

module tb_ksa_32bit;

    // --- 1. DUT Signals ---
    logic [31:0] a;
    logic [31:0] b;
    logic        cin;
    logic [31:0] sum;
    logic        cout;

    // --- 2. Internal Testbench Variables ---
    logic [32:0] expected_res; // 33-bit to capture both expected Cout and Sum
    int          error_count = 0;
    int          test_count  = 0;

    // --- 3. Instantiate the Device Under Test (DUT) ---
    ksa_32bit dut (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .cout(cout)
    );

    // --- 4. Self-Checking Task ---
    task check_adder(input logic [31:0] test_a, input logic [31:0] test_b, input logic test_cin, input string test_name);
        begin
            // Apply stimulus
            a   = test_a;
            b   = test_b;
            cin = test_cin;
            
            // Wait for combinational logic propagation (Delay)
            #10; 

            // Calculate expected result using SystemVerilog built-in operator
            expected_res = test_a + test_b + test_cin;

            // Increment test counter
            test_count++;

            // Compare DUT output with Expected output
            if ({cout, sum} !== expected_res) begin
                $display("---------------------------------------------------------");
                $display("[ERROR] %s", test_name);
                $display("   Input A    = 32'h%08X", test_a);
                $display("   Input B    = 32'h%08X", test_b);
                $display("   Input Cin  = 1'b%b", test_cin);
                $display("   EXPECTED   : Cout = 1'b%b, Sum = 32'h%08X", expected_res[32], expected_res[31:0]);
                $display("   ACTUAL GOT : Cout = 1'b%b, Sum = 32'h%08X", cout, sum);
                $display("---------------------------------------------------------");
                error_count++;
            end else begin
                $display("[PASS] %s | A=%08X, B=%08X, Cin=%b -> Cout=%b, Sum=%08X", 
                          test_name, test_a, test_b, test_cin, cout, sum);
            end
        end
    endtask

    // --- 5. Test Scenarios ---
    initial begin
        $display("=========================================================");
        $display("   STARTING KOGGE-STONE ADDER 32-BIT VERIFICATION        ");
        $display("=========================================================");

        // ------------------------------------------------------------------
        // GROUP 1: THE ULTIMATE CORNER CASES (CARRY PROPAGATION STRESS TEST)
        // ------------------------------------------------------------------
        $display("\n--- Running Extreme Corner Cases ---");
        
        // Corner Case 1: Ripple from Cin to Cout through ALL bits (Propagate chain)
        // A = 11...1, B = 00...0, Cin = 1. Expected: Sum = 00...0, Cout = 1.
        check_adder(32'hFFFF_FFFF, 32'h0000_0000, 1'b1, "FULL CARRY PROPAGATION (ALL 1s + ALL 0s + 1)");

        // Corner Case 2: Checkerboard pattern Carry Propagation
        // A = 1010...10, B = 0101...01. All P_i = 1, G_i = 0.
        check_adder(32'hAAAA_AAAA, 32'h5555_5555, 1'b1, "CHECKERBOARD CARRY PROPAGATION (A + 5 + 1)");
        
        // Corner Case 3: Maximum possible values generating carries everywhere
        // A = 11...1, B = 11...1, Cin = 1. Expected: Sum = 11...1, Cout = 1.
        check_adder(32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b1, "MAXIMUM VALUES WITH CIN (ALL 1s + ALL 1s + 1)");
        
        // Corner Case 4: Maximum values without Cin
        check_adder(32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b0, "MAXIMUM VALUES NO CIN (ALL 1s + ALL 1s + 0)");

        // Corner Case 5: Carry stops right at the MSB (Sum becomes Negative Min in Signed)
        // A = 011...1, B = 000...0, Cin = 1. Expected: Sum = 100...0, Cout = 0.
        check_adder(32'h7FFF_FFFF, 32'h0000_0000, 1'b1, "CARRY STOPS AT MSB (7FFF... + 0 + 1)");

        // Corner Case 6: All Zeros
        check_adder(32'h0000_0000, 32'h0000_0000, 1'b0, "ALL ZEROS");

      
        // Corner Case 7: 
        check_adder(32'hFFFF_FFFE, 32'h0000_0000, 1'b1, "DEATH AT THE DOORSTEP (FFFF_FFFE + 0 + 1)");

        
        // Corner Case 8:
        check_adder(32'hFFFF_FFFF, 32'h0000_0001, 1'b0, "DOMINO EFFECT (ALL 1s + 1 + 0)");
      
        // Corner Case 9: 
        check_adder(32'h0F0F_0F0F, 32'hF0F0_F0F0, 1'b1, "FRACTURED PROPAGATION (0F0F... + F0F0... + 1)");
      
      
        // ------------------------------------------------------------------
        // GROUP 2: RANDOMIZED STRESS TESTING
        // ------------------------------------------------------------------
        $display("\n--- Running 1000 Randomized Test Vectors ---");
        for (int i = 0; i < 1000; i++) begin
            // Using $urandom for unsigned 32-bit random generation
            check_adder($urandom, $urandom, $urandom_range(0, 1), "RANDOMIZED VECTOR");
            
            // Break early if too many errors occur to avoid console flooding
            if (error_count > 10) begin
                $display("\n[FATAL] Too many errors detected. Halting simulation to check routing!");
                break;
            end
        end

        // ------------------------------------------------------------------
        // 6. FINAL SUMMARY
        // ------------------------------------------------------------------
        $display("\n=========================================================");
        if (error_count == 0)
            $display("   [SUCCESS] ALL %0d TESTS PASSED FLAWLESSLY!            ", test_count);
        else
            $display("   [FAILED] DETECTED %0d ROUTING ERRORS IN %0d TESTS.    ", error_count, test_count);
        $display("=========================================================");

        $finish;
    end

endmodule