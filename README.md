# HOCS: Hybrid Optical Computing System 🇹🇷

![Status](https://img.shields.io/badge/Status-Prototyping-orange)
![Version](https://img.shields.io/badge/Version-2.4.0--alpha-blue)
![License](https://img.shields.io/badge/License-MIT%20%2B%20CERN-green)

![Platform](https://img.shields.io/badge/Platform-Xilinx%20Kria_KV260-lightgrey)
![Languages](https://img.shields.io/badge/Languages-Python_%7C_C++_%7C_Verilog-blueviolet)
![Framework](https://img.shields.io/badge/AI_Framework-PyTorch-red)
![System](https://img.shields.io/badge/Driver-Linux_Kernel_Module-yellow)
![Deploy](https://img.shields.io/badge/Deploy-Docker_Container-2496ED)

> **Note:** This project is currently being maintained from a mobile device due to a critical hardware failure on the main development workstation. Please excuse any formatting glitches.

---

## 👋 Hi, I'm Yusuf from Turkey
This is an open-source research project aimed at solving the "Thermal Wall" and "Memory Wall" problems in modern AI computing.

I am an undergraduate student building this with limited resources. In fact, **my workstation motherboard burned down** last week while running heavy behavioral simulations for this project. Despite the setbacks, I am committed to finishing this architecture.

This repository hosts the full **logic flow, custom drivers, compilers, and hardware designs (Verilog/PCB)** we have developed so far.

---

## 💡 What is HOCS?
**HOCS** stands for **Hybrid Optical Computing System**.

Modern AI chips use electrons, which create heat and latency. We are designing a prototype processor unit using **Copper Oxide (CuO)** memristors that interacts with light (photons) to perform **Matrix Multiplication (GEMM)** at near light-speed, with drastically reduced thermal output.

### How it works (The Concept)
1.  **Input:** Python (PyTorch) sends matrix data to the FPGA (Xilinx Kria).
2.  **Conversion:** The FPGA converts 32-bit digital numbers into precise Analog Voltage signals via high-speed DACs.
3.  **The Physics:** Voltage is applied across our custom CuO memristor crossbar array. The resulting current, modulated by the memristance (representing weights), performs the multiplication instantly in the analog domain ($I = V \times G$).
4.  **Output:** We read the resulting currents back via ADCs, convert them to digital, and stream them back to the host PC.

---

## 🧠 Theoretical Foundation & Expected Performance

*This section addresses the mathematical model driving our architecture.*

Since physical hardware testing is currently paused due to lack of manufacturing funds, we rely on **mathematical modeling** and **behavioral simulations** to validate our approach.

### The Core Math (Analog MAC)
The fundamental operation is the Analog Multiply-Accumulate (MAC), modeled as:

$$I_{out}[j] = \sum_{i=0}^{N-1} V_{in}[i] \cdot G_{ij}$$

Where:
* $V_{in}$ is the input voltage vector (activations).
* $G_{ij}$ is the conductance matrix of the memristors (weights).
* $I_{out}$ is the resulting current vector.

### Projected Benchmark (Simulated vs. Silicon)
Based on our architectural parameters (128x128 tiles, 1GHz effective analog bandwidth), here are the **theoretical design targets** compared to a standard CPU:

| Metric | Standard CPU (Intel i7) | HOCS Core (Theoretical Target) | Estimated Improvement |
| :--- | :--- | :--- | :--- |
| **Operation Principle** | Digital (CMOS) | Analog (Memristive/Optical) | - |
| **Matrix Latency** | ~50 µs | **< 1 µs** (Analog propagation) | ~50x Faster |
| **Energy per MAC** | ~10 pJ | **~0.1 pJ** (Target) | ~100x More Efficient |
| **Thermal Output** | High (Active Cooling) | **Near-Zero** (Passive) | **Critical Solve** |

> *Disclaimer: These figures are targeted design goals based on simulations. Real-world hardware results will vary.*

---

## 📂 Project Structure (Architecture Map)

Instead of a complex file tree, here is a breakdown of the system modules available in this repository:

| Module / Directory | Category | Role in Architecture |
| :--- | :--- | :--- |
| `backend/` | 🧠 **AI Logic** | Main Python API service & AXI driver logic. |
| `compiler/` | 🔄 **Software** | Transpiler converting PyTorch models to Optical-ASM. |
| `security/` | 🛡️ **Security** | Lattice-based cryptography (Post-Quantum) implementation. |
| `kernel_driver/` | ⚡ **System** | Custom Linux Kernel Module (C) for DMA memory management. |
| `hdl/` | 🔌 **Hardware** | Verilog design files for FPGA logic & SCRAM safety. |
| `asm/` | ⚙️ **Low Level** | Hand-optimized ARM64 Assembly kernels for Kria SoC. |
| `hardware/` | 📐 **PCB** | Schematics, Board Constraints, and Gerber files. |
| `simulation/` | 🧪 **Test** | Behavioral models for verifying AXI handshakes. |

---

## ⚠️ Current Limitations & Validation Status

We believe in transparent engineering. Here is the honest status of our validation efforts:

* ❌ **Physical Hardware Test Results:** Not available yet. PCB designs are ready, but we await funding for manufacturing the first prototype ("First Light").
* ⚠️ **Scientific Validation:** Currently limited to high-level behavioral simulations (Python/C++) to verify logic flow. We lack access to professional physics simulators (e.g., Lumerical).
* ⚠️ **Academic Paper:** A draft whitepaper exists detailing the architecture. A formal academic paper cannot be published without empirical data.

---

## ⚡ Quick Start (Simulation API)

You can run the full HOCS software stack in simulation mode using Docker.

**Prerequisites:** Docker installed on your machine.

1.  **Clone the repository:**
    `git clone https://github.com/CodeTheEagle/HOCS-Core-Architecture.git`
2.  **Build the Docker container:**
    `docker build -t hocs-sim .`
3.  **Run the API server:**
    `docker run -p 8000:8000 hocs-sim`

---

## 🚀 Roadmap

- [x] Design the Core Architecture & Protocols (ICD)
- [x] Develop Linux Kernel Module & Custom DMA
- [x] Build PyTorch Compiler & Security Layer
- [ ] **Urgent:** Secure a new workstation to resume full-scale development.
- [ ] Manufacture the PCB Prototype.
- [ ] Achieve "First Light" and gather real hardware data.

---

## 🤝 Support & Collaboration

This is an ambitious project for a student. If you are a professor with lab access, an engineer with old FPGA gear, or a company interested in this architecture, please reach out. We have the design; we need the tools to build it.

**Contact:** https://www.linkedin.com/in/muhammed-yusuf-%C3%A7obano%C4%9Flu-906625392?utm_source=share&utm_campaign=share_via&utm_content=profile&utm_medium=android_app

**Location:** Diyarbakır / Adıyaman, Turkey

---

## 📚 Citation

If you use HOCS architecture or concepts in your research, please cite as follows:

> Cobanoglu, M. Y. (2026). *HOCS: Hybrid Optical Computing System Architecture*. GitHub Repository. Version 2.4.0-alpha.
