`timescale 1ns / 1ps

module hocs_axi_lite_csr_top #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 12,
    parameter integer NUM_LANES          = 144
)(
    input  logic                                S_AXI_ACLK,
    input  logic                                S_AXI_ARESETN,
    
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_AWADDR,
    input  logic [2:0]                          S_AXI_AWPROT,
    input  logic                                S_AXI_AWVALID,
    output logic                                S_AXI_AWREADY,
    
    input  logic [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0]   S_AXI_WSTRB,
    input  logic                                S_AXI_WVALID,
    output logic                                S_AXI_WREADY,
    
    output logic [1:0]                          S_AXI_BRESP,
    output logic                                S_AXI_BVALID,
    input  logic                                S_AXI_BREADY,
    
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_ARADDR,
    input  logic [2:0]                          S_AXI_ARPROT,
    input  logic                                S_AXI_ARVALID,
    output logic                                S_AXI_ARREADY,
    
    output logic [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_RDATA,
    output logic [1:0]                          S_AXI_RRESP,
    output logic                                S_AXI_RVALID,
    input  logic                                S_AXI_RREADY,

    input  logic [NUM_LANES-1:0]                lane_lock_status_in,
    input  logic [NUM_LANES-1:0]                lane_prbs_err_in,
    input  logic                                cuo_thermal_alarm_in,
    input  logic                                global_deskew_done_in,

    output logic                                sw_global_reset_out,
    output logic                                sw_prbs_en_out,
    output logic                                sw_force_retrain_out,
    output logic [7:0]                          sw_thermal_throttle_limit_out
);

    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    logic                          axi_awready;
    logic                          axi_wready;
    logic [1:0]                    axi_bresp;
    logic                          axi_bvalid;
    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    logic                          axi_arready;
    logic [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    logic [1:0]                    axi_rresp;
    logic                          axi_rvalid;

    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 9;

    logic slv_reg_rden;
    logic slv_reg_wren;
    logic [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    integer byte_index;
    logic aw_en;

    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg0_sys_ctrl;
    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg1_sys_stat;
    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg2_thermal;
    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg3_lane_lock_0_31;
    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg4_lane_lock_32_63;
    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg5_lane_lock_64_95;
    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg6_lane_lock_96_127;
    logic [C_S_AXI_DATA_WIDTH-1:0] slv_reg7_lane_lock_128_143;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end else begin    
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end 
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awaddr <= 0;
        end else begin    
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awaddr <= S_AXI_AWADDR;
            end
        end 
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_wready <= 1'b0;
        end else begin    
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en ) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end 
    end

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg0_sys_ctrl <= 0;
            slv_reg2_thermal <= 32'h00000050; 
        end else begin
            if (slv_reg_wren) begin
                case (axi_awaddr[OPT_MEM_ADDR_BITS+ADDR_LSB : ADDR_LSB])
                    10'h000: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1) begin
                            if (S_AXI_WSTRB[byte_index] == 1) begin
                                slv_reg0_sys_ctrl[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                            end
                        end
                    end
                    10'h002: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1) begin
                            if (S_AXI_WSTRB[byte_index] == 1) begin
                                slv_reg2_thermal[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                            end
                        end
                    end
                    default: begin
                        slv_reg0_sys_ctrl <= slv_reg0_sys_ctrl;
                        slv_reg2_thermal  <= slv_reg2_thermal;
                    end
                endcase
            end else begin
                slv_reg0_sys_ctrl[0] <= 1'b0; 
                slv_reg0_sys_ctrl[2] <= 1'b0;
            end
        end
    end
  always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 32'b0;
        end else begin    
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end 
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b0;
        end else begin    
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b0;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end                
        end
    end

    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

    always_comb begin
        case (axi_araddr[OPT_MEM_ADDR_BITS+ADDR_LSB : ADDR_LSB])
            10'h000   : reg_data_out = slv_reg0_sys_ctrl;
            10'h001   : reg_data_out = {30'd0, global_deskew_done_in, cuo_thermal_alarm_in};
            10'h002   : reg_data_out = slv_reg2_thermal;
            10'h003   : reg_data_out = lane_lock_status_in[31:0];
            10'h004   : reg_data_out = lane_lock_status_in[63:32];
            10'h005   : reg_data_out = lane_lock_status_in[95:64];
            10'h006   : reg_data_out = lane_lock_status_in[127:96];
            10'h007   : reg_data_out = {16'd0, lane_lock_status_in[143:128]};
            10'h008   : reg_data_out = lane_prbs_err_in[31:0];
            10'h009   : reg_data_out = lane_prbs_err_in[63:32];
            10'h00A   : reg_data_out = lane_prbs_err_in[95:64];
            10'h00B   : reg_data_out = lane_prbs_err_in[127:96];
            10'h00C   : reg_data_out = {16'd0, lane_prbs_err_in[143:128]};
            default   : reg_data_out = 32'hDEADBEEF;
        endcase
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rdata <= 0;
        end else begin    
            if (slv_reg_rden) begin
                axi_rdata <= reg_data_out;
            end   
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_bvalid  <= 0;
            axi_bresp   <= 2'b0;
        end else begin    
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
            end else begin
                if (S_AXI_BREADY && axi_bvalid) begin
                    axi_bvalid <= 1'b0; 
                end  
            end
        end
    end

    assign sw_global_reset_out          = slv_reg0_sys_ctrl[0];
    assign sw_prbs_en_out               = slv_reg0_sys_ctrl[1];
    assign sw_force_retrain_out         = slv_reg0_sys_ctrl[2];
    assign sw_thermal_throttle_limit_out = slv_reg2_thermal[7:0];

endmodule
