# 8×8 Systolic Matrix Multiplier with UART Interface

**Target** : Terasic DE10-Standard (Cyclone V 5CSXFC6D6F31C6N)  
**Tool**   : Quartus Prime Lite 25.1 / ModelSim-Intel FPGA Edition  
**Fmax**   : ≈ 125 MHz on Cyclone V (up from 83 MHz baseline)

---

## Directory Structure

```
systolic_matmul/
├── rtl/
│   ├── pkg/
│   │   └── uart_pkg.sv              # Shared UART constants & types
│   ├── primitives/
│   │   ├── gates.sv                 # xnor_gate, and2_gate, and4_gate, mux2_1bit
│   │   ├── adders.sv                # full_adder, ripple adders, synchronizer
│   │   ├── fifo_sync_structured.sv  # Generic sync FIFO (parameterised W × L)
│   │   └── ksa_32bit.sv             # 32-bit Kogge-Stone adder + pg/black/gray cells
│   ├── multiplier/
│   │   └── booth_wallace_8x8.sv     # Radix-4 Booth × Wallace Tree × KSA-16
│   ├── systolic/
│   │   ├── delay_line.sv            # Parameterised skew shift-register
│   │   ├── pe.sv                    # Processing Element (4-stage MAC pipeline)
│   │   ├── global_controller.sv     # Moore FSM + RTL fanout tree
│   │   └── systolic_array_top.sv    # 8×8 PE array + delay lines + controller
│   ├── uart/
│   │   ├── uart_rx.sv               # 8N1 UART receiver (16× oversampling)
│   │   ├── uart_tx.sv               # 8N1 UART transmitter
│   │   └── uart_top.sv              # Baud gen + FIFOs + TX FSM
│   └── top/
│       └── system_top.sv            # Chip top: UART ↔ systolic array FSM
├── sim/
│   └── tb/                          # Testbench files (user-supplied)
├── constraints/
│   └── system_top.sdc               # Timing constraints (50 MHz → 125 MHz target)
├── scripts/
│   ├── filelist.f                   # Ordered source list for VCS / ModelSim
│   ├── sim.sh                       # ModelSim compile + simulate script
│   └── create_project.tcl           # Quartus project creation script
└── docs/
    └── README.md                    # This file
```

---

## Pipeline Architecture

```
PE v4.0 — 4-stage MAC pipeline
─────────────────────────────────────────────────────────────────────
Stage 1a │ Booth enc + PPG + Alignment        │ ~2–3 ns │ → pp_reg
Stage 1b │ Wallace Tree (3×FA, 5→2 rows)      │ ~3–4 ns │ → wt_reg
Stage 1c │ KSA-16 final adder                 │ ~2–3 ns │ → mul_reg
Stage 2  │ KSA-32 accumulate                  │ ~3–4 ns │ → acc_reg
─────────────────────────────────────────────────────────────────────
TOTAL_CYCLES = 3×N + 3 = 27  (N=8)
```

### Key Design Decisions

| Problem | Solution |
|---|---|
| Stage 1 CSA serial carry chain (~10 ns) | Replace with KSA-16 (~3 ns) |
| Block RAM inference in delay_line | `(* ramstyle = "logic" *)` attribute forces FF chain |
| High-fanout en_all net (64 PEs) on Quartus Lite | N×N explicit `(* keep *)` FF copies (RTL fanout tree) |
| Unsigned 8-bit Booth: off-by-b[7]×A×256 | 5th Booth window correction in `neg_out[15:8]` |
| 9-bit PP overflow for unsigned 2A | Widen `in_2a` to 10 bits in `partial_product_generator` |

---

## Data Protocol (UART 8N1, 9600 baud)

```
Host → FPGA :  2 × N² bytes
  [0  .. N²-1]   Matrix A, row-major (A[0][0], A[0][1], …, A[N-1][N-1])
  [N² .. 2N²-1]  Matrix B, row-major

FPGA → Host :  N² × 4 bytes
  N² 32-bit results, row-major, LSB-first
```

---

## Compile Order

Files must be compiled in this exact dependency order:

1. `rtl/pkg/uart_pkg.sv`
2. `rtl/primitives/gates.sv`
3. `rtl/primitives/adders.sv`
4. `rtl/primitives/fifo_sync_structured.sv`
5. `rtl/primitives/ksa_32bit.sv`
6. `rtl/multiplier/booth_wallace_8x8.sv`
7. `rtl/systolic/delay_line.sv`
8. `rtl/systolic/pe.sv`
9. `rtl/systolic/global_controller.sv`
10. `rtl/systolic/systolic_array_top.sv`
11. `rtl/uart/uart_rx.sv`
12. `rtl/uart/uart_tx.sv`
13. `rtl/uart/uart_top.sv`
14. `rtl/top/system_top.sv`

---

## Quick Start

### Quartus Prime (synthesis + P&R)
```bash
quartus_sh -t scripts/create_project.tcl
quartus_sh --flow compile systolic_matmul
```

### ModelSim / QuestaSim (simulation)
```bash
# Add your testbench to sim/tb/, then:
./scripts/sim.sh
```

### VCS (simulation)
```bash
vcs -sverilog -f scripts/filelist.f sim/tb/tb_system_top.sv -o simv
./simv
```

---

## Timing Summary (post-fit estimates, Cyclone V)

| Path | Delay |
|---|---|
| Stage 1a (Booth+PPG) → pp_reg | ~2–3 ns |
| Stage 1b (Wallace)   → wt_reg | ~3–4 ns |
| Stage 1c (KSA-16)    → mul_reg | ~2–3 ns |
| Stage 2  (KSA-32)    → acc_reg | ~3–4 ns |
| Fmax (estimated) | ≈ 125 MHz |

---

## Resource Estimate (8×8, 32-bit accumulator)

| Resource | Count (approx) |
|---|---|
| ALMs | ~4 200 |
| Registers (FFs) | ~7 300 |
| Block RAMs | 0 (delay_line forced to logic FFs) |
| DSP blocks | 0 (structural multiplier) |

---

## Revision History

| Version | Change |
|---|---|
| v1.0 | Original 2-stage PE (Booth+Wallace+CSA + KSA-32) |
| v2.0 | 3-stage PE: pp_reg stage between Booth and Wallace |
| v2.1 | en_all pipelined; TOTAL_CYCLES = 3N+2 |
| v3.0 | Stage 1b CSA → KSA-16 |
| v3.1 | a_out/b_out forwarding FFs made free-running |
| v4.0 | 4-stage PE: wt_reg between Wallace and KSA-16; TOTAL_CYCLES = 3N+3 |
| v4.2 | 10-bit pp_raw; 5th Booth window for unsigned B |
