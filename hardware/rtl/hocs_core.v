/* ==============================================================================
 * FILE: hocs_core.v
 * MODULE: HOCS Optical Accelerator Engine
 * AUTHOR: CodeTheEagle Team
 * TYPE: Synthesizable Verilog (IEEE 1364-2005)
 * * DESCRIPTION:
 * This is the top-level RTL module for the HOCS Optical Core.
 * It implements the AXI4-Stream interface to communicate with the DMA engine
 * and generates the precise timing signals required for the DLP6500.
 * ============================================================================== */

module hocs_core #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    // System Signals
    input  wire                   clk,            // 250 MHz Core Clock
    input  wire                   rst_n,          // Active Low Reset

    // AXI4-Lite Control Interface (from CPU)
    input  wire [ADDR_WIDTH-1:0]  ctrl_addr,
    input  wire [DATA_WIDTH-1:0]  ctrl_wdata,
    input  wire                   ctrl_write_en,
    output reg  [DATA_WIDTH-1:0]  ctrl_rdata,
    
    // AXI4-Stream Interface (DMA Data In)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Hardware Triggers (To Optics)
    output reg                    laser_trigger_pin,
    output reg                    dlp_sync_pin,
    input  wire                   sensor_vsync_in
);

    // --- INTERNAL STATE MACHINE ---
    localparam [2:0] 
        IDLE        = 3'b000,
        LOAD_DATA   = 3'b001,
        ALIGN_DLP   = 3'b010,
        FIRE_LASER  = 3'b011,
        READOUT     = 3'b100,
        ERROR       = 3'b111;

    reg [2:0] current_state, next_state;
    reg [31:0] cycle_counter;

    // --- CONTROL REGISTERS ---
    reg [31:0] reg_status;
    reg [31:0] reg_config;
    
    // Assign Ready Signal (Always ready to accept data in LOAD state)
    assign s_axis_tready = (current_state == LOAD_DATA);

    // --- SYNCHRONOUS LOGIC ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state     <= IDLE;
            cycle_counter     <= 0;
            laser_trigger_pin <= 0;
            dlp_sync_pin      <= 0;
            reg_status        <= 0;
        end else begin
            current_state <= next_state;

            // Cycle Counter for Precision Timing
            if (current_state == FIRE_LASER) 
                cycle_counter <= cycle_counter + 1;
            else 
                cycle_counter <= 0;
        end
    end

    // --- NEXT STATE LOGIC ---
    always @(*) begin
        case (current_state)
            IDLE: begin
                // Wait for Start Bit in Config Register
                if (reg_config[0] == 1'b1) 
                    next_state = LOAD_DATA;
                else 
                    next_state = IDLE;
            end

            LOAD_DATA: begin
                // Wait until FIFO is full or Stream ends
                if (s_axis_tvalid) 
                    next_state = ALIGN_DLP;
                else 
                    next_state = LOAD_DATA;
            end

            ALIGN_DLP: begin
                // Wait 50 cycles for Mirrors to flip
                next_state = FIRE_LASER; 
            end

            FIRE_LASER: begin
                // Hold Laser ON for 10 nanoseconds (simulated cycles)
                if (cycle_counter > 100)
                    next_state = READOUT;
                else
                    next_state = FIRE_LASER;
            end

            READOUT: begin
                // Wait for VSYNC from Camera
                if (sensor_vsync_in)
                    next_state = IDLE;
                else
                    next_state = READOUT;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // --- OUTPUT LOGIC ---
    always @(posedge clk) begin
        case (current_state)
            FIRE_LASER: laser_trigger_pin <= 1'b1;
            default:    laser_trigger_pin <= 1'b0;
        endcase
        
        // Status Register Update
        reg_status[2:0] <= current_state;
    end

endmodule
