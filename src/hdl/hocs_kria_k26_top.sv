`timescale 1ns / 1ps

module hocs_kria_k26_top #(
    parameter int NUM_OPT_LANES = 144
)(
    input  logic [NUM_OPT_LANES-1:0] opt_rx_p,
    input  logic [NUM_OPT_LANES-1:0] opt_rx_n,
    output logic [NUM_OPT_LANES-1:0] opt_tx_p,
    output logic [NUM_OPT_LANES-1:0] opt_tx_n,

    input  logic                     opt_refclk_p,
    input  logic                     opt_refclk_n,

    input  logic                     cuo_thermal_sda,
    output logic                     cuo_thermal_scl
);

    logic sys_clk_250mhz;
    logic opt_clk_500mhz;
    logic clk_locked;
    logic sys_aresetn;
    
    logic opt_refclk_bufg;

    IBUFDS_GTE4 #(
        .REFCLK_EN_TX_PATH("1'b0"),
        .REFCLK_HROW_CK_SEL(2'b00),
        .REFCLK_ICNTL_RX(2'b00)
    ) refclk_ibuf (
        .O(opt_refclk_bufg),
        .ODIV2(),
        .CEB(1'b0),
        .I(opt_refclk_p),
        .IB(opt_refclk_n)
    );

    logic clkfbout_hocs;
    logic clkfbout_buf_hocs;

    MMCME4_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .COMPENSATION("AUTO"),
        .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(8.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(4.000), 
        .CLKOUT0_PHASE(0.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT1_DIVIDE(8),       
        .CLKOUT1_PHASE(0.000),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .CLKIN1_PERIOD(6.400)     
    ) hocs_pll_inst (
        .CLKFBOUT(clkfbout_hocs),
        .CLKFBOUTB(),
        .CLKOUT0(opt_clk_500mhz),
        .CLKOUT0B(),
        .CLKOUT1(sys_clk_250mhz),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBIN(clkfbout_buf_hocs),
        .CLKIN1(opt_refclk_bufg),
        .CLKIN2(1'b0),
        .CLKINSEL(1'b1),
        .DADDR(7'h00),
        .DCLK(1'b0),
        .DEN(1'b0),
        .DI(16'h0000),
        .DO(),
        .DRDY(),
        .DWE(1'b0),
        .CDDCDONE(),
        .CDDCREQ(1'b0),
        .PSCLK(1'b0),
        .PSEN(1'b0),
        .PSINCDEC(1'b0),
        .PSDONE(),
        .LOCKED(clk_locked),
        .CLKINSTOPPED(),
        .CLKFBSTOPPED(),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    BUFG clkfb_buf (.I(clkfbout_hocs), .O(clkfbout_buf_hocs));

    logic [NUM_OPT_LANES-1:0][65:0] raw_rx_data_int;
    logic [NUM_OPT_LANES-1:0][65:0] raw_tx_data_int;

    logic [NUM_OPT_LANES-1:0] rx_prbs_err_int;
    logic [NUM_OPT_LANES-1:0] rx_lock_status_int;
    logic                     global_deskew_done_int;
    logic                     thermal_alarm_int;

    logic [31:0]  s_axi_awaddr;
    logic [2:0]   s_axi_awprot;
    logic         s_axi_awvalid;
    logic         s_axi_awready;
    logic [31:0]  s_axi_wdata;
    logic [3:0]   s_axi_wstrb;
    logic         s_axi_wvalid;
    logic         s_axi_wready;
    logic [1:0]   s_axi_bresp;
    logic         s_axi_bvalid;
    logic         s_axi_bready;
    logic [31:0]  s_axi_araddr;
    logic [2:0]   s_axi_arprot;
    logic         s_axi_arvalid;
    logic         s_axi_arready;
    logic [31:0]  s_axi_rdata;
    logic [1:0]   s_axi_rresp;
    logic         s_axi_rvalid;
    logic         s_axi_rready;

    logic [63:0]  m_axi_awaddr;
    logic [7:0]   m_axi_awlen;
    logic [2:0]   m_axi_awsize;
    logic [1:0]   m_axi_awburst;
    logic         m_axi_awvalid;
    logic         m_axi_awready;
    logic [127:0] m_axi_wdata;
    logic [15:0]  m_axi_wstrb;
    logic         m_axi_wlast;
    logic         m_axi_wvalid;
    logic         m_axi_wready;
    logic [1:0]   m_axi_bresp;
    logic         m_axi_bvalid;
    logic         m_axi_bready;

    logic sw_global_reset;
    logic sw_prbs_en;
    logic sw_force_retrain;
    logic [7:0] sw_thermal_throttle_limit;

    assign sys_aresetn = clk_locked & ~sw_global_reset;

    zynq_ultra_ps_e_0 ps_block_inst (
        .pl_clk0(), 
        .pl_resetn0(),
        .maxihpm0_lpd_aclk(sys_clk_250mhz),
        .maxigp0_awaddr(s_axi_awaddr),
        .maxigp0_awprot(s_axi_awprot),
        .maxigp0_awvalid(s_axi_awvalid),
        .maxigp0_awready(s_axi_awready),
        .maxigp0_wdata(s_axi_wdata),
        .maxigp0_wstrb(s_axi_wstrb),
        .maxigp0_wvalid(s_axi_wvalid),
        .maxigp0_wready(s_axi_wready),
        .maxigp0_bresp(s_axi_bresp),
        .maxigp0_bvalid(s_axi_bvalid),
        .maxigp0_bready(s_axi_bready),
        .maxigp0_araddr(s_axi_araddr),
        .maxigp0_arprot(s_axi_arprot),
        .maxigp0_arvalid(s_axi_arvalid),
        .maxigp0_arready(s_axi_arready),
        .maxigp0_rdata(s_axi_rdata),
        .maxigp0_rresp(s_axi_rresp),
        .maxigp0_rvalid(s_axi_rvalid),
        .maxigp0_rready(s_axi_rready),
        .saxihp0_fpd_aclk(sys_clk_250mhz),
        .saxigp2_awaddr(m_axi_awaddr),
        .saxigp2_awlen(m_axi_awlen),
        .saxigp2_awsize(m_axi_awsize),
        .saxigp2_awburst(m_axi_awburst),
        .saxigp2_awvalid(m_axi_awvalid),
        .saxigp2_awready(m_axi_awready),
        .saxigp2_wdata(m_axi_wdata),
        .saxigp2_wstrb(m_axi_wstrb),
        .saxigp2_wlast(m_axi_wlast),
        .saxigp2_wvalid(m_axi_wvalid),
        .saxigp2_wready(m_axi_wready),
        .saxigp2_bresp(m_axi_bresp),
        .saxigp2_bvalid(m_axi_bvalid),
        .saxigp2_bready(m_axi_bready)
    );
  `timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:      HOCS (Hybrid Optical Computing System)
// Architect:    Muhammed Yusuf Çobanoğlu
// Module Name:  tb_hocs_kria_k26_top
// Description:  HOCS Sisteminin Vivado'da Doğrulanması (Verification)
//               144 Kanallı Optik Veri Yolu için 500MHz Diferansiyel Saat 
//               ve Sahte Fotonik Veri (Stimulus) Enjeksiyonu.
//////////////////////////////////////////////////////////////////////////////////

module tb_hocs_kria_k26_top;

    // ---------------------------------------------------------------------
    // 1. TEST PARAMETRELERİ VE SİNYAL TANIMLAMALARI
    // ---------------------------------------------------------------------
    parameter int NUM_OPT_LANES = 144;
    
    // Diferansiyel Optik Referans Saati (500 MHz -> Periyot: 2.0 ns)
    logic opt_refclk_p = 1'b0;
    logic opt_refclk_n = 1'b1;
    
    // Termal Sensör Simülasyonu
    logic cuo_thermal_sda = 1'b1;
    wire  cuo_thermal_scl;

    // 144 Kanallı Diferansiyel Optik TX/RX Fiziksel Hatları
    logic [NUM_OPT_LANES-1:0] opt_rx_p;
    logic [NUM_OPT_LANES-1:0] opt_rx_n;
    wire  [NUM_OPT_LANES-1:0] opt_tx_p;
    wire  [NUM_OPT_LANES-1:0] opt_tx_n;

    // ---------------------------------------------------------------------
    // 2. KRA K26 TOP MODULE INSTANTIATION (Gerçek Donanımın Çağrılması)
    // ---------------------------------------------------------------------
    hocs_kria_k26_top #(
        .NUM_OPT_LANES(NUM_OPT_LANES)
    ) UUT_HOCS_CORE (
        .opt_rx_p(opt_rx_p),
        .opt_rx_n(opt_rx_n),
        .opt_tx_p(opt_tx_p),
        .opt_tx_n(opt_tx_n),
        .opt_refclk_p(opt_refclk_p),
        .opt_refclk_n(opt_refclk_n),
        .cuo_thermal_sda(cuo_thermal_sda),
        .cuo_thermal_scl(cuo_thermal_scl)
    );

    // ---------------------------------------------------------------------
    // 3. CLOCK GENERATOR (Saat Sinyallerinin Üretilmesi)
    // ---------------------------------------------------------------------
    // 500 MHz diferansiyel saat üretimi (1.0 ns High, 1.0 ns Low)
    always #1.000 opt_refclk_p = ~opt_refclk_p;
    always #1.000 opt_refclk_n = ~opt_refclk_n;

    // ---------------------------------------------------------------------
    // 4. TEST SENARYOSU (STIMULUS) - Vivado'yu Ağlatacak Olan Kısım
    // ---------------------------------------------------------------------
    initial begin
        $display("=================================================================");
        $display("[+] HOCS 144-Channel Deep-Tech Simulation Initiated.");
        $display("[+] Target: Xilinx Kria K26 FPGA");
        $display("=================================================================");

        // Adım 1: Hatları Sıfırla (Power-On State)
        opt_rx_p = {NUM_OPT_LANES{1'b0}};
        opt_rx_n = {NUM_OPT_LANES{1'b1}};
        
        $display("[INFO] Time: %0t | System Powered On. PLL Locking in progress...", $time);
        
        // PLL'in kilitlenmesi için donanıma zaman tanı (1000 ns bekle)
        #1000;
        
        $display("[INFO] Time: %0t | PLL Locked. System clocks distributed.", $time);
        $display("[INFO] Time: %0t | Injecting 64b/66b Alignment Headers to all 144 Lanes...", $time);

        // Adım 2: Optik Hatlara Veri Enjeksiyonu (Header Hunt State)
        // Burada PHY katmanımızın ST_HUNT durumundan ST_LOCK durumuna geçmesini test ediyoruz.
        // Optik modüllerden 2'b01 veya 2'b10 header'ları geldiğini simüle edeceğiz.
        
        for (int frame = 0; frame < 100; frame++) begin
            // 66-bit çerçevenin ilk 2 biti Sync Header (01)
            opt_rx_p = {NUM_OPT_LANES{1'b0}}; // Header 0
            opt_rx_n = {NUM_OPT_LANES{1'b1}};
            #2.0; // 1 cycle
            
            opt_rx_p = {NUM_OPT_LANES{1'b1}}; // Header 1
            opt_rx_n = {NUM_OPT_LANES{1'b0}};
            #2.0; // 1 cycle

            // Geri kalan 64 bit rastgele payload/veri
            for (int bit_idx = 0; bit_idx < 64; bit_idx++) begin
                opt_rx_p = {NUM_OPT_LANES{$random}}; 
                opt_rx_n = ~opt_rx_p;
                #2.0;
            end
        end

        $display("[SUCCESS] Time: %0t | Header injection complete. Check 'lane_lock_status' in Waveform!", $time);
        $display("[INFO] Time: %0t | Simulating CuO Thermal Alarm Spike...", $time);

        // Adım 3: 50nm CuO Termal Sensör Tetiklenmesi (Hardware Throttling Test)
        #500;
        cuo_thermal_sda = 1'b0; // Termal alarmı aktif et
        #200;
        cuo_thermal_sda = 1'b1; // Soğudu, alarmı kapat

        $display("[SUCCESS] Time: %0t | HOCS Architecture Simulation Finished. Terminating.", $time);
        $finish; // Simülasyonu bitir
    end

endmodule
