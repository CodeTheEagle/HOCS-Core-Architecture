#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
================================================================================
PROJECT: HOCS (Hybrid Optical Computing System)
MODULE:  HOCS Session Manager (SDK Core)
VERSION: 2.4.1-Enterprise
AUTHOR:  CodeTheEagle Team (Yusuf & Mikail)
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
    simulation_mode: bool = True  # Set to False on
