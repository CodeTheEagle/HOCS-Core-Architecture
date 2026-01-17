# HOCS: Hybrid Optical Computing System 🇹🇷

![Status](https://img.shields.io/badge/Status-Prototyping-orange)
![Platform](https://img.shields.io/badge/Platform-Xilinx%20Kria-red)
![Language](https://img.shields.io/badge/Language-Python%20%7C%20Verilog-blue)

## 👋 Hi, I'm Yusuf from Turkey
This is an open-source research project I started with my friends to solve a problem we all hate: **Computers getting hot and slow.**

I am a university student, not a big corporation. I am building this with limited resources. In fact, **my workstation motherboard burned down** last week while running simulations for this project. Currently, I am maintaining this repo from my phone and internet cafes until I can get hardware support. 

So if you see bugs or simple code, please understand that this is a work in progress by a student who is trying to learn.

---

## 💡 What is HOCS?
HOCS stands for **Hybrid Optical Computing System**. 

Right now, AI chips use electrons (electricity) to do math. Electrons have mass, they create friction, and friction creates heat. That's why your GPU fan screams when you play games or train AI.

**Our Idea:** What if we use **Light (Photons)** instead of electrons for the heavy math?
We are designing a special processor unit using **Copper Oxide (CuO)** memristors that interacts with light to perform Matrix Multiplication (the core of all AI) at the speed of light, with almost zero heat.

### How it works (The Plan)
1.  **Input:** Python sends matrix data to the FPGA (Xilinx Kria).
2.  **Conversion:** The FPGA converts digital numbers into Analog Voltage.
3.  **The Magic:** Voltage passes through our custom CuO sensor layer. The physics of the material performs the multiplication instantly.
4.  **Output:** We read the result back, convert it to digital, and send it to the PC.

---

## 📂 Project Structure
Since my PC is broken, I cannot upload the full heavy bitstreams yet. But here is what is currently available:

* `drivers/` -> **hocs_exascale_driver.py**: This is the main control script. It includes a "Benchmark Mode" that stresses your CPU to prove why we need optical computing. (Warning: It might freeze your PC if you set matrix size too high!).
* `simulation/` -> **Behavioral Models**: Python scripts to test the logic before we burn it to hardware.
* `docs/` -> Technical details and my draft whitepaper.

## ⚠️ Known Issues / FAQ
**Q: Is this ChatGPT code?**
A: I used AI tools to help check my English grammar and format the Readme because I want it to look professional. But the **Architecture, the Logic, and the Verilog designs are 100% human-made**.

**Q: Where is the physical chip?**
A: We have the PCB designs ready (Gerber files). We need funding/support to manufacture the first prototype.

**Q: Why is the simulation code simple?**
A: It is a behavioral model to verify logic flow (AXI Stream handshake, etc.). Real physics simulation requires expensive software (Lumerical) which I don't have access to right now.

## 🚀 Roadmap
- [x] Design the Core Architecture
- [x] Write Python Drivers (PYNQ)
- [ ] Find a new computer to finish compilation (Urgent!)
- [ ] Manufacture the PCB
- [ ] First Light (Hardware Test)

## 🤝 Support
If you have an old workstation or FPGA board gathering dust, or if you are a professor who can help with lab access, please reach out. We want to finish this.

**Contact:** https://www.linkedin.com/in/muhammed-yusuf-%C3%A7obano%C4%9Flu-906625392?utm_source=share&utm_campaign=share_via&utm_content=profile&utm_medium=android_app

**Location:** Diyarbakır / Adıyaman, Turkey

## 📂 Project Structure
Here is an overview of the repository organization:

```text
HOCS-Project/
├── backend/                # API & Main Logic
├── compiler/               # <--- YENİ! (PyTorch to Optical-ASM Compiler)
│   └── hocs_torch_bridge.py
├── security/               # <--- YENİ! (Post-Quantum Cryptography)
│   └── post_quantum_auth.c
├── memory/                 # Custom DMA Allocator
├── asm/                    # ARM64 Assembly Kernels
├── cpp_core/               # C++ Physics Engine
├── kernel_driver/          # Linux Kernel Module
├── hdl/                    # Verilog Hardware Design
├── hardware/               # Constraints & PCB
└── README.md
