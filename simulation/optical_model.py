import numpy as np
import math

class MZIModel:
    """
    Mathematical model of a Silicon Photonic Mach-Zehnder Interferometer (MZI).
    Used to calculate transmission based on phase shift.
    """
    
    def __init__(self, arm_length_um=200):
        self.L = arm_length_um  # Length of the phase shifter arm
        self.wavelength = 1.55  # Operating wavelength (1550 nm)
        self.neff = 2.45        # Effective refractive index of Silicon waveguide

    def calculate_phase_shift(self, voltage):
        """
        Calculates phase shift (Delta Phi) induced by the CuO heater/memristor.
        Delta_Phi ~ Power ~ Voltage^2 (Thermo-optic effect)
        """
        # Thermo-optic coefficient (approximate for demo)
        dndT = 1.8e-4 
        heating_efficiency = 0.15 # rad/mW
        
        # P = V^2 / R (Assuming Resistance = 500 Ohm)
        power_mw = (voltage ** 2) / 500 * 1000 
        
        delta_phi = power_mw * heating_efficiency
        return delta_phi

    def transmission(self, voltage):
        """
        Transfer function of the MZI: T = cos^2(Delta_Phi / 2)
        """
        phi = self.calculate_phase_shift(voltage)
        
        # MZI Transmission Formula
        T = math.cos(phi / 2) ** 2
        
        return T

if __name__ == "__main__":
    # Test the physics model
    mzi = MZIModel()
    test_voltages = [0, 1, 2, 3.3, 5]
    
    print("Voltage (V) | Phase (rad) | Transmission (%)")
    print("-" * 40)
    for v in test_voltages:
        phi = mzi.calculate_phase_shift(v)
        tr = mzi.transmission(v)
        print(f"{v:9.2f} | {phi:10.3f} | {tr*100:6.2f}%")
      
