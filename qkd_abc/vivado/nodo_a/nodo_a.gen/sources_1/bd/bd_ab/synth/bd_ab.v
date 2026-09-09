//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
//Date        : Wed Sep  9 11:57:00 2026
//Host        : ArcosLaptop running 64-bit major release  (build 9200)
//Command     : generate_target bd_ab.bd
//Design      : bd_ab
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "bd_ab,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=bd_ab,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=4,numReposBlks=4,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=1,numPkgbdBlks=0,bdsource=USER,synth_mode=Hierarchical}" *) (* HW_HANDOFF = "bd_ab.hwdef" *) 
module bd_ab
   (pcie_mgt_rxn,
    pcie_mgt_rxp,
    pcie_mgt_txn,
    pcie_mgt_txp,
    pcie_perstn,
    pcie_refclk_clk_n,
    pcie_refclk_clk_p,
    sysclk_300_clk_n,
    sysclk_300_clk_p);
  (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_7x_mgt:1.0 pcie_mgt rxn" *) (* X_INTERFACE_MODE = "Master" *) input [7:0]pcie_mgt_rxn;
  (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_7x_mgt:1.0 pcie_mgt rxp" *) input [7:0]pcie_mgt_rxp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_7x_mgt:1.0 pcie_mgt txn" *) output [7:0]pcie_mgt_txn;
  (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_7x_mgt:1.0 pcie_mgt txp" *) output [7:0]pcie_mgt_txp;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.PCIE_PERSTN RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.PCIE_PERSTN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input pcie_perstn;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 pcie_refclk CLK_N" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME pcie_refclk, CAN_DEBUG false, FREQ_HZ 100000000" *) input [0:0]pcie_refclk_clk_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 pcie_refclk CLK_P" *) input [0:0]pcie_refclk_clk_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 sysclk_300 CLK_N" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME sysclk_300, CAN_DEBUG false, FREQ_HZ 300000000" *) input sysclk_300_clk_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 sysclk_300 CLK_P" *) input sysclk_300_clk_p;

  wire bd_clk_tx_clk_out1;
  wire [0:0]bd_refbuf_IBUF_DS_ODIV2;
  wire [0:0]bd_refbuf_IBUF_OUT;
  wire [31:0]bd_xdma_M_AXI_LITE_ARADDR;
  wire bd_xdma_M_AXI_LITE_ARREADY;
  wire bd_xdma_M_AXI_LITE_ARVALID;
  wire [31:0]bd_xdma_M_AXI_LITE_AWADDR;
  wire bd_xdma_M_AXI_LITE_AWREADY;
  wire bd_xdma_M_AXI_LITE_AWVALID;
  wire bd_xdma_M_AXI_LITE_BREADY;
  wire [1:0]bd_xdma_M_AXI_LITE_BRESP;
  wire bd_xdma_M_AXI_LITE_BVALID;
  wire [31:0]bd_xdma_M_AXI_LITE_RDATA;
  wire bd_xdma_M_AXI_LITE_RREADY;
  wire [1:0]bd_xdma_M_AXI_LITE_RRESP;
  wire bd_xdma_M_AXI_LITE_RVALID;
  wire [31:0]bd_xdma_M_AXI_LITE_WDATA;
  wire bd_xdma_M_AXI_LITE_WREADY;
  wire [3:0]bd_xdma_M_AXI_LITE_WSTRB;
  wire bd_xdma_M_AXI_LITE_WVALID;
  wire bd_xdma_axi_aclk;
  wire bd_xdma_axi_aresetn;
  wire [7:0]pcie_mgt_rxn;
  wire [7:0]pcie_mgt_rxp;
  wire [7:0]pcie_mgt_txn;
  wire [7:0]pcie_mgt_txp;
  wire pcie_perstn;
  wire [0:0]pcie_refclk_clk_n;
  wire [0:0]pcie_refclk_clk_p;
  wire sysclk_300_clk_n;
  wire sysclk_300_clk_p;

  bd_ab_bd_ab_top_0 bd_ab_top
       (.axi_aclk(bd_xdma_axi_aclk),
        .axi_aresetn(bd_xdma_axi_aresetn),
        .clk_tx(bd_clk_tx_clk_out1),
        .s_axi_araddr(bd_xdma_M_AXI_LITE_ARADDR),
        .s_axi_arready(bd_xdma_M_AXI_LITE_ARREADY),
        .s_axi_arvalid(bd_xdma_M_AXI_LITE_ARVALID),
        .s_axi_awaddr(bd_xdma_M_AXI_LITE_AWADDR),
        .s_axi_awready(bd_xdma_M_AXI_LITE_AWREADY),
        .s_axi_awvalid(bd_xdma_M_AXI_LITE_AWVALID),
        .s_axi_bready(bd_xdma_M_AXI_LITE_BREADY),
        .s_axi_bresp(bd_xdma_M_AXI_LITE_BRESP),
        .s_axi_bvalid(bd_xdma_M_AXI_LITE_BVALID),
        .s_axi_rdata(bd_xdma_M_AXI_LITE_RDATA),
        .s_axi_rready(bd_xdma_M_AXI_LITE_RREADY),
        .s_axi_rresp(bd_xdma_M_AXI_LITE_RRESP),
        .s_axi_rvalid(bd_xdma_M_AXI_LITE_RVALID),
        .s_axi_wdata(bd_xdma_M_AXI_LITE_WDATA),
        .s_axi_wready(bd_xdma_M_AXI_LITE_WREADY),
        .s_axi_wstrb(bd_xdma_M_AXI_LITE_WSTRB),
        .s_axi_wvalid(bd_xdma_M_AXI_LITE_WVALID));
  bd_ab_bd_clk_tx_0 bd_clk_tx
       (.clk_in1_n(sysclk_300_clk_n),
        .clk_in1_p(sysclk_300_clk_p),
        .clk_out1(bd_clk_tx_clk_out1));
  bd_ab_bd_refbuf_0 bd_refbuf
       (.IBUF_DS_N(pcie_refclk_clk_n),
        .IBUF_DS_ODIV2(bd_refbuf_IBUF_DS_ODIV2),
        .IBUF_DS_P(pcie_refclk_clk_p),
        .IBUF_OUT(bd_refbuf_IBUF_OUT));
  bd_ab_bd_xdma_0 bd_xdma
       (.axi_aclk(bd_xdma_axi_aclk),
        .axi_aresetn(bd_xdma_axi_aresetn),
        .cfg_mgmt_addr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .cfg_mgmt_byte_enable({1'b0,1'b0,1'b0,1'b0}),
        .cfg_mgmt_read(1'b0),
        .cfg_mgmt_write(1'b0),
        .cfg_mgmt_write_data({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .m_axi_arready(1'b0),
        .m_axi_awready(1'b0),
        .m_axi_bid({1'b0,1'b0,1'b0,1'b0}),
        .m_axi_bresp({1'b0,1'b0}),
        .m_axi_bvalid(1'b0),
        .m_axi_rdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .m_axi_rid({1'b0,1'b0,1'b0,1'b0}),
        .m_axi_rlast(1'b0),
        .m_axi_rresp({1'b0,1'b0}),
        .m_axi_rvalid(1'b0),
        .m_axi_wready(1'b0),
        .m_axil_araddr(bd_xdma_M_AXI_LITE_ARADDR),
        .m_axil_arready(bd_xdma_M_AXI_LITE_ARREADY),
        .m_axil_arvalid(bd_xdma_M_AXI_LITE_ARVALID),
        .m_axil_awaddr(bd_xdma_M_AXI_LITE_AWADDR),
        .m_axil_awready(bd_xdma_M_AXI_LITE_AWREADY),
        .m_axil_awvalid(bd_xdma_M_AXI_LITE_AWVALID),
        .m_axil_bready(bd_xdma_M_AXI_LITE_BREADY),
        .m_axil_bresp(bd_xdma_M_AXI_LITE_BRESP),
        .m_axil_bvalid(bd_xdma_M_AXI_LITE_BVALID),
        .m_axil_rdata(bd_xdma_M_AXI_LITE_RDATA),
        .m_axil_rready(bd_xdma_M_AXI_LITE_RREADY),
        .m_axil_rresp(bd_xdma_M_AXI_LITE_RRESP),
        .m_axil_rvalid(bd_xdma_M_AXI_LITE_RVALID),
        .m_axil_wdata(bd_xdma_M_AXI_LITE_WDATA),
        .m_axil_wready(bd_xdma_M_AXI_LITE_WREADY),
        .m_axil_wstrb(bd_xdma_M_AXI_LITE_WSTRB),
        .m_axil_wvalid(bd_xdma_M_AXI_LITE_WVALID),
        .pci_exp_rxn(pcie_mgt_rxn),
        .pci_exp_rxp(pcie_mgt_rxp),
        .pci_exp_txn(pcie_mgt_txn),
        .pci_exp_txp(pcie_mgt_txp),
        .sys_clk(bd_refbuf_IBUF_DS_ODIV2),
        .sys_clk_gt(bd_refbuf_IBUF_OUT),
        .sys_rst_n(pcie_perstn),
        .usr_irq_req(1'b0));
endmodule
