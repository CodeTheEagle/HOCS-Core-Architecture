/*
 * Module: HOCS_TOP_WRAPPER
 * Project: Hybrid Optical Computing System (HOCS)
 * Author: Muhammed Yusuf Cobanoglu
 * Description: 
 * Top-level logic wrapper for the Kria KV260 FPGA.
 * Integrates AXI Stream interfaces with the custom CuO Memristor Controller.
 * Manages data flow between DMA and Optical DACs.
 */

`timescale 1ns / 1ps

module hocs_top #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12
)(
    // System Clock & Reset
    input wire clk,
    input wire rst_n,

    // AXI Stream Slave (Data Input from DMA)
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,

    // AXI Stream Master (Result Output to DMA)
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,

    // External Physical Interface (PMOD / Optical Core)
    output wire [11:0] dac_out_parallel, // To DAC
    output wire dac_valid,
    input wire [11:0] adc_in_parallel,   // From ADC
    output wire adc_clk_trigger
);

    // Internal Signals
    wire [DATA_WIDTH-1:0] core_data_in;
    wire [DATA_WIDTH-1:0] core_data_out;
    wire compute_enable;
    wire compute_done;

    // -------------------------------------------------------------------------
    // AXI Stream Handshake Logic
    // -------------------------------------------------------------------------
    // Simple pass-through logic for demonstration
    assign s_axis_tready = (compute_enable) ? 1'b0 : 1'b1; // Stop upstream if busy
    
    // -------------------------------------------------------------------------
    // Instantiation: Custom Optical Core Controller
    // -------------------------------------------------------------------------
    cuo_array_controller #(
        .PRECISION(12)
    ) u_optical_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(s_axis_tvalid),
        .data_in(s_axis_tdata[11:0]),
        .dac_out(dac_out_parallel),
        .adc_in(adc_in_parallel),
        .result_out(core_data_out),
        .done(m_axis_tvalid) // Signal valid when computation is done
    );

    // Route result back to DMA
    assign m_axis_tdata = {20'b0, core_data_out[11:0]}; // Zero padding
    assign m_axis_tlast = s_axis_tlast; // Propagate last signal

endmodule
