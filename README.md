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
├── constraints/                 # SDC timing constraints for synthesis
├── doc/                         # Documentation and diagrams
├── lib/                         # Standard cell libraries
│   └── gpdk045/                 # 45nm Generic Process Design Kit (GPDK)
├── rtl/                         # SystemVerilog source files
│   ├── pkg/                     # Packages (UART configurations)
│   ├── primitives/              # Basic blocks (Adders, KSA cells, FIFO, gates)
│   ├── multiplier/              # Booth Encoder, Wallace Tree components
│   ├── systolic/                # PE, Systolic Array Top, Global Controller, Delay lines
│   ├── uart/                    # UART TX/RX, Baud Gen
│   └── top/                     # System Top integration
├── scripts/                     # Xcelium/modelsim simulation and utility scripts
├── sim/                         # Simulation runs, wave dumps, and tests
├── syn/                         # Synthesis workspace
│   ├── synth.tcl                # Main Tcl scripts for Cadence Genus (SDC, constraints)
│   ├── sta.tcl                  # Static Timing Analysis Script
│   ├── synth_core.tcl           # Synthesis for core
│   └── synth_8corners.tcl       # Multi-corner synthesis script
├── tb/                          # Self-checking Testbenches for Xcelium
│   ├── tb_system_top.sv         # Top level testbench
│   └── ...                      # Sub-block testbenches
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
* **Critical Path Delay (WNS):** +2 ps (Met Setup Time)
* **Total Cell Area:** ~192.514 $um^2$
* **Total Power:** ~37.8 mW

## 📝 Author
**Nguyen Thanh Phong**
* B.E. in IC Design, Ho Chi Minh City University of Technology (HCMUT)
* LinkedIn: [linkedin.com/in/nguyenthanhphong]([https://linkedin.com/in/nguyenthanhphong](https://www.linkedin.com/in/nguy%E1%BB%85n-thanh-phong-43b389294/))
