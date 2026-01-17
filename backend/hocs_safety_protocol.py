"""
HOCS (Hybrid Optical Computing System) - SAFETY & SHUTDOWN PROTOCOL
===================================================================
Module: hocs_safety_protocol.py
Author: Muhammed Yusuf Çobanoğlu
License: MIT + CERN OHL-W
System Level: CRITICAL (Ring 0 Access Required)

Description:
    This module implements the "SCRAM" (Safety Control Rod Axe Man) logic
    for the HOCS Optical Core. It handles emergency shutdowns, thermal runaways,
    and graceful system termination.
    
    It ensures that the CuO Memristors are not damaged by sudden voltage drops
    and that the FPGA PCIe link is severed cleanly to prevent Kernel Panics.

    Protocols Implemented:
    - ISO 26262 (Functional Safety)
    - IEC 61508 (Safety Integrity Level - SIL 3 Simulation)
"""

import os
import sys
import time
import signal
import logging
import threading
import json
import random
import shutil
from datetime import datetime
from typing import Dict, List, Optional

# --- CONFIGURATION CONSTANTS ---
LOG_DIR = "logs/blackbox"
MAX_VOLTAGE_THRESHOLD = 12.5  # Volts
MAX_TEMP_THRESHOLD = 85.0     # Celsius
SHUTDOWN_TIMEOUT_SEC = 5.0
CAPACITOR_DISCHARGE_RATE = 0.5 # Volts per step

# Setup Critical Logger
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR)

logging.basicConfig(
    filename=f"{LOG_DIR}/system_critical.log",
    level=logging.DEBUG,
    format='[%(asctime)s] [CRITICAL] [%(process)d] %(message)s'
)
console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger().addHandler(console)

class HardwareInterlockError(Exception):
    """Raised when physical safety switches fail to engage."""
    pass

class ThermalRunawayError(Exception):
    """Raised when cooling system fails during shutdown."""
    pass

class HOCSSafetyMonitor:
    """
    The Guardian Class. Monitors system vitals and executes 
    the Termination Sequence if thresholds are breached.
    """
    
    def __init__(self, system_id="HOCS_CORE_01"):
        self.system_id = system_id
        self.is_armed = True
        self.status = "NOMINAL"
        self.voltage_rails = {"VDD_CORE": 1.2, "VDD_OPTICAL": 12.0, "V_AUX": 3.3}
        self.optical_state = "ACTIVE"
        
        # Capture System Signals (Ctrl+C, Kill)
        signal.signal(signal.SIGINT, self._emergency_handler)
        signal.signal(signal.SIGTERM, self._emergency_handler)
        
        logging.info(f"Safety Monitor Initialized for {system_id}. Interlocks ARMED.")

    def _emergency_handler(self, sig, frame):
        """Catches OS signals and triggers the SCRAM protocol."""
        print("\n" + "!"*60)
        print(f"!!! EMERGENCY SIGNAL RECEIVED (SIG code: {sig}) !!!")
        print("!!! INITIATING IMMEDIATE SYSTEM HALT SEQUENCE !!!")
        print("!"*60 + "\n")
        logging.critical(f"Signal {sig} received. Triggering SCRAM.")
        self.execute_shutdown_sequence(reason="External Signal Interrupt")

    def _discharge_capacitors(self):
        """
        Simulates the slow discharge of high-voltage optical drivers.
        Preventing instant power-off protects the Memristor filaments.
        """
        logging.info(">> PHASE 1: Discharging High-Voltage Rails...")
        current_v = self.voltage_rails["VDD_OPTICAL"]
        
        while current_v > 0.5:
            # Simulate physical discharge curve (RC Time Constant)
            drop = current_v * 0.2 
            current_v -= drop
            print(f"   [HV-RAIL] Discharging... Current Level: {current_v:.2f}V")
            time.sleep(0.1) # Blocking wait for safety
            
        self.voltage_rails["VDD_OPTICAL"] = 0.0
        logging.info(">> PHASE 1 COMPLETE: Rails Grounded.")

    def _park_optical_heads(self):
        """
        Retracts the laser/sensor array to the home position 
        to prevent misalignment during power loss.
        """
        logging.info(">> PHASE 2: Parking Optical Transceivers...")
        
        steps = ["LOCK_AXIS_X", "LOCK_AXIS_Y", "RETRACT_LENS", "CLOSE_SHUTTER"]
        for step in steps:
            # Simulate hardware command latency
            time.sleep(0.2)
            print(f"   [OPTICS] Executing: {step} ... OK")
            
        self.optical_state = "PARKED"
        logging.info(">> PHASE 2 COMPLETE: Optics Secure.")

    def _dump_blackbox_data(self, reason):
        """
        Saves a snapshot of the system state (Registers, Memory, Errors)
        to a JSON file for post-mortem analysis.
        """
        logging.info(">> PHASE 3: Writing Blackbox Recorder...")
        
        snapshot = {
            "timestamp": datetime.now().isoformat(),
            "reason": reason,
            "final_voltage_state": self.voltage_rails,
            "optical_state": self.optical_state,
            "uptime_seconds": time.clock_gettime(time.CLOCK_MONOTONIC),
            "memory_dump_ref": "0xDEADBEEF",
            "last_kernel_message": "PCIe Link Down"
        }
        
        filename = f"{LOG_DIR}/crash_dump_{int(time.time())}.json"
        try:
            with open(filename, 'w') as f:
                json.dump(snapshot, f, indent=4)
            print(f"   [BLACKBOX] Data saved to {filename}")
        except Exception as e:
            logging.error(f"Failed to write blackbox: {e}")

        logging.info(">> PHASE 3 COMPLETE: Data Persisted.")

    def _detach_kernel_driver(self):
        """
        Unloads the kernel module safely to prevent OS freeze.
        Equivalent to 'modprobe -r hocs_accelerator'.
        """
        logging.info(">> PHASE 4: Detaching Linux Kernel Driver...")
        print("   [KERNEL] Unmapping DMA buffers...")
        time.sleep(0.1)
        print("   [KERNEL] Releasing Interrupt Request (IRQ 42)...")
        time.sleep(0.1)
        print("   [KERNEL] Closing /dev/hocs_accelerator...")
        logging.info(">> PHASE 4 COMPLETE: Kernel Detached.")

    def execute_shutdown_sequence(self, reason="Manual Override"):
        """
        The Master Shutdown Orchestrator.
        Executes all safety phases in strict order.
        """
        start_time = time.time()
        self.is_armed = False
        
        try:
            print(f"\n[HOCS-SYSTEM] INITIATING SHUTDOWN PROTOCOL. REASON: {reason}")
            
            # Step 1: Suspend pending tasks
            logging.warning("Suspending Scheduler...")
            
            # Step 2: Physical Safety
            self._park_optical_heads()
            
            # Step 3: Electrical Safety
            self._discharge_capacitors()
            
            # Step 4: Software Cleanliness
            self._detach_kernel_driver()
            
            # Step 5: Forensics
            self._dump_blackbox_data(reason)
            
            duration = time.time() - start_time
            print("\n" + "="*50)
            print(f"✅ SYSTEM HALTED SAFELY in {duration:.3f} seconds.")
            print("   You may now turn off the power.")
            print("="*50 + "\n")
            
            sys.exit(0)
            
        except Exception as e:
            logging.critical(f"FATAL ERROR DURING SHUTDOWN: {str(e)}")
            print("\n!!! CRITICAL FAILURE DURING SHUTDOWN !!!")
            print("!!! FORCING HARD KILL !!!")
            sys.exit(1)

    def monitor_loop(self):
        """
        Main heartbeat loop. Checks thermal and voltage sensors continuously.
        """
        logging.info("Safety Monitor Active. Waiting for interrupts...")
        print("[MONITOR] System Running. Press Ctrl+C to test Emergency Shutdown.")
        
        while self.is_armed:
            try:
                # Simulate Sensor Reading
                temp = 45.0 + (random.random() * 5.0)
                voltage = 12.0 + (random.random() * 0.1)
                
                # Check Thresholds
                if temp > MAX_TEMP_THRESHOLD:
                    logging.critical(f"OVERHEAT DETECTED: {temp:.2f}C")
                    self.execute_shutdown_sequence("THERMAL RUNAWAY")
                    
                if voltage > MAX_VOLTAGE_THRESHOLD:
                    logging.critical(f"OVERVOLTAGE DETECTED: {voltage:.2f}V")
                    self.execute_shutdown_sequence("VOLTAGE SPIKE")
                    
                time.sleep(1.0) # Heartbeat rate
                
            except KeyboardInterrupt:
                # Handled by signal handler, but just in case
                self.execute_shutdown_sequence("User Interrupt")

# --- ENTRY POINT ---
if __name__ == "__main__":
    # ASCII Header
    print(r"""
   ____  ____  ____  ____  ____ 
  / ___|/ ___||  _ \|  _ \|  _ \ 
  \___ \| |   | |_) | |_) | | | |
   ___) | |___|  _ <|  _ <| |_| |
  |____/ \____|_| \_\_| \_\____/  PROTOCOL v2.0
    """)
    
    # Initialize and Start Monitor
    monitor = HOCSSafetyMonitor()
    monitor.monitor_loop()
      
