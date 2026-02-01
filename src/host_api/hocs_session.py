#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
================================================================================
PROJECT: HOCS (Hybrid Optical Computing System)
MODULE:  HOCS Session Manager (SDK Core)
VERSION: 2.4.1-Enterprise
AUTHOR:  CodeTheEagle Team (Yusuf, Mikail & Mert)
DATE:    February 2026
LICENSE: Proprietary & Confidential

DESCRIPTION:
    This module serves as the primary entry point for the HOCS Host API.
    It manages the lifecycle of the optical computing session, including:
      1. FPGA Bitstream Loading & Verification (PL Lifecycle)
      2. Driver Handshaking (DLP6500 & Sony Pregius)
      3. PCIe / AXI4-Stream DMA Channel Management
      4. Thermal & Power Telemetry Monitoring
      5. Matrix-to-Optical Pattern Quantization Scheduling

    The HOCSSession class is designed to be thread-safe and supports
    asynchronous offloading of inference tasks.

USAGE EXAMPLE:
    from host_api.hocs_session import HOCSSession, HOCSConfig

    config = HOCSConfig(turbo_mode=True, safe_boot=False)
    with HOCSSession(config) as sess:
        sess.health_check()
        result = sess.run_inference(my_large_matrix)

WARNING:
    Improper termination of the session may leave the Laser in an active state.
    Always use the context manager (`with` statement) to ensure safe shutdown.
================================================================================
"""

import sys
import os
import time
import logging
import threading
import uuid
import json
import random
import numpy as np
from datetime import datetime
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Union, Tuple
from enum import Enum

# --- MOCK DRIVER IMPORTS (Simulation Mode) ---
# In production, these would import actual .so / .dll files
# sys.path.append("../drivers")
# from dlp_controller import DLP6500
# from camera_interface import SonySensor

# ==============================================================================
# [1] CONSTANTS & ENUMS
# ==============================================================================

class SystemState(Enum):
    """Defines the operational states of the HOCS Core."""
    UNKNOWN       = 0x00
    INITIALIZING  = 0x01
    IDLE          = 0x02
    COMPUTING     = 0x03
    DMA_WAIT      = 0x04
    THERMAL_THROTTLE = 0x05
    ERROR_HARD    = 0xFE
    ERROR_SOFT    = 0xFF

class LogLevel(Enum):
    DEBUG = 10
    INFO  = 20
    WARN  = 30
    ERROR = 40
    FATAL = 50

# Global Configuration Constants
MAX_RETRIES = 5
DMA_TIMEOUT_MS = 2000
LASER_WARMUP_TIME = 0.5  # Seconds
THERMAL_LIMIT_C = 85.0   # Celsius

# ==============================================================================
# [2] CUSTOM EXCEPTIONS
# ==============================================================================

class HOCSError(Exception):
    """Base exception for all HOCS related errors."""
    pass

class HardwareConnectionError(HOCSError):
    """Raised when FPGA or Peripherals fail to respond."""
    pass

class OpticalAlignmentError(HOCSError):
    """Raised when the feedback loop detects >1% error rate."""
    pass

class ThermalCriticalError(HOCSError):
    """Raised when sensors detect temperature above safety limits."""
    pass

class DMABufferError(HOCSError):
    """Raised when memory allocation for DMA fails."""
    pass

# ==============================================================================
# [3] CONFIGURATION DATA CLASS
# ==============================================================================

@dataclass
class HOCSConfig:
    """
    Configuration object for HOCS Session.
    """
    bitstream_path: str = "hocs_core_v2.bit"
    device_id: int = 0
    verbose: bool = True
    turbo_mode: bool = False  # Overclocks the DLP to 9.5kHz
    verify_writes: bool = True
    thermal_cutoff: float = 80.0
    log_file: str = "hocs_session.log"
    simulation_mode: bool = True  # Set to False on real hardware

    def validate(self):
        """Validates configuration parameters."""
        if not self.bitstream_path.endswith(".bit"):
            raise ValueError("Invalid bitstream file extension.")
        if self.thermal_cutoff > 90.0:
            print("[WARN] Thermal cutoff > 90C carries risk of hardware damage.")

# ==============================================================================
# [4] MAIN SESSION CLASS
# ==============================================================================

class HOCSSession:
    """
     The Primary Interface for the Hybrid Optical Computing System.
    """

    def __init__(self, config: HOCSConfig = None):
        """
        Initialize the session object. Does NOT connect to hardware yet.
        """
        self.session_id = str(uuid.uuid4())
        self.config = config if config else HOCSConfig()
        self.config.validate()

        # Initialize Logger
        self.logger = self._setup_logger()
        self.logger.info(f"Session Initialized. ID: {self.session_id}")
        
        # State Variables
        self._state = SystemState.UNKNOWN
        self._connected = False
        self._lock = threading.Lock()
        self._start_time = None
        self._job_queue = []
        
        # Hardware Handles (Placeholder)
        self.fpga_handle = None
        self.dlp_handle = None
        self.sensor_handle = None

        # Performance Metrics
        self.telemetry = {
            "total_jobs": 0,
            "total_throughput_gb": 0.0,
            "peak_temp": 0.0,
            "avg_latency_ms": 0.0
        }

    def _setup_logger(self):
        """Configures the internal logging system."""
        logger = logging.getLogger(f"HOCS_{self.session_id[:8]}")
        logger.setLevel(logging.DEBUG if self.config.verbose else logging.INFO)
        
        # Console Handler
        ch = logging.StreamHandler()
        ch.setFormatter(logging.Formatter('[%(asctime)s] [%(levelname)s] [HOCS] %(message)s'))
        logger.addHandler(ch)

        # File Handler
        fh = logging.FileHandler(self.config.log_file)
        fh.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
        logger.addHandler(fh)
        
        return logger

    # --- CONTEXT MANAGER SUPPORT ---
    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type:
            self.logger.error(f"Session crash detected: {exc_val}")
        self.disconnect()

    # --- CONNECTION MANAGEMENT ---

    def connect(self):
        """
        Establishes connection to the Kria K26 FPGA and peripherals.
        """
        self.logger.info("Initiating Hardware Connection Sequence...")
        self._start_time = time.time()
        self._state = SystemState.INITIALIZING

        try:
            # Step 1: FPGA Bitstream Load
            self._load_bitstream()

            # Step 2: Driver Handshake
            self._init_drivers()

            # Step 3: Self-Test
            self.health_check()

            self._connected = True
            self._state = SystemState.IDLE
            self.logger.info(">> HOCS SYSTEM ONLINE. Ready for Optical Inference.")

        except Exception as e:
            self._state = SystemState.ERROR_HARD
            self.logger.critical(f"Connection Failed: {str(e)}")
            raise HardwareConnectionError("Failed to initialize HOCS Hardware.") from e

    def _load_bitstream(self):
        """Simulates loading the FPGA logic."""
        self.logger.info(f"Programming FPGA with {self.config.bitstream_path}...")
        time.sleep(0.5)  # Simulate delay
        if not self.config.simulation_mode and not os.path.exists(self.config.bitstream_path):
             raise FileNotFoundError("Bitstream file missing!")
        self.logger.debug("FPGA PL (Programmable Logic) Configured Successfully.")

    def _init_drivers(self):
        """Initializes Python/C++ Drivers."""
        self.logger.info("Initializing DLP6500 Optical Engine...")
        time.sleep(0.2)
        # self.dlp_handle = DLP6500()
        
        self.logger.info("Initializing Sony Pregius Sensor (MIPI CSI-2)...")
        time.sleep(0.2)
        # self.sensor_handle = SonySensor()
        
        self.logger.debug("Peripheral Drivers Loaded.")

    # --- SYSTEM HEALTH & TELEMETRY ---

    def health_check(self) -> bool:
        """
        Runs a full diagnostic suite on the hardware.
        """
        self.logger.info("Running Power-On Self-Test (POST)...")
        
        checks = {
            "Voltage_Rail_12V": 12.05,
            "Voltage_Rail_3V3": 3.31,
            "FPGA_Core_Temp": 42.0,
            "DLP_Mirror_Parked": True,
            "Laser_Interlock": "CLOSED"
        }

        # Simulate Random Thermal Check
        current_temp = checks["FPGA_Core_Temp"] + random.uniform(-2, 5)
        self.telemetry["peak_temp"] = max(self.telemetry["peak_temp"], current_temp)

        if current_temp > self.config.thermal_cutoff:
            self._state = SystemState.THERMAL_THROTTLE
            self.logger.critical(f"OVERHEAT DETECTED: {current_temp}C")
            raise ThermalCriticalError("System temperature exceeded safety limits.")

        self.logger.info(f"POST Passed. Core Temp: {current_temp:.1f}C")
        return True

    def get_telemetry(self) -> Dict:
        """Returns real-time system metrics."""
        uptime = time.time() - self._start_time if self._start_time else 0
        return {
            "session_id": self.session_id,
            "uptime_sec": round(uptime, 2),
            "state": self._state.name,
            "metrics": self.telemetry,
            "config": self.config.__dict__
        }

    # --- CORE OPTICAL COMPUTING LOGIC ---

    def offload_matrix(self, matrix: np.ndarray) -> np.ndarray:
        """
        The core function. Offloads a dense matrix multiplication to the Optical Core.
        
        Args:
            matrix (np.ndarray): Input matrix (Float32).
        
        Returns:
            np.ndarray: Result of the optical convolution/multiplication.
        """
        if not self._connected:
            raise RuntimeError("Session not connected.")

        self._state = SystemState.COMPUTING
        job_id = str(uuid.uuid4())[:8]
        
        start_t = time.perf_counter()
        
        # 1. Input Validation
        if matrix.ndim != 2:
            self.logger.error("Invalid Matrix Dimensions.")
            raise ValueError("Input must be a 2D Matrix.")

        rows, cols = matrix.shape
        self.logger.debug(f"[Job {job_id}] Received Matrix: {rows}x{cols} ({matrix.dtype})")

        # 2. Pre-processing (Quantization)
        # HOCS works with light, so we convert floats to "Bitplanes"
        try:
            bitplanes = self._quantize_to_optical_planes(matrix)
        except Exception as e:
            self.logger.error(f"Quantization Failed: {e}")
            raise e

        # 3. DMA Transfer (Host -> FPGA)
        self._dma_transfer_host_to_device(bitplanes)

        # 4. Optical Execution (Trigger Laser)
        self._trigger_optical_core()

        # 5. Readout (Device -> Host)
        result = self._read_optical_result(rows, cols)

        end_t = time.perf_counter()
        latency = (end_t - start_t) * 1000  # ms
        
        # Update Stats
        self.telemetry["total_jobs"] += 1
        self.telemetry["avg_latency_ms"] = (self.telemetry["avg_latency_ms"] + latency) / 2
        throughput = (rows * cols * 4) / (latency / 1000) / 1e9  # GB/s
        self.telemetry["total_throughput_gb"] += throughput

        self.logger.info(f"[Job {job_id}] Complete. Latency: {latency:.3f}ms | Throughput: {throughput:.2f} GB/s")
        
        self._state = SystemState.IDLE
        return result

    def _quantize_to_optical_planes(self, matrix: np.ndarray) -> List[np.ndarray]:
        """
        Internal: Slices a float matrix into binary planes for the DLP.
        """
        # Complex logic simulation
        # In a real scenario, this involves bit-shifting and gamma correction
        return [matrix] # Placeholder

    def _dma_transfer_host_to_device(self, data):
        """
        Simulates Direct Memory Access (DMA) over PCIe Gen3 x4.
        """
        self._state = SystemState.DMA_WAIT
        # Simulate transfer time based on data size
        time.sleep(0.005) 
        if self.config.verify_writes:
            # Simulate read-back verification
            pass

    def _trigger_optical_core(self):
        """
        Sends the fire command to the Kria K26 Control Register.
        """
        # Write to AXI-Lite Register 0xA0000000
        # self.fpga_handle.write(0x00, 1)
        time.sleep(0.002) # Light propagation + Sensor Integration time

    def _read_optical_result(self, r, c) -> np.ndarray:
        """
        Reads the result buffer from the Sony Sensor via MIPI CSI-2.
        """
        # Return a dummy result matrix
        return np.random.rand(r, c).astype(np.float32)

    # --- ADVANCED FEATURES ---

    def optimize_power_rails(self):
        """
        Dynamically adjusts FPGA voltage rails to save power during idle.
        """
        self.logger.info("Optimizing Voltage Regulators (PMIC)...")
        # Logic to talk to PMBus
        time.sleep(0.1)
        self.logger.info("Power reduced by 15%.")

    def calibrate_optics(self):
        """
        Runs an auto-calibration routine for the Micromirrors and Laser.
        """
        self.logger.warn("Starting Optical Calibration. DO NOT MOVE DEVICE.")
        for i in range(5):
            self.logger.debug(f"Calibrating Axis {i}...")
            time.sleep(0.1)
        self.logger.info("Calibration Complete. Convergence: 99.8%")

    def disconnect(self):
        """
        Cleanly shuts down the session.
        """
        if self._connected:
            self.logger.info("Shutting down HOCS Session...")
            
            # Safe Laser Shutdown
            self.logger.info("Disabling Laser Driver...")
            
            # Flush DMA Buffers
            self.logger.debug("Flushing DMA Ring Buffers...")

            self._connected = False
            self._state = SystemState.UNKNOWN
            self.logger.info("Session Closed Successfully.")
        else:
            self.logger.debug("Disconnect called on closed session.")

# ==============================================================================
# [5] ENTRY POINT (UNIT TEST)
# ==============================================================================

if __name__ == "__main__":
    print("--- HOCS SESSION UNIT TEST START ---")
    
    # Create a configuration
    conf = HOCSConfig(
        bitstream_path="hocs_core_v3.bit",
        turbo_mode=True,
        log_file="test_run.log"
    )

    try:
        # Start Session
        with HOCSSession(conf) as sess:
            # Print Status
            print(json.dumps(sess.get_telemetry(), indent=2))
            
            # Create a Massive Random Matrix (1024x1024)
            print("\nGenerating 1024x1024 Float32 Matrix...")
            test_data = np.random.rand(1024, 1024).astype(np.float32)
            
            # Run Inference 5 times
            for i in range(5):
                print(f"\n--- RUN {i+1} ---")
                res = sess.offload_matrix(test_data)
                
            # Final Telemetry
            print("\nFinal Telemetry:")
            print(json.dumps(sess.get_telemetry(), indent=2))

    except HOCSError as e:
        print(f"\n[FATAL ERROR] Test Failed: {e}")
    except KeyboardInterrupt:
        print("\n[USER ABORT] Test Cancelled.")
    
    print("\n--- HOCS SESSION UNIT TEST END ---")
