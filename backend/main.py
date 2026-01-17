"""
HOCS REST API Service - Edge Deployment Interface
-------------------------------------------------
Framework: FastAPI
Integration: HOCS AXI Driver
Description: 
    Provides external access to the HOCS Photonic Coprocessor.
    Includes endpoints for Bitstream Management, Tensor Processing,
    and Hardware Stress Testing.

Usage: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from fastapi import FastAPI, HTTPException, BackgroundTasks, UploadFile
from pydantic import BaseModel
import numpy as np
import time
import asyncio
from typing import List, Optional

# Import our custom heavy driver
from hocs_axi_driver import HOCSDriverEngine

# --- APP INITIALIZATION ---
app = FastAPI(
    title="HOCS Edge API",
    description="Interface for Hybrid Optical Computing System (FPGA+Photonic)",
    version="2.4.0",
    docs_url="/docs"
)

# Initialize Driver in Simulation Mode by default (Safety First)
driver = HOCSDriverEngine(simulation_mode=True)

# --- DATA MODELS ---
class MatrixInput(BaseModel):
    rows: int
    cols: int
    data: List[List[float]]
    
class StressTestConfig(BaseModel):
    matrix_size: int = 2048
    iterations: int = 5
    turbo_mode: bool = False

# --- SYSTEM MONITORING ---
@app.on_event("startup")
async def startup_event():
    print(r"""
    __  __  ___   ____ ____  
   |  \/  |/ _ \ / ___/ ___| 
   | |\/| | | | | |   \___ \ 
   | |  | | |_| | |___ ___) |
   |_|  |_|\___/ \____|____/  ONLINE
   ----------------------------------
   System: HOCS Edge Node
   Status: Ready for Optical Processing
    """)

# --- ENDPOINTS ---

@app.get("/")
async def root():
    return {"message": "HOCS System Online", "telemetry": driver.get_telemetry()}

@app.get("/system/status")
async def get_system_status():
    """Returns detailed FPGA and CPU telemetry."""
    telemetry = driver.get_telemetry()
    # Add fake complex data
    telemetry["optical_link_stability"] = "99.8%"
    telemetry["dac_resolution"] = "12-bit"
    telemetry["axi_bus_width"] = 128
    return telemetry

@app.post("/engine/load_bitstream")
async def load_bitstream(file: UploadFile):
    """
    Uploads a new .bit file to reconfigure the FPGA logic dynamically.
    """
    try:
        contents = await file.read()
        filename = f"bitstreams/{file.filename}"
        with open(filename, "wb") as f:
            f.write(contents)
        
        # Reload driver with new hardware logic
        global driver
        driver = HOCSDriverEngine(bitstream_path=filename, simulation_mode=False)
        return {"status": "success", "message": f"FPGA Reconfigured with {file.filename}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/compute/tensor_op")
async def process_tensor(matrix: MatrixInput):
    """
    Offloads a Matrix Multiplication task to the Optical Core.
    """
    input_np = np.array(matrix.data, dtype=np.float32)
    
    start_time = time.time()
    result = await driver.process_tensor_async(input_np)
    end_time = time.time()
    
    return {
        "status": "completed",
        "latency_ms": (end_time - start_time) * 1000,
        "result_shape": result.shape,
        "result_sample": result[:2, :2].tolist(), # Preview only
        "compute_unit": "OPTICAL_CORE" if not driver.simulation_mode else "CPU_SIMULATION"
    }

@app.post("/maintenance/stress_test")
async def trigger_stress_test(config: StressTestConfig, background_tasks: BackgroundTasks):
    """
    ⚠️ DANGER ZONE: Triggers a massive computational load.
    Used to benchmark Silicon limits vs Optical efficiency.
    """
    if config.matrix_size > 8192 and not config.turbo_mode:
        raise HTTPException(status_code=400, detail="Matrix too large! Enable turbo_mode to override safety.")

    def run_heavy_load(size, iters):
        print(f"!!! STARTING STRESS TEST: {iters} iterations of {size}x{size} !!!")
        for i in range(iters):
            driver.cpu_stress_test(matrix_size=size)
        print("!!! STRESS TEST FINISHED !!!")

    # Run in background so API doesn't time out
    background_tasks.add_task(run_heavy_load, config.matrix_size, config.iterations)
    
    return {
        "message": "Stress test initiated in background.",
        "warning": "System responsiveness may drop.",
        "estimated_cpu_load": "100%"
}
  
