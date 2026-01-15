from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List
import numpy as np

# Import our Mock HAL
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from drivers.mock_hal import HOCSDriver

app = FastAPI(
    title="HOCS Neural Interface API",
    description="REST API for communicating with the Photonic Processor Unit",
    version="1.0.0"
)

# Initialize Hardware Driver in Simulation Mode
chip = HOCSDriver(mode='SIMULATION')
chip.connect()

class MatrixInput(BaseModel):
    vector: List[float]
    weights: List[List[float]] = None

@app.get("/")
def read_root():
    return {"system_status": "ONLINE", "hardware": "HOCS-128c-Prototype", "laser": "STANDBY"}

@app.post("/compute")
def compute_inference(data: MatrixInput):
    """
    Sends a vector to the optical core for matrix multiplication.
    """
    if len(data.vector) != 128:
        raise HTTPException(status_code=400, detail="Input vector must be 128 channels wide.")
    
    # 1. Write weights if provided (Memristive Programming)
    if data.weights:
        chip.write_weights(data.weights)
    
    # 2. Perform Inference (Optical Speed)
    result = chip.perform_inference(data.vector)
    
    return {
        "status": "success",
        "output_vector": result.tolist(),
        "latency": "0.4 ns"  # Theoretical optical latency
    }
  
