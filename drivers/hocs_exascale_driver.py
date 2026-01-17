#!/usr/bin/env python3
"""
HOCS (Hybrid Optical Computing System) - High Performance Simulation Driver
Author: Muhammed Yusuf Cobanoglu
License: MIT
Description:
    This driver simulates the workload dispatching mechanism for the HOCS architecture.
    It demonstrates the computational bottleneck of traditional silicon CPUs vs.
    the theoretical throughput of the Optical Core.

    Usage:
    python hocs_exascale_driver.py --size 2048 --batches 5 --simulate_hw
"""

import numpy as np
import time
import sys
import os
import argparse
import logging
import random

# --- CONFIGURATION & CONSTANTS ---
VERSION = "0.9.2-Alpha"
FPGA_BASE_ADDR = 0x40000000  # Virtual Base Address for AXI DMA
REG_CONTROL    = 0x00        # Control Register Offset
REG_STATUS     = 0x04        # Status Register Offset
REG_SIZE_X     = 0x08        # Matrix Dimension X
REG_SIZE_Y     = 0x0C        # Matrix Dimension Y

# Setup Professional Logging
logging.basicConfig(
    level=logging.INFO,
    format='[HOCS-KERNEL] %(asctime)s - %(levelname)s - %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger("HOCS_Driver")

class VirtualFPGAInterface:
    """
    Simulates the Low-Level Register Access to Xilinx Kria FPGA.
    In the real hardware, this would use 'mmap' to access physical memory.
    """
    def __init__(self):
        self.registers = {
            FPGA_BASE_ADDR + REG_CONTROL: 0x0,
            FPGA_BASE_ADDR + REG_STATUS:  0x1, # 1 = IDLE
            FPGA_BASE_ADDR + REG_SIZE_X:  0,
            FPGA_BASE_ADDR + REG_SIZE_Y:  0
        }
        self.connected = False

    def connect(self):
        logger.info("Handshaking with HOCS FPGA Core...")
        time.sleep(0.5) # Simulate bus latency
        self.connected = True
        logger.info(f"Hardware Linked. Device ID: 7x_CuO_Processing_Unit_v1")

    def write_register(self, offset, value):
        if not self.connected:
            raise ConnectionError("FPGA Core not connected.")
        addr = FPGA_BASE_ADDR + offset
        self.registers[addr] = value
        # logger.debug(f"write_reg: [0x{addr:X}] <= {value}")

    def read_register(self, offset):
        addr = FPGA_BASE_ADDR + offset
        return self.registers.get(addr, 0x0)

    def trigger_dma(self):
        """Simulates the AXI Stream DMA transfer trigger."""
        self.write_register(REG_CONTROL, 0x2) # START bit
        time.sleep(0.002) # Optical latency is negligible
        self.write_register(REG_CONTROL, 0x0) # RESET bit

class PowerEfficiencyMonitor:
    """Calculates theoretical energy savings compared to standard GPU/CPU."""
    def __init__(self):
        self.silicon_joules_per_op = 10e-12 # Approx 10 pJ per FLOP for CPU
        self.optical_joules_per_op = 1e-15  # Approx 1 fJ per FLOP for HOCS (Theoretical)

    def report(self, ops_count):
        silicon_cost = ops_count * self.silicon_joules_per_op
        optical_cost = ops_count * self.optical_joules_per_op
        saving = silicon_cost / optical_cost
        
        print(f"\n--- ⚡ ENERGY EFFICIENCY REPORT ---")
        print(f"   Silicon Energy Cost : {silicon_cost:.6f} Joules")
        print(f"   HOCS Optical Cost   : {optical_cost:.9f} Joules")
        print(f"   Efficiency Gain     : {saving:.0f}x More Efficient")
        print(f"----------------------------------")

class HOCSDriverManager:
    """
    Main Orchestrator for Data Pipeline.
    Manages Memory -> DMA -> FPGA -> Readback flow.
    """
    def __init__(self, matrix_size, use_gpu_simulation=False):
        self.matrix_size = matrix_size
        self.fpga = VirtualFPGAInterface()
        self.power_mon = PowerEfficiencyMonitor()
        self.use_gpu = use_gpu_simulation
        
        logger.info(f"Initializing HOCS Driver v{VERSION}")
        logger.info(f"Target Matrix Size: {matrix_size}x{matrix_size}")

    def _check_system_resources(self):
        """Pre-flight check for available RAM."""
        # Simple heuristic check
        estimated_ram = (self.matrix_size ** 2) * 8 * 3 # 3 matrices (A, B, C), float64
        estimated_mb = estimated_ram / (1024**2)
        logger.info(f"Estimated VRAM Requirement: {estimated_mb:.2f} MB")
        
        if estimated_mb > 4000:
            logger.warning("High Memory Usage Detected! System may throttle.")

    def generate_workload(self):
        """Generates random tensors for testing."""
        logger.info("Generating Synthetic Tensors (Float32)...")
        try:
            A = np.random.rand(self.matrix_size, self.matrix_size).astype(np.float32)
            B = np.random.rand(self.matrix_size, self.matrix_size).astype(np.float32)
            return A, B
        except MemoryError:
            logger.critical("Host System Out of Memory. This highlights the need for edge-processing.")
            sys.exit(1)

    def run_benchmark(self, batches=1, run_silicon_test=True):
        self.fpga.connect()
        self._check_system_resources()

        # Set Hardware Registers
        self.fpga.write_register(REG_SIZE_X, self.matrix_size)
        self.fpga.write_register(REG_SIZE_Y, self.matrix_size)

        total_ops = 0
        
        print("\n" + "="*60)
        print(f"🚀 STARTING WORKLOAD DISPATCH | Batches: {batches}")
        print("="*60)

        for i in range(batches):
            logger.info(f"Processing Batch [{i+1}/{batches}]...")
            
            A, B = self.generate_workload()
            
            # --- 1. SILICON BOTTLENECK DEMO ---
            if run_silicon_test:
                logger.info(">> Running on HOST CPU (Silicon Mode) for comparison...")
                t0 = time.time()
                
                # THE HEAVY LIFTING: This creates heat and lag on standard PCs
                C_silicon = np.dot(A, B)
                
                t1 = time.time()
                dt_silicon = t1 - t0
                logger.warning(f"Silicon Calculation Time: {dt_silicon:.4f} sec")
                
                if dt_silicon > 0.5:
                    logger.info("   -> High Latency Detected. Electronic interconnect limit reached.")
            
            # --- 2. OPTICAL CORE SIMULATION ---
            logger.info(">> Dispatching to HOCS Optical Core (DMA Transfer)...")
            self.fpga.trigger_dma()
            
            # Theoretical Optical Time (Speed of light + DAC/ADC latency)
            dt_optical = 0.0005 # 500 microseconds
            logger.info(f"Optical Core Execution Time: {dt_optical:.6f} sec")
            
            # Calculate FLOPs for this batch
            ops = 2 * (self.matrix_size ** 3)
            total_ops += ops

            # Cleanup to save RAM
            del A, B
            if run_silicon_test: del C_silicon

        print("\n" + "="*60)
        logger.info("Workload Completed Successfully.")
        self.power_mon.report(total_ops)

def parse_arguments():
    parser = argparse.ArgumentParser(description="HOCS Hardware Driver & Benchmark Tool")
    parser.add_argument('--size', type=int, default=1024, help='Matrix Dimension (NxN)')
    parser.add_argument('--batches', type=int, default=3, help='Number of batches to run')
    parser.add_argument('--skip_cpu', action='store_true', help='Skip the CPU stress test (Fast Mode)')
    return parser.parse_args()

if __name__ == "__main__":
    try:
        args = parse_arguments()
        
        # ASCII ART LOGO
        print(r"""
  _   _  ___   ____ ___ 
 | | | |/ _ \ / ___/ __|
 | |_| | | | | |   \__ \
 |  _  | |_| | |___|___/
 |_| |_|\___/ \____|___/  v0.9
        """)
        
        driver = HOCSDriverManager(args.size)
        driver.run_benchmark(batches=args.batches, run_silicon_test=not args.skip_cpu)
        
    except KeyboardInterrupt:
        print("\n[!] Process Interrupted by User.")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Critical Failure: {str(e)}")
        sys.exit(1)
        
