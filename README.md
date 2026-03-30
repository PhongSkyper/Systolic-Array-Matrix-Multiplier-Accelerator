# 8x8 Systolic Array Matrix Multiplier Accelerator

![Language](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)
![EDA](https://img.shields.io/badge/EDA-Cadence_Genus_%7C_Xcelium-red.svg)
![TechNode](https://img.shields.io/badge/Technology-45nm-green.svg)
![Target](https://img.shields.io/badge/Target_Freq-1.0_GHz-orange.svg)

## 📌 Overview
This repository contains the RTL design, verification environment, and synthesis scripts for a high-performance **8x8 Systolic Array Matrix Multiplier**. Designed from a top-down approach, the accelerator targets a highly aggressive **1.0 GHz** operating frequency on a 45nm standard cell library. 

The project addresses memory wall bottlenecks by implementing an **Output Stationary (OS)** dataflow, significantly reducing routing congestion and switching power for the 32-bit accumulation bus.

## 🚀 Key Microarchitecture Features

### 1. High-Speed Processing Element (PE)
To meet the 1.0 GHz strict timing constraints, the standard multiplier was replaced with a highly optimized, 4-stage pipelined datapath:
* **Stage 1a (Booth Encoder):** Radix-4 Modified Booth encoding reduces partial products by 50% (8 rows to 4 rows). Includes a 10-bit PPG to prevent overflow in signed/unsigned operations.
* **Stage 1b (Wallace Tree):** A 3-stage Carry-Save Adder (CSA) Wallace Tree compresses the 4 partial products and negative correction vectors down to 2 rows (Sum and Carry) with $O(\log N)$ delay.
* **Stage 1c (KSA-16 Final Adder):** A 16-bit Kogge-Stone Adder (Parallel Prefix Adder) rapidly resolves the final product.
* **Stage 2 (Accumulator):** A 32-bit KSA performs the in-place accumulation for the Output Stationary dataflow.

### 2. Peripheral & Synchronization
* **UART Interface:** Enables serialized configuration and data read-back via standard PC terminal.
* **Synchronous FIFO:** A 1-cycle latency circular-buffer FIFO resolves the extreme clock domain/bandwidth mismatch between the 1 GHz Systolic Array and the low-baudrate UART.

## 📂 Repository Structure
```text
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

## 🛠️ Prerequisites & EDA Tools
* **Simulation & Verification:** Cadence Xcelium (`xrun`)
* **Logic Synthesis & STA:** Cadence Genus (`genus`)
* **Technology Library:** 45nm Generic Process Design Kit (`gpdk045`)

## ⚙️ How to Run

### 1. Verification (Cadence Xcelium)
The testbenches use a bottom-up approach, featuring randomized stress testing (`$urandom`), corner cases, and mathematical reference models.
To run the simulation for the top-level system, use the provided script or Xcelium directly:

```bash
# Build and run Xcelium simulation using filelist (ensure Cadence env is sourced)
xrun -f scripts/filelist.f tb/tb_system_top.sv +access+rwc -gui
```

### 2. Logic Synthesis & STA (Cadence Genus)
To synthesize the design and generate Area, Power, and Timing (Critical Path) reports using Cadence Genus on the 45nm standard cell library:

```bash
# Navigate to synthesis directory
cd syn/

# Launch Cadence Genus with the synthesis script
genus -f synth.tcl

# Or run the multi-corner script
# genus -f synth_8corners.tcl
```
*Note: Ensure your `synth.tcl` or `synth_core.tcl` is properly configured with your specific 45nm `.lib` paths (`lib/gpdk045/gpdk045_lib/`) and SDC constraints (`create_clock -period 1.0 [get_ports clk]`).*

## 📊 Synthesis Results (Target: 45nm)
*(Note: Update these metrics based on your latest Cadence Genus reports)*
* **Target Frequency:** 1.0 GHz (Clock Period: 1.0 ns)
* **Critical Path Delay (WNS):** +0.05 ns (Met Setup Time)
* **Total Cell Area:** ~TBD $um^2$
* **Dynamic Power:** ~TBD mW
* **Leakage Power:** ~TBD uW

## 📝 Author
**Nguyen Thanh Phong**
* B.E. in IC Design, Ho Chi Minh City University of Technology (HCMUT)
* LinkedIn: [linkedin.com/in/nguyenthanhphong](https://linkedin.com/in/nguyenthanhphong)
