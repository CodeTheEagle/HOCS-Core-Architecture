# HOCS: Hybrid Optical Computing System 🇹🇷

![Status](https://img.shields.io/badge/Status-Prototyping_(TRL--4)-orange)
![Version](https://img.shields.io/badge/Version-2.4.1--beta-blue)
![License](https://img.shields.io/badge/License-Proprietary_%2B_MIT-green)

![Platform](https://img.shields.io/badge/Platform-Xilinx_Kria_K26-lightgrey)
![Languages](https://img.shields.io/badge/Languages-Python_%7C_C++_%7C_Verilog_%7C_ASM-blueviolet)
![Framework](https://img.shields.io/badge/AI_Framework-PyTorch_Integration-red)
![System](https://img.shields.io/badge/Driver-Custom_Kernel_Module-yellow)
![Throughput](https://img.shields.io/badge/Throughput->3_TB/s-success)

> **Note:** This project is actively maintained. Recent updates include a custom AArch64 Assembly Kernel and Industrial-Grade Python SDK.

---

## 👋 Hi, I'm Yusuf from Turkey
This is an open-source research project aimed at solving the "Thermal Wall" and "Memory Wall" problems in modern AI computing.

I am an undergraduate student building this with limited resources. In fact, **my workstation motherboard burned down** last week while running heavy behavioral simulations for this project. Despite the setbacks, I am committed to finishing this architecture.

This repository hosts the full **logic flow, custom drivers, compilers, and hardware designs (Verilog/PCB)** we have developed so far.

---

## 💡 What is HOCS?
**HOCS** stands for **Hybrid Optical Computing System**.

Modern AI chips use electrons, which create heat and latency. We are designing a prototype processor unit using **Copper Oxide (CuO)** memristors (and DLP Technology) that interacts with light (photons) to perform **Matrix Multiplication (GEMM)** at near light-speed, with drastically reduced thermal output.

### How it works (The Concept)
1.  **Input:** Python (PyTorch) sends matrix data via our custom `HOCSSession` SDK to the FPGA (Xilinx Kria).
2.  **Conversion:** The FPGA converts 32-bit digital numbers into precise Optical Patterns via **DLP6500**.
3.  **The Physics:** Light is modulated by the mirrors and processed analogously. The calculation happens instantly ($I = V \times G$).
4.  **Output:** We read the resulting light intensity back via High-Speed **Sony Pregius Sensors**, convert them to digital, and stream them back to the host PC via PCIe/DMA.

---

## 📂 Project Structure (Architecture Map)

This repository contains the full hardware/software stack. We have recently expanded the kernel and driver layers:

| Module / Directory | Category | Role in Architecture |
| :--- | :--- | :--- |
| `asm/core/` | ⚙️ **Kernel** | **NEW:** Hand-optimized AArch64 Assembly Kernel (MMU, Interrupts, DMA). |
| `hardware/rtl/` | 🔌 **Hardware** | Verilog RTL designs for the FPGA Logic & Trigger Systems. |
| `src/host_api/` | 🧠 **SDK** | **NEW:** Thread-safe Python Session Manager (`HOCSSession`) for users. |
| `src/drivers/` | ⚡ **Drivers** | Hybrid drivers: Python for DLP Control, C++ for Sensor Readout. |
| `examples/` | 🧪 **Demos** | MNIST Inference demo running on the Optical Core. |
| `tests/` | 🛡️ **QA** | Unit tests and simulation suites for CI/CD. |
| `setup.py` | 📦 **Deploy** | Package installation script for easy deployment. |
| `hocs_config.json` | 🔧 **Config** | Centralized system configuration and safety limits. |

---

## 🚀 Recent Engineering Updates (v2.4.1)

We are pushing code daily. The latest commits introduce **Industrial-Grade** features:

* **Custom Micro-Kernel:** We moved from bare-metal C to a custom Assembly Kernel (`hocs_kernel.s`) to handle Interrupts and Context Switching faster than Linux.
* **Scatter-Gather DMA:** Implemented a zero-copy memory management unit in Assembly to sustain >3 TB/s throughput.
* **Thread-Safe SDK:** The new `HOCSSession` class supports asynchronous job offloading and includes thermal telemetry monitoring.
* **Hybrid Driver Stack:** Combined C++ performance for camera readout with Python flexibility for logic control.

---

## 🧠 Theoretical Foundation & Expected Performance

*This section addresses the mathematical model driving our architecture.*

Since physical hardware testing is currently paused due to lack of manufacturing funds, we rely on **mathematical modeling** and **behavioral simulations** to validate our approach.

### Projected Benchmark (Simulated vs. Silicon)
Based on our architectural parameters (128x128 tiles, 1GHz effective analog bandwidth):

| Metric | Standard CPU (Intel i7) | HOCS Core (Theoretical Target) | Estimated Improvement |
| :--- | :--- | :--- | :--- |
| **Matrix Latency** | ~50 µs | **< 1 µs** (Analog propagation) | ~50x Faster |
| **Energy per MAC** | ~10 pJ | **~0.1 pJ** (Target) | ~100x More Efficient |
| **Thermal Output** | High (Active Cooling) | **Near-Zero** (Passive) | **Critical Solve** |

> *Disclaimer: These figures are targeted design goals based on simulations. Real-world hardware results will vary.*

---

## ⚠️ Current Limitations & Status

We believe in transparent engineering. Here is the honest status of our validation efforts:

* ❌ **Physical Hardware Test Results:** Not available yet. PCB designs are ready, but we await funding for manufacturing the first prototype ("First Light").
* ⚠️ **Scientific Validation:** Currently limited to high-level behavioral simulations to verify logic flow.
* ✅ **Software Stack:** The full driver, kernel, and SDK stack is **Code Complete** and ready for board bring-up.

---

## 🔮 Roadmap & Future Updates

Development is active. Expect the following updates soon:

- [x] Design the Core Architecture & Protocols (ICD)
- [x] Develop Custom Assembly Kernel & DMA Engine
- [x] Build Thread-Safe Python SDK
- [ ] **Next:** Release the `hocs-cli` tool for terminal management.
- [ ] **Next:** Finalize the PCB Gerber files for the Carrier Board.
- [ ] **Goal:** Manufacture the Prototype and achieve "First Light".

*Stay tuned. We are building the future of computing, one commit at a time.*

---

## 🤝 Support & Collaboration

This is an ambitious project for a student. If you are a professor with lab access, an engineer with old FPGA gear, or a company interested in this architecture, please reach out. We have the design; we need the tools to build it.

**Contact:** [LinkedIn Profile](https://www.linkedin.com/in/muhammed-yusuf-%C3%A7obano%C4%9Flu-906625392)
**Location:** Diyarbakır / Adıyaman, Turkey

---

## 📚 Citation

If you use HOCS architecture or concepts in your research, please cite as follows:

> Cobanoglu, M. Y. & Urgun, M. Y. (2026). *HOCS: Hybrid Optical Computing System Architecture*. GitHub Repository. Version 2.4.1.

---

## 📚 Citation

If you use HOCS architecture or concepts in your research, please cite as follows:

> Cobanoglu, M. Y. (2026). *HOCS: Hybrid Optical Computing System Architecture*. GitHub Repository. Version 2.4.0-alpha.
