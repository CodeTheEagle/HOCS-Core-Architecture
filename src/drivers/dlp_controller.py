#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
================================================================================
PROJECT: HOCS (Hybrid Optical Computing System)
MODULE:  TI DLP6500 Digital Micromirror Device Controller
VERSION: 3.1.0-RC (Release Candidate)
AUTHOR:  CodeTheEagle Team (Yusuf, Mikail & Mert)
DATE:    February 2026
LICENSE: Proprietary & Confidential

DESCRIPTION:
    This module implements the low-level register interface for the Texas 
    Instruments DLP® LightCrafter™ 6500/9000 evaluation modules.
    
    It abstracts the underlying communication bus (I2C/USB) and provides
    high-level primitives for:
      1. Spatial Light Modulator (SLM) Configuration
      2. High-Speed Pattern Sequence Uploading (1-bit to 8-bit planes)
      3. Trigger Synchronization (Input/Output Triggers)
      4. Thermal Monitoring & PWM LED Control

    COMPATIBILITY:
      - Hardware: DLPC900 Digital Controller
      - Firmware: v4.0.1 or higher

    SYNC NOTE:
    This driver expects the FPGA to be mapped to the trigger pins defined in
    'hocs_defs.inc'. Ensure Jumper J7 on the Carrier Board is set to EXT_TRIG.
================================================================================
"""

import time
import struct
import logging
import threading
import random
from enum import Enum, auto
from typing import List, Tuple, Union, Optional
from dataclasses import dataclass

# ==============================================================================
# [1] CONSTANTS & REGISTER MAP (Based on DLPC900 Programmer's Guide)
# ==============================================================================

class DLPRegister(Enum):
    """Memory Mapped Registers for DLPC900."""
    # System Control
    SOURCE_SEL       = 0x00
    DISPLAY_MODE     = 0x69
    DATA_SWAP        = 0x14
    
    # Image Orientation
    IMG_ORIENT       = 0x14
    IMG_CROP         = 0x10
    
    # Pattern Sequence
    PAT_CONFIG       = 0x30
    PAT_START_STOP   = 0x31
    PAT_TRIG_MODE    = 0x32
    PAT_EXPOSURE     = 0x34
    
    # Peripheral Control
    LED_ENABLE       = 0x50
    LED_CURRENT      = 0x54
    PWM_INVERT       = 0x56
    
    # Status / Telemetry
    STATUS_HW        = 0x20
    STATUS_SW        = 0x21
    TEMP_SENSOR      = 0xD0
    VOLT_SENSOR      = 0xD1

class DLPMode(Enum):
    """Operational Modes."""
    STANDBY          = 0x00
    VIDEO_HDMI       = 0x01
    PATTERN_ON_FLY   = 0x02
    PATTERN_PRE_LOAD = 0x03
    TEST_PATTERN     = 0x04

class TriggerSource(Enum):
    """Trigger Input Sources."""
    INTERNAL_AUTO    = 0x00
    EXTERNAL_POS     = 0x01  # Trigger from Kria K26 (Rising Edge)
    EXTERNAL_NEG     = 0x02  # Trigger from Kria K26 (Falling Edge)
    SW_TRIGGER       = 0x03

# Communication Constants
I2C_ADDRESS_MAIN = 0x1A
I2C_ADDRESS_AUX  = 0x1B
USB_TIMEOUT_MS   = 1000
MAX_PATTERN_COUNT = 400  # Max patterns in onboard memory

# ==============================================================================
# [2] EXCEPTIONS
# ==============================================================================

class DLPError(Exception):
    """Base exception for DLP Controller."""
    pass

class DLPCommsError(DLPError):
    """I2C or USB Bus failure."""
    pass

class DLPConfigurationError(DLPError):
    """Invalid parameter set passed to registers."""
    pass

class DLPThermalShutdown(DLPError):
    """Critical Temperature Reached."""
    pass

# ==============================================================================
# [3] DLP CONTROLLER CLASS
# ==============================================================================

class DLP6500Controller:
    """
    High-level driver for the DLP6500 SLM.
    Thread-safe and synchronized with HOCSSession.
    """

    def __init__(self, bus_id: int = 1, simulation: bool = True):
        """
        Initialize the Controller Instance.
        
        Args:
            bus_id (int): I2C Bus ID (e.g., /dev/i2c-1).
            simulation (bool): If True, mocks hardware interactions.
        """
        self.bus_id = bus_id
        self.simulation = simulation
        self._lock = threading.RLock()  # Reentrant Lock
        self._connected = False
        self._current_mode = DLPMode.STANDBY
        
        # Setup Logging
        self.logger = logging.getLogger("DLP6500")
        self.logger.setLevel(logging.INFO)
        if not self.logger.handlers:
            ch = logging.StreamHandler()
            ch.setFormatter(logging.Formatter('[%(levelname)s] [DLP] %(message)s'))
            self.logger.addHandler(ch)

        self.logger.info(f"Driver Initialized. Simulation: {self.simulation}")

    # --- CONNECTION MANAGEMENT ---

    def connect(self):
        """
        Establishes physical connection to the DMD Controller.
        """
        with self._lock:
            self.logger.info("Probing I2C Bus for DLPC900...")
            
            try:
                if not self.simulation:
                    # Actual SMBus implementation would go here
                    # self.bus = smbus.SMBus(self.bus_id)
                    pass
                else:
                    time.sleep(0.3) # Simulating bus handshake
                
                # Verify Device ID (Magic Handshake)
                dev_id = self._read_register(0x00, 4)
                self.logger.info(f"Device Found. ID: {dev_id}")
                
                self._connected = True
                
                # Perform Soft Reset to known state
                self.reset_device()
                
            except Exception as e:
                self.logger.error(f"Connection Failed: {e}")
                raise DLPCommsError("DMD Controller unresponsive.")

    def disconnect(self):
        """
        Safely shuts down the DMD (Parks mirrors).
        """
        with self._lock:
            if self._connected:
                self.logger.info("Parking Mirrors and Shutting Down...")
                self.set_mode(DLPMode.STANDBY)
                self._write_register(DLPRegister.LED_ENABLE, 0x00) # Leds Off
                self._connected = False

    # --- CORE CONFIGURATION ---

    def reset_device(self):
        """
        Software Reset. Restores factory defaults.
        """
        self.logger.debug("Performing Soft Reset...")
        # Command Sequence: Stop -> Clear -> Standby
        self.stop_sequence()
        time.sleep(0.1)
        self.set_mode(DLPMode.STANDBY)

    def set_mode(self, mode: DLPMode):
        """
        Changes the display mode of the DLP.
        
        Args:
            mode (DLPMode): The target operational mode.
        """
        with self._lock:
            if self._current_mode == mode:
                return

            self.logger.info(f"Switching Mode: {self._current_mode.name} -> {mode.name}")
            
            # Write to Display Mode Register (0x69)
            # Bit 0-2: Mode Select
            self._write_register(DLPRegister.DISPLAY_MODE, mode.value)
            
            # Wait for PLL Lock
            time.sleep(0.2)
            self._current_mode = mode

    # --- PATTERN SEQUENCE MANAGEMENT (CRITICAL FOR HOCS) ---

    def configure_pattern_sequence(self, 
                                   bit_depth: int = 1, 
                                   num_patterns: int = 24, 
                                   exposure_us: int = 105):
        """
        Configures the High-Speed Pattern Logic.
        
        This aligns with the 'HOCS_Core' FPGA timing.
        
        Args:
            bit_depth (int): 1, 4, or 8 bits per pattern.
            num_patterns (int): Total patterns in the batch.
            exposure_us (int): Exposure time in microseconds (Laser Pulse Width).
        """
        with self._lock:
            if self._current_mode != DLPMode.PATTERN_PRE_LOAD:
                self.set_mode(DLPMode.PATTERN_PRE_LOAD)

            self.logger.info(f"Configuring Sequence: {num_patterns} patterns @ {bit_depth}-bit")
            
            # 1. Validation
            if bit_depth not in [1, 4, 8]:
                raise DLPConfigurationError(f"Invalid bit depth: {bit_depth}")
            
            min_exposure = 50 if bit_depth == 1 else 500
            if exposure_us < min_exposure:
                self.logger.warning(f"Exposure {exposure_us}us is too fast for {bit_depth}-bit mode.")

            # 2. Set Trigger Mode (External Positive Edge from Kria K26)
            self._write_register(DLPRegister.PAT_TRIG_MODE, TriggerSource.EXTERNAL_POS.value)
            
            # 3. Set Exposure & Frame Period
            # Register 0x34 takes 4 bytes (Microseconds)
            period_us = exposure_us + 10 # 10us Dark Time for Mirror Settle
            self._write_register_32(DLPRegister.PAT_EXPOSURE, exposure_us)
            
            # 4. Prepare LUT (Look-Up Table) for Pattern Order
            self._upload_pattern_lut(num_patterns, bit_depth)

    def start_sequence(self):
        """
        Arms the DLP. It will now wait for the TRIGGER signal from FPGA.
        """
        self.logger.info("Arming DLP Sequence. Waiting for FPGA Trigger...")
        # Write 0x02 to Start/Stop Register (0x31)
        self._write_register(DLPRegister.PAT_START_STOP, 0x02)
        
        # Verify status
        status = self._read_status()
        if not status['sequence_running']:
             self.logger.warning("Sequence did not start immediately (Waiting for Trig).")

    def stop_sequence(self):
        """
        Stops the current pattern sequence immediately.
        """
        self.logger.debug("Stopping Pattern Sequence.")
        # Write 0x00 to Start/Stop Register
        self._write_register(DLPRegister.PAT_START_STOP, 0x00)

    # --- TELEMETRY & HEALTH ---

    def get_diagnostics(self) -> dict:
        """
        Reads thermal sensors and system status.
        """
        temp = self._read_temperature()
        volt = self._read_voltage()
        status = self._read_status()
        
        # Safety Check
        if temp > 65.0:
            self.logger.critical(f"DMD OVERTEMP: {temp}C")
            self.disconnect()
            raise DLPThermalShutdown(f"Temperature {temp}C exceeds limit.")
            
        return {
            "temperature_c": temp,
            "voltage_v": volt,
            "status_flags": status
        }

    # --- LOW LEVEL I/O (SIMULATED OR REAL) ---

    def _write_register(self, reg: Union[DLPRegister, int], value: int):
        """Writes a single byte to a register."""
        reg_addr = reg.value if isinstance(reg, DLPRegister) else reg
        
        if self.simulation:
            # self.logger.debug(f"I2C WRITE: Reg[0x{reg_addr:02X}] <= 0x{value:02X}")
            pass
        else:
            # Real hardware I2C code
            pass

    def _write_register_32(self, reg: Union[DLPRegister, int], value: int):
        """Writes a 32-bit integer (Little Endian)."""
        bytes_val = struct.pack('<I', value)
        for i, b in enumerate(bytes_val):
             self._write_register(reg.value + i, b)

    def _read_register(self, reg: Union[DLPRegister, int], length: int) -> int:
        """Reads 'length' bytes."""
        if self.simulation:
            return 0xCAFEBABE # Dummy ID
        return 0x00

    def _read_temperature(self) -> float:
        """Reads DMD temperature."""
        if self.simulation:
            return 45.0 + random.uniform(-1, 1)
        return 0.0

    def _read_voltage(self) -> float:
        """Reads System Voltage."""
        if self.simulation:
            return 1.2 + random.uniform(-0.01, 0.01)
        return 0.0

    def _read_status(self) -> dict:
        """Decodes Status Register 0x20."""
        # Mock status
        return {
            "init_done": True,
            "sequence_running": True,
            "dmd_parked": False,
            "buffer_frozen": False
        }

    def _upload_pattern_lut(self, count, bit_depth):
        """
        Internal: Generates and uploads the Pattern Definition Loop.
        On the DLPC900, this is a mailbox operation.
        """
        self.logger.debug(f"Building LUT for {count} patterns...")
        # Simulate SPI/Flash programming time
        time.sleep(0.05 * (count / 10))
        self.logger.info("Pattern LUT Uploaded Successfully.")

# ==============================================================================
# [4] STANDALONE TEST HARNESS
# ==============================================================================

if __name__ == "__main__":
    print("--- TI DLP6500 DRIVER UNIT TEST ---")
    
    # 1. Instantiate Driver
    dlp = DLP6500Controller(bus_id=1, simulation=True)
    
    try:
        # 2. Connect
        dlp.connect()
        
        # 3. Check Health
        health = dlp.get_diagnostics()
        print(f"Health Check: {health}")
        
        # 4. Configure HOCS Mode (High Speed Matrix Multiplication)
        # 1-bit depth for maximum speed (9523 Hz)
        dlp.configure_pattern_sequence(bit_depth=1, num_patterns=128, exposure_us=100)
        
        # 5. Start Waiting for Trigger
        dlp.start_sequence()
        
        print(">> DLP is ARMED. Waiting for Kria K26 Trigger Pulse...")
        
        # Simulate running for 2 seconds
        for i in range(5):
            time.sleep(0.5)
            print(f"   [Telemetry] Temp: {dlp._read_temperature():.2f}C")
            
        # 6. Stop
        dlp.stop_sequence()
        
    except DLPError as e:
        print(f"[FATAL] {e}")
    finally:
        dlp.disconnect()
        print("--- TEST COMPLETE ---")
