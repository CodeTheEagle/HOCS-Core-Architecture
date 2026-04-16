/*
 * Module: HOCS_SCRAM_CONTROLLER
 * Author: Muhammed Yusuf Cobanoglu
 * Description:
 * Hardware-level emergency shutdown logic.
 * Independent of the Operating System. Watchdog Timer (WDT) driven.
 *
 * "SCRAM" = Safety Control Rod Axe Man (Nuclear Terminology for Emergency Kill)
 */

`timescale 1ns / 1ps

module hocs_scram_controller (
    input wire clk,                  // System Clock (300 MHz)
    input wire rst_n,                // Active Low Reset
    input wire heartbeat_signal,     // Signal from Python Driver
    input wire [7:0] temp_sensor_raw,// Raw temperature data
    
    output reg power_cut_trigger,    // Controls physical relay
    output reg [3:0] status_leds,    // Debug LEDs
    output reg system_locked         // Logic Lockout Flag
);

    // Thresholds
    parameter TEMP_CRITICAL_LIMIT = 8'd200; // ~85 Degrees Celsius
    parameter WATCHDOG_LIMIT      = 32'd300_000_000; // 1 Second at 300MHz

    // Registers
    reg [31:0] watchdog_counter;
    reg heartbeat_prev;

    // States
    localparam STATE_OK       = 2'b00;
    localparam STATE_WARNING  = 2'b01;
    localparam STATE_SCRAM    = 2'b10;
    localparam STATE_DEAD     = 2'b11;

    reg [1:0] current_state;

    // -------------------------------------------------------------------------
    // WATCHDOG LOGIC
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_counter <= 0;
            heartbeat_prev <= 0;
        end else begin
            // Edge detection for heartbeat
            if (heartbeat_signal != heartbeat_prev) begin
                watchdog_counter <= 0; // Reset timer if software is alive
                heartbeat_prev <= heartbeat_signal;
            end else begin
                // Increment timer if no signal
                if (watchdog_counter < WATCHDOG_LIMIT)
                    watchdog_counter <= watchdog_counter + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // SCRAM FSM (Finite State Machine)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_OK;
            power_cut_trigger <= 0;
            system_locked <= 0;
            status_leds <= 4'b0001; // Green
        end else begin
            case (current_state)
                
                STATE_OK: begin
                    // Check Conditions
                    if (temp_sensor_raw > TEMP_CRITICAL_LIMIT) begin
                        current_state <= STATE_SCRAM;
                    end else if (watchdog_counter >= WATCHDOG_LIMIT) begin
                        current_state <= STATE_SCRAM; // Software Dead? Kill Hardware.
                    end
                    status_leds <= 4'b0001; // Green
                end

                STATE_SCRAM: begin
                    // !!! EMERGENCY ACTION !!!
                    power_cut_trigger <= 1;   // Cut power relay
                    system_locked <= 1;       // Freeze Logic
                    status_leds <= 4'b1111;   // All ON (Panic)
                    current_state <= STATE_DEAD;
                end

                STATE_DEAD: begin
                    // Stay here until Hard Reset
                    power_cut_trigger <= 1;
                    status_leds <= ~status_leds; // Blink rapidly
                end

            endcase
        end
    end

endmodule
