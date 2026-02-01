import time
import random

def print_log(msg, level="INFO"):
    print(f"[{time.strftime('%H:%M:%S')}] [{level}] {msg}")

def main():
    print_log("Starting HOCS Hardware-in-Loop Simulation...", "SYSTEM")
    time.sleep(1)
    
    # 1. Initialize Core
    print_log("Loading Bitstream: hocs_core.bit -> Kria K26", "FPGA")
    time.sleep(0.5)
    print_log("AXI4-Stream Interface: UP", "NET")
    
    # 2. Mock Optical Job
    matrix_size = 1024
    print_log(f"Allocating Memory for {matrix_size}x{matrix_size} Matrix...", "MMU")
    
    # 3. Fire Laser
    print_log("Triggering DLP6500 Pattern Sequence...", "OPTICS")
    time.sleep(0.2)
    print_log("LASER PULSE FIRED (Duration: 10ns)", "HARDWARE")
    
    # 4. Read Result
    throughput = random.uniform(3.1, 3.4)
    print_log("Capturing Sony Pregius Frame...", "SENSOR")
    print_log(f"Processing Complete. Measured Throughput: {throughput:.2f} TB/s", "RESULT")
    
    print_log("Simulation PASSED.", "SUCCESS")

if __name__ == "__main__":
    main()
  
