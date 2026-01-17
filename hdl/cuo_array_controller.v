/*
 * Module: CUO_ARRAY_CONTROLLER
 * Description: 
 * Finite State Machine (FSM) to control the Copper Oxide (CuO) Crossbar.
 * Handles DAC timing constraints and ADC readout synchronization.
 */

module cuo_array_controller #(
    parameter PRECISION = 12
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [PRECISION-1:0] data_in,
    
    // Hardware Interfaces
    output reg [PRECISION-1:0] dac_out,
    input wire [PRECISION-1:0] adc_in,
    
    // Result Interface
    output reg [31:0] result_out,
    output reg done
);

    // FSM States
    localparam STATE_IDLE    = 3'b000;
    localparam STATE_LOAD    = 3'b001; // Load data to DAC
    localparam STATE_WAIT    = 3'b010; // Wait for Analog Settling
    localparam STATE_READ    = 3'b011; // Read ADC
    localparam STATE_DONE    = 3'b100;

    reg [2:0] current_state, next_state;
    reg [7:0] delay_counter;

    // State Transition Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
            delay_counter <= 0;
        end else begin
            current_state <= next_state;
            
            // Counter logic for analog delay
            if (current_state == STATE_WAIT)
                delay_counter <= delay_counter + 1;
            else
                delay_counter <= 0;
        end
    end

    // Next State Logic
    always @(*) begin
        case (current_state)
            STATE_IDLE: begin
                if (start) next_state = STATE_LOAD;
                else       next_state = STATE_IDLE;
            end
            
            STATE_LOAD: begin
                next_state = STATE_WAIT; // Push data to DAC and wait
            end
            
            STATE_WAIT: begin
                // Wait 20 clock cycles for voltage to stabilize (Memristor Hysteresis)
                if (delay_counter > 20) next_state = STATE_READ;
                else                    next_state = STATE_WAIT;
            end
            
            STATE_READ: begin
                next_state = STATE_DONE; // Latch the ADC value
            end
            
            STATE_DONE: begin
                next_state = STATE_IDLE;
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end

    // Output Logic
    always @(posedge clk) begin
        case (current_state)
            STATE_LOAD: begin
                dac_out <= data_in; // Send digital value to DAC
                done <= 1'b0;
            end
            
            STATE_READ: begin
                // Accumulate result (Simple simulation logic for now)
                result_out <= adc_in; 
            end
            
            STATE_DONE: begin
                done <= 1'b1;
            end
        endcase
    end

endmodule
