`timescale 1ps / 1fs

module hocs_optical_islip_crossbar_144x144 #(
    parameter int NUM_PORTS    = 144,
    parameter int DATA_WIDTH   = 64,
    parameter int VOQ_DEPTH    = 512,
    parameter int MAX_ITER     = 4
)(
    input  logic                                         sys_clk,
    input  logic                                         sys_aresetn,
    
    input  logic [NUM_PORTS-1:0][DATA_WIDTH-1:0]         ingress_tdata,
    input  logic [NUM_PORTS-1:0]                         ingress_tvalid,
    input  logic [NUM_PORTS-1:0][$clog2(NUM_PORTS)-1:0]  ingress_tdest,
    output logic [NUM_PORTS-1:0]                         ingress_tready,
    
    output logic [NUM_PORTS-1:0][DATA_WIDTH-1:0]         egress_tdata,
    output logic [NUM_PORTS-1:0]                         egress_tvalid,
    input  logic [NUM_PORTS-1:0]                         egress_tready
);

    localparam int PTR_WIDTH = $clog2(VOQ_DEPTH);
    localparam int PORT_BITS = $clog2(NUM_PORTS);

    logic [NUM_PORTS-1:0][NUM_PORTS-1:0][DATA_WIDTH-1:0] voq_ram [0:VOQ_DEPTH-1];
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0][PTR_WIDTH-1:0]  voq_wr_ptr;
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0][PTR_WIDTH-1:0]  voq_rd_ptr;
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0][PTR_WIDTH:0]    voq_count;
    
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0]                 voq_empty;
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0]                 voq_full;
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0]                 req_matrix;
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0]                 grant_matrix;
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0]                 accept_matrix;

    logic [NUM_PORTS-1:0][PORT_BITS-1:0]                 grant_ptr_arbiter;
    logic [NUM_PORTS-1:0][PORT_BITS-1:0]                 accept_ptr_arbiter;

    genvar i, j;
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : INGRESS_PORT_GEN
            for (j = 0; j < NUM_PORTS; j++) begin : VOQ_MATRIX_GEN

                always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                    if (!sys_aresetn) begin
                        voq_wr_ptr[i][j] <= '0;
                        voq_rd_ptr[i][j] <= '0;
                        voq_count[i][j]  <= '0;
                    end else begin
                        automatic logic wr_en = ingress_tvalid[i] && (ingress_tdest[i] == j) && !voq_full[i][j];
                        automatic logic rd_en = accept_matrix[i][j] && !voq_empty[i][j];

                        if (wr_en && !rd_en) begin
                            voq_ram[voq_wr_ptr[i][j]][i][j] <= ingress_tdata[i];
                            voq_wr_ptr[i][j] <= (voq_wr_ptr[i][j] == VOQ_DEPTH-1) ? '0 : voq_wr_ptr[i][j] + 1;
                            voq_count[i][j]  <= voq_count[i][j] + 1;
                        end else if (!wr_en && rd_en) begin
                            voq_rd_ptr[i][j] <= (voq_rd_ptr[i][j] == VOQ_DEPTH-1) ? '0 : voq_rd_ptr[i][j] + 1;
                            voq_count[i][j]  <= voq_count[i][j] - 1;
                        end else if (wr_en && rd_en) begin
                            voq_ram[voq_wr_ptr[i][j]][i][j] <= ingress_tdata[i];
                            voq_wr_ptr[i][j] <= (voq_wr_ptr[i][j] == VOQ_DEPTH-1) ? '0 : voq_wr_ptr[i][j] + 1;
                            voq_rd_ptr[i][j] <= (voq_rd_ptr[i][j] == VOQ_DEPTH-1) ? '0 : voq_rd_ptr[i][j] + 1;
                        end
                    end
                end

                assign voq_empty[i][j] = (voq_count[i][j] == 0);
                assign voq_full[i][j]  = (voq_count[i][j] == VOQ_DEPTH);
                assign req_matrix[i][j] = !voq_empty[i][j];

            end

            assign ingress_tready[i] = !voq_full[i][ingress_tdest[i]];
        end
    endgenerate

    logic [NUM_PORTS-1:0] grant_valid;
    logic [NUM_PORTS-1:0] accept_valid;

    typedef enum logic [1:0] {
        IDLE     = 2'b00,
        REQ      = 2'b01,
        GRANT    = 2'b10,
        ACCEPT   = 2'b11
    } islip_state_t;

    islip_state_t current_state, next_state;
    logic [$clog2(MAX_ITER)-1:0] iter_count;

    always_ff @(posedge sys_clk or negedge sys_aresetn) begin
        if (!sys_aresetn) begin
            current_state <= IDLE;
            iter_count    <= '0;
        end else begin
            current_state <= next_state;
            if (current_state == ACCEPT && next_state == REQ) begin
                iter_count <= iter_count + 1;
            end else if (next_state == IDLE) begin
                iter_count <= '0;
            end
        end
    end
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0] next_grant_matrix;
    logic [NUM_PORTS-1:0][NUM_PORTS-1:0] next_accept_matrix;

    generate
        for (j = 0; j < NUM_PORTS; j++) begin : GRANT_ARBITER_GEN
            always_comb begin
                automatic logic [NUM_PORTS-1:0] req_vec;
                automatic logic [NUM_PORTS-1:0] req_masked;
                automatic logic [NUM_PORTS-1:0] grant_vec;
                automatic logic [NUM_PORTS-1:0] mask;

                for (int i = 0; i < NUM_PORTS; i++) begin
                    req_vec[i] = req_matrix[i][j];
                end

                mask = (1 << grant_ptr_arbiter[j]) - 1;
                req_masked = req_vec & ~mask;

                if (req_masked != 0) begin
                    grant_vec = req_masked & ~(req_masked - 1);
                end else if (req_vec != 0) begin
                    grant_vec = req_vec & ~(req_vec - 1);
                end else begin
                    grant_vec = '0;
                end

                for (int i = 0; i < NUM_PORTS; i++) begin
                    next_grant_matrix[i][j] = grant_vec[i];
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < NUM_PORTS; i++) begin : ACCEPT_ARBITER_GEN
            always_comb begin
                automatic logic [NUM_PORTS-1:0] grant_vec;
                automatic logic [NUM_PORTS-1:0] grant_masked;
                automatic logic [NUM_PORTS-1:0] accept_vec;
                automatic logic [NUM_PORTS-1:0] mask;

                for (int j = 0; j < NUM_PORTS; j++) begin
                    grant_vec[j] = grant_matrix[i][j];
                end

                mask = (1 << accept_ptr_arbiter[i]) - 1;
                grant_masked = grant_vec & ~mask;

                if (grant_masked != 0) begin
                    accept_vec = grant_masked & ~(grant_masked - 1);
                end else if (grant_vec != 0) begin
                    accept_vec = grant_vec & ~(grant_vec - 1);
                end else begin
                    accept_vec = '0;
                end

                for (int j = 0; j < NUM_PORTS; j++) begin
                    next_accept_matrix[i][j] = accept_vec[j];
                end
            end
        end
    endgenerate

    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (|req_matrix) begin
                    next_state = REQ;
                end
            end
            REQ: begin
                next_state = GRANT;
            end
            GRANT: begin
                next_state = ACCEPT;
            end
            ACCEPT: begin
                if (iter_count == MAX_ITER - 1) begin
                    next_state = IDLE;
                end else begin
                    next_state = REQ;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge sys_clk or negedge sys_aresetn) begin
        if (!sys_aresetn) begin
            grant_matrix <= '0;
            accept_matrix <= '0;
            for (int k = 0; k < NUM_PORTS; k++) begin
                grant_ptr_arbiter[k] <= '0;
                accept_ptr_arbiter[k] <= '0;
            end
        end else begin
            if (current_state == IDLE) begin
                grant_matrix <= '0;
                accept_matrix <= '0;
            end else if (current_state == REQ) begin
                grant_matrix <= next_grant_matrix;
            end else if (current_state == GRANT) begin
                accept_matrix <= next_accept_matrix;
                
                if (iter_count == 0) begin
                    for (int x = 0; x < NUM_PORTS; x++) begin
                        for (int y = 0; y < NUM_PORTS; y++) begin
                            if (next_accept_matrix[y][x]) begin
                                grant_ptr_arbiter[x] <= (y == NUM_PORTS - 1) ? '0 : (y + 1);
                            end
                        end
                    end
                    
                    for (int y = 0; y < NUM_PORTS; y++) begin
                        for (int x = 0; x < NUM_PORTS; x++) begin
                            if (next_accept_matrix[y][x]) begin
                                accept_ptr_arbiter[y] <= (x == NUM_PORTS - 1) ? '0 : (x + 1);
                            end
                        end
                    end
                end
            end
        end
    end

    generate
        for (j = 0; j < NUM_PORTS; j++) begin : CROSSBAR_MUX_EGRESS
            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    egress_tdata[j]  <= '0;
                    egress_tvalid[j] <= 1'b0;
                end else begin
                    automatic logic port_active = 1'b0;
                    automatic int src_port = 0;
                    
                    for (int i = 0; i < NUM_PORTS; i++) begin
                        if (accept_matrix[i][j]) begin
                            port_active = 1'b1;
                            src_port = i;
                            break;
                        end
                    end
                    
                    if (port_active && egress_tready[j]) begin
                        egress_tdata[j]  <= voq_ram[voq_rd_ptr[src_port][j]][src_port][j];
                        egress_tvalid[j] <= 1'b1;
                    end else begin
                        egress_tvalid[j] <= 1'b0;
                    end
                end
            end
        end
    endgenerate
  localparam int PIPE_STAGES = 3;
    logic [NUM_PORTS-1:0][DATA_WIDTH-1:0] egress_pipe_tdata [0:PIPE_STAGES-1];
    logic [NUM_PORTS-1:0]                 egress_pipe_tvalid [0:PIPE_STAGES-1];

    generate
        for (i = 0; i < NUM_PORTS; i++) begin : EGRESS_PIPELINE_GEN
            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    for (int p = 0; p < PIPE_STAGES; p++) begin
                        egress_pipe_tdata[p][i]  <= '0;
                        egress_pipe_tvalid[p][i] <= 1'b0;
                    end
                end else begin
                    egress_pipe_tdata[0][i]  <= egress_tdata[i];
                    egress_pipe_tvalid[0][i] <= egress_tvalid[i];

                    for (int p = 1; p < PIPE_STAGES; p++) begin
                        egress_pipe_tdata[p][i]  <= egress_pipe_tdata[p-1][i];
                        egress_pipe_tvalid[p][i] <= egress_pipe_tvalid[p-1][i];
                    end
                end
            end
        end
    endgenerate

    logic [NUM_PORTS-1:0][31:0] crc32_lfsr;
    logic [NUM_PORTS-1:0]       crc32_err_flag;
    logic [31:0]                crc32_poly = 32'h04C11DB7;

    generate
        for (i = 0; i < NUM_PORTS; i++) begin : PARALLEL_CRC32_GEN
            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    crc32_lfsr[i]     <= 32'hFFFFFFFF;
                    crc32_err_flag[i] <= 1'b0;
                end else if (egress_pipe_tvalid[PIPE_STAGES-1][i]) begin
                    automatic logic [31:0] current_crc = crc32_lfsr[i];
                    automatic logic [DATA_WIDTH-1:0] data_chunk = egress_pipe_tdata[PIPE_STAGES-1][i];
                    
                    for (int byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx++) begin
                        automatic logic [7:0] data_byte = data_chunk[(byte_idx*8) +: 8];
                        current_crc = current_crc ^ {data_byte, 24'h000000};
                        
                        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
                            if (current_crc[31]) begin
                                current_crc = (current_crc << 1) ^ crc32_poly;
                            end else begin
                                current_crc = current_crc << 1;
                            end
                        end
                    end
                    
                    crc32_lfsr[i] <= current_crc;
                    
                    if (data_chunk[63:56] == 8'hFD) begin
                        if (current_crc != 32'hC704DD7B) begin
                            crc32_err_flag[i] <= 1'b1;
                        end else begin
                            crc32_err_flag[i] <= 1'b0;
                        end
                        crc32_lfsr[i] <= 32'hFFFFFFFF;
                    end else begin
                        crc32_err_flag[i] <= 1'b0;
                    end
                end else begin
                    crc32_err_flag[i] <= 1'b0;
                end
            end
        end
    endgenerate

    (* use_dsp = "yes" *) logic [NUM_PORTS-1:0][63:0] dsp_rx_byte_cnt;
    (* use_dsp = "yes" *) logic [NUM_PORTS-1:0][63:0] dsp_tx_byte_cnt;
    (* use_dsp = "yes" *) logic [NUM_PORTS-1:0][31:0] dsp_drop_pkt_cnt;
    (* use_dsp = "yes" *) logic [NUM_PORTS-1:0][31:0] dsp_crc_err_cnt;

    generate
        for (i = 0; i < NUM_PORTS; i++) begin : DSP_PERF_COUNTERS_GEN
            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    dsp_rx_byte_cnt[i]  <= '0;
                    dsp_tx_byte_cnt[i]  <= '0;
                    dsp_drop_pkt_cnt[i] <= '0;
                    dsp_crc_err_cnt[i]  <= '0;
                end else begin
                    if (ingress_tvalid[i] && ingress_tready[i]) begin
                        dsp_rx_byte_cnt[i] <= dsp_rx_byte_cnt[i] + (DATA_WIDTH/8);
                    end else if (ingress_tvalid[i] && !ingress_tready[i]) begin
                        if (ingress_tdata[i][63:56] == 8'hFB) begin
                            dsp_drop_pkt_cnt[i] <= dsp_drop_pkt_cnt[i] + 1;
                        end
                    end

                    if (egress_pipe_tvalid[PIPE_STAGES-1][i]) begin
                        dsp_tx_byte_cnt[i] <= dsp_tx_byte_cnt[i] + (DATA_WIDTH/8);
                    end

                    if (crc32_err_flag[i]) begin
                        dsp_crc_err_cnt[i] <= dsp_crc_err_cnt[i] + 1;
                    end
                end
            end
        end
    endgenerate
  typedef struct packed {
        logic [7:0]  port_id;
        logic [63:0] rx_bytes;
        logic [63:0] tx_bytes;
        logic [31:0] drop_pkts;
        logic [31:0] crc_errs;
        logic        token_valid;
        logic        data_valid;
    } telemetry_flit_t;

    telemetry_flit_t telemetry_ring [0:NUM_PORTS-1];
    logic [7:0]      master_token_generator;
    logic [31:0]     telemetry_interval_cnt;

    always_ff @(posedge sys_clk or negedge sys_aresetn) begin
        if (!sys_aresetn) begin
            master_token_generator <= '0;
            telemetry_interval_cnt <= '0;
            telemetry_ring[0]      <= '0;
        end else begin
            telemetry_interval_cnt <= telemetry_interval_cnt + 1;
            
            if (telemetry_interval_cnt == 32'h000F_FFFF) begin
                telemetry_ring[0].port_id     <= master_token_generator;
                telemetry_ring[0].token_valid <= 1'b1;
                telemetry_ring[0].data_valid  <= 1'b0;
                telemetry_ring[0].rx_bytes    <= '0;
                telemetry_ring[0].tx_bytes    <= '0;
                telemetry_ring[0].drop_pkts   <= '0;
                telemetry_ring[0].crc_errs    <= '0;
                
                master_token_generator <= (master_token_generator == NUM_PORTS - 1) ? '0 : master_token_generator + 1;
                telemetry_interval_cnt <= '0;
            end else begin
                telemetry_ring[0] <= telemetry_ring[NUM_PORTS-1];
            end
        end
    end

    generate
        for (i = 1; i < NUM_PORTS; i++) begin : TELEMETRY_RING_NODES
            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    telemetry_ring[i] <= '0;
                end else begin
                    automatic telemetry_flit_t incoming_flit = telemetry_ring[i-1];
                    
                    if (incoming_flit.token_valid && incoming_flit.port_id == i && !incoming_flit.data_valid) begin
                        telemetry_ring[i].port_id     <= incoming_flit.port_id;
                        telemetry_ring[i].token_valid <= 1'b1;
                        telemetry_ring[i].data_valid  <= 1'b1;
                        telemetry_ring[i].rx_bytes    <= dsp_rx_byte_cnt[i];
                        telemetry_ring[i].tx_bytes    <= dsp_tx_byte_cnt[i];
                        telemetry_ring[i].drop_pkts   <= dsp_drop_pkt_cnt[i];
                        telemetry_ring[i].crc_errs    <= dsp_crc_err_cnt[i];
                    end else begin
                        telemetry_ring[i] <= incoming_flit;
                    end
                end
            end
        end
    endgenerate

    logic [NUM_PORTS-1:0] port_degradation_mask;
    logic [7:0]           thermal_duty_cycle;
    logic                 global_throttle_stall;
    logic [7:0]           throttle_counter;

    always_ff @(posedge sys_clk or negedge sys_aresetn) begin
        if (!sys_aresetn) begin
            global_throttle_stall <= 1'b0;
            throttle_counter      <= '0;
            port_degradation_mask <= '0;
        end else begin
            throttle_counter <= throttle_counter + 1;
            
            if (thermal_duty_cycle > 0) begin
                if (throttle_counter >= (255 - thermal_duty_cycle)) begin
                    global_throttle_stall <= 1'b1;
                end else begin
                    global_throttle_stall <= 1'b0;
                end
            end else begin
                global_throttle_stall <= 1'b0;
            end

            for (int k = 0; k < NUM_PORTS; k++) begin
                if (dsp_crc_err_cnt[k] > 32'h0000_FFFF || dsp_drop_pkt_cnt[k] > 32'h000F_FFFF) begin
                    port_degradation_mask[k] <= 1'b1;
                end
            end
        end
    end

    logic [NUM_PORTS-1:0][15:0] egress_credit_counter;
    logic [NUM_PORTS-1:0]       credit_starved;

    generate
        for (i = 0; i < NUM_PORTS; i++) begin : CREDIT_FLOW_CONTROL
            always_ff @(posedge sys_clk or negedge sys_aresetn) begin
                if (!sys_aresetn) begin
                    egress_credit_counter[i] <= 16'hFFFF;
                    credit_starved[i]        <= 1'b0;
                end else begin
                    automatic logic credit_consume = egress_tvalid[i] && egress_tready[i];
                    automatic logic credit_return  = (telemetry_ring[i].data_valid && telemetry_ring[i].port_id == i);

                    if (credit_consume && !credit_return) begin
                        egress_credit_counter[i] <= egress_credit_counter[i] - 1;
                    end else if (!credit_consume && credit_return) begin
                        egress_credit_counter[i] <= egress_credit_counter[i] + 64; 
                    end

                    if (egress_credit_counter[i] < 16'h00FF) begin
                        credit_starved[i] <= 1'b1;
                    end else begin
                        credit_starved[i] <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < NUM_PORTS; i++) begin : THROTTLE_INJECTION
            always_comb begin
                if (global_throttle_stall || port_degradation_mask[i] || credit_starved[i]) begin
                    for (int j = 0; j < NUM_PORTS; j++) begin
                        next_grant_matrix[i][j] = 1'b0;
                    end
                end
            end
        end
    endgenerate
(* ram_style = "block" *) logic [191:0] telemetry_shadow_ram [0:NUM_PORTS-1];

    always_ff @(posedge sys_clk) begin
        if (telemetry_ring[NUM_PORTS-1].token_valid && telemetry_ring[NUM_PORTS-1].data_valid) begin
            telemetry_shadow_ram[telemetry_ring[NUM_PORTS-1].port_id] <= {
                telemetry_ring[NUM_PORTS-1].crc_errs,   // 32-bit
                telemetry_ring[NUM_PORTS-1].drop_pkts,  // 32-bit
                telemetry_ring[NUM_PORTS-1].tx_bytes,   // 64-bit
                telemetry_ring[NUM_PORTS-1].rx_bytes    // 64-bit
            };
        end
    end

    // Opsiyonel: Sentezleyicinin (Vivado) bu BRAM'i silmemesi (Optimize away) için sahte bir okuma portu
    (* dont_touch = "yes" *) logic [191:0] dummy_read_keep;
    always_ff @(posedge sys_clk) begin
        dummy_read_keep <= telemetry_shadow_ram[telemetry_interval_cnt[7:0]];
    end

endmodule
