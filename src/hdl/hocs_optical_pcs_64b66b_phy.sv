`timescale 1ps / 1fs

module hocs_optical_pcs_64b66b_phy #(
    parameter int NUM_LANES         = 144,
    parameter int RAW_DATA_WIDTH    = 66,
    parameter int ALIGNED_WIDTH     = 64,
    parameter int DESKEW_FIFO_DEPTH = 256,
    parameter int SYNC_TOLERANCE    = 64
)(
    input  logic                                     sys_clk,
    input  logic                                     opt_rx_clk,
    input  logic                                     opt_tx_clk,
    input  logic                                     sys_aresetn,
    
    input  logic                                     prbs31_en,
    input  logic                                     force_retrain,

    input  logic [NUM_LANES-1:0][RAW_DATA_WIDTH-1:0] rx_raw_data,
    output logic [NUM_LANES-1:0][ALIGNED_WIDTH-1:0]  rx_descrambled_data,
    output logic [NUM_LANES-1:0]                     rx_data_valid,

    input  logic [NUM_LANES-1:0][ALIGNED_WIDTH-1:0]  tx_raw_data,
    output logic [NUM_LANES-1:0][RAW_DATA_WIDTH-1:0] tx_scrambled_data,

    output logic [NUM_LANES-1:0]                     lane_lock_status,
    output logic [NUM_LANES-1:0]                     lane_prbs_err_flag,
    output logic                                     global_deskew_done
);

    typedef enum logic [2:0] {
        ST_LOSS  = 3'b000,
        ST_HUNT  = 3'b001,
        ST_LOCK  = 3'b010,
        ST_ALIGN = 3'b011,
        ST_PRBS  = 3'b100,
        ST_RUN   = 3'b101,
        ST_FAIL  = 3'b111
    } pcs_lane_state_t;

    pcs_lane_state_t [NUM_LANES-1:0] current_state, next_state;

    logic [NUM_LANES-1:0][5:0]  good_sh_cnt;
    logic [NUM_LANES-1:0][5:0]  bad_sh_cnt;
    logic [NUM_LANES-1:0]       sh_valid;
    logic [NUM_LANES-1:0][1:0]  sync_header_reg;

    logic [NUM_LANES-1:0][DESKEW_FIFO_DEPTH-1:0][ALIGNED_WIDTH-1:0] deskew_mem;
    logic [NUM_LANES-1:0][7:0]  wr_ptr;
    logic [NUM_LANES-1:0][7:0]  rd_ptr;
    logic [NUM_LANES-1:0]       marker_detected;

    logic [57:0] scrambler_poly [NUM_LANES-1:0];

    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i++) begin : PCS_LANE_LOGIC

            always_ff @(posedge opt_rx_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    sync_header_reg[i] <= 2'b00;
                    sh_valid[i]        <= 1'b0;
                end else begin
                    sync_header_reg[i] <= rx_raw_data[i][1:0];
                    if (rx_raw_data[i][1:0] == 2'b01 || rx_raw_data[i][1:0] == 2'b10) begin
                        sh_valid[i] <= 1'b1;
                    end else begin
                        sh_valid[i] <= 1'b0;
                    end
                end
            end

            always_ff @(posedge opt_rx_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    current_state[i] <= ST_LOSS;
                    good_sh_cnt[i]   <= '0;
                    bad_sh_cnt[i]    <= '0;
                end else begin
                    if (force_retrain) begin
                        current_state[i] <= ST_LOSS;
                    end else begin
                        current_state[i] <= next_state[i];
                    end

                    case (current_state[i])
                        ST_HUNT: begin
                            if (sh_valid[i]) begin
                                good_sh_cnt[i] <= good_sh_cnt[i] + 1;
                                bad_sh_cnt[i]  <= '0;
                            end else begin
                                good_sh_cnt[i] <= '0;
                                bad_sh_cnt[i]  <= bad_sh_cnt[i] + 1;
                            end
                        end
                        ST_LOCK: begin
                            if (!sh_valid[i]) bad_sh_cnt[i] <= bad_sh_cnt[i] + 1;
                            else bad_sh_cnt[i] <= '0;
                        end
                        default: begin
                            good_sh_cnt[i] <= '0;
                            bad_sh_cnt[i]  <= '0;
                        end
                    endcase
                end
            end

            always_comb begin
                next_state[i] = current_state[i];
                case (current_state[i])
                    ST_LOSS: begin
                        next_state[i] = ST_HUNT;
                    end
                    ST_HUNT: begin
                        if (good_sh_cnt[i] >= SYNC_TOLERANCE)
                            next_state[i] = ST_LOCK;
                        else if (bad_sh_cnt[i] >= 16)
                            next_state[i] = ST_LOSS;
                    end
                    ST_LOCK: begin
                        if (bad_sh_cnt[i] >= 4)
                            next_state[i] = ST_LOSS;
                        else if (marker_detected[i])
                            next_state[i] = ST_ALIGN;
                    end
                    ST_ALIGN: begin
                        if (prbs31_en)
                            next_state[i] = ST_PRBS;
                        else if (global_deskew_done)
                            next_state[i] = ST_RUN;
                    end
                    ST_PRBS: begin
                        if (!prbs31_en) next_state[i] = ST_RUN;
                    end
                    ST_RUN: begin
                        if (bad_sh_cnt[i] >= 4) next_state[i] = ST_FAIL;
                    end
                    ST_FAIL: begin
                        // Wait for system reset or graceful degradation trigger
                    end
                endcase
            end

            assign lane_lock_status[i] = (current_state[i] == ST_LOCK || current_state[i] == ST_RUN);

            always_ff @(posedge opt_rx_clk) begin
                if (current_state[i] == ST_RUN && sh_valid[i]) begin
                    scrambler_poly[i] <= {scrambler_poly[i][56:0], scrambler_poly[i][57] ^ scrambler_poly[i][38]};
                    rx_descrambled_data[i] <= rx_raw_data[i][65:2] ^ {64{scrambler_poly[i][57]}};
                    rx_data_valid[i] <= 1'b1;
                end else begin
                    rx_data_valid[i] <= 1'b0;
                end
            end

        end
    endgenerate

    logic [NUM_LANES-1:0] deskew_rdy;
    always_ff @(posedge sys_clk or negedge sys_aresetn) begin
        if (!sys_aresetn) begin
            global_deskew_done <= 1'b0;
        end else begin
            if (&deskew_rdy) begin
                global_deskew_done <= 1'b1;
            end else begin
                global_deskew_done <= 1'b0;
            end
        end
    end

endmodule
logic [NUM_LANES-1:0][30:0] prbs_lfsr;
    logic [NUM_LANES-1:0][30:0] prbs_expected;
    logic [NUM_LANES-1:0]       prbs_lock;

    generate
        for (i = 0; i < NUM_LANES; i++) begin : PRBS31_CORE
            always_ff @(posedge opt_rx_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    prbs_lfsr[i] <= 31'h7FFFFFFF;
                    lane_prbs_err_flag[i] <= 1'b0;
                    prbs_lock[i] <= 1'b0;
                end else if (current_state[i] == ST_PRBS) begin
                    if (!prbs_lock[i]) begin
                        prbs_lfsr[i] <= rx_descrambled_data[i][30:0];
                        prbs_lock[i] <= 1'b1;
                    end else begin
                        for (int j = 0; j < ALIGNED_WIDTH; j++) begin
                            prbs_expected[i][0] = prbs_lfsr[i][30] ^ prbs_lfsr[i][27];
                            prbs_expected[i][30:1] = prbs_lfsr[i][29:0];
                        end
                        if (rx_descrambled_data[i] != prbs_expected[i]) begin
                            lane_prbs_err_flag[i] <= 1'b1;
                        end else begin
                            lane_prbs_err_flag[i] <= 1'b0;
                        end
                        prbs_lfsr[i] <= prbs_expected[i];
                    end
                end else begin
                    prbs_lock[i] <= 1'b0;
                    lane_prbs_err_flag[i] <= 1'b0;
                end
            end
        end
    endgenerate

    logic [NUM_LANES-1:0][7:0] wr_ptr_gray;
    logic [NUM_LANES-1:0][7:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    logic [NUM_LANES-1:0][7:0] rd_ptr_gray;
    logic [NUM_LANES-1:0][7:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    generate
        for (i = 0; i < NUM_LANES; i++) begin : DESKEW_FIFO_CDC
            always_ff @(posedge opt_rx_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    wr_ptr[i] <= '0;
                    wr_ptr_gray[i] <= '0;
                end else if (rx_data_valid[i] && current_state[i] == ST_RUN) begin
                    deskew_mem[i][wr_ptr[i]] <= rx_descrambled_data[i];
                    wr_ptr[i] <= wr_ptr[i] + 1;
                    wr_ptr_gray[i] <= (wr_ptr[i] + 1) ^ ((wr_ptr[i] + 1) >> 1);
                end
            end

            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    wr_ptr_gray_sync1[i] <= '0;
                    wr_ptr_gray_sync2[i] <= '0;
                end else begin
                    wr_ptr_gray_sync1[i] <= wr_ptr_gray[i];
                    wr_ptr_gray_sync2[i] <= wr_ptr_gray_sync1[i];
                end
            end

            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    rd_ptr[i] <= '0;
                    rd_ptr_gray[i] <= '0;
                    marker_detected[i] <= 1'b0;
                end else begin
                    if (deskew_mem[i][rd_ptr[i]][ALIGNED_WIDTH-1:ALIGNED_WIDTH-8] == 8'hC1) begin
                        marker_detected[i] <= 1'b1;
                    end

                    if (global_deskew_done) begin
                        rd_ptr[i] <= rd_ptr[i] + 1;
                        rd_ptr_gray[i] <= (rd_ptr[i] + 1) ^ ((rd_ptr[i] + 1) >> 1);
                    end
                end
            end

            always_ff @(posedge opt_rx_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    rd_ptr_gray_sync1[i] <= '0;
                    rd_ptr_gray_sync2[i] <= '0;
                end else begin
                    rd_ptr_gray_sync1[i] <= rd_ptr_gray[i];
                    rd_ptr_gray_sync2[i] <= rd_ptr_gray_sync1[i];
                end
            end
        end
    endgenerate

    logic [7:0] master_rd_ptr;
    logic deskew_eval_trigger;

    always_ff @(posedge sys_clk or negedge sys_aresetn) begin
        if (!sys_aresetn) begin
            deskew_eval_trigger <= 1'b0;
            master_rd_ptr <= '0;
            deskew_rdy <= '0;
        end else begin
            if (&marker_detected) begin
                deskew_eval_trigger <= 1'b1;
            end
            
            if (deskew_eval_trigger && !global_deskew_done) begin
                for (int j = 0; j < NUM_LANES; j++) begin
                    if (rd_ptr[j] != master_rd_ptr) begin
                        deskew_rdy[j] <= 1'b0;
                        if ((wr_ptr_gray_sync2[j] ^ (wr_ptr_gray_sync2[j] >> 1)) - rd_ptr[j] > 4) begin
                            rd_ptr[j] <= rd_ptr[j] + 1;
                        end
                    end else begin
                        deskew_rdy[j] <= 1'b1;
                    end
                end
            end
        end
    end
