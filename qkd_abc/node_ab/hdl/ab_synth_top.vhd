--------------------------------------------------------------------------------
-- ab_synth_top.vhd
--------------------------------------------------------------------------------
-- QUE ES:      envoltorio de SINTESIS del nodo transmisor (A o B). Es el "top"
--              real del proyecto de Vivado en la FASE 1 (bring-up del bridge).
-- PARA QUE:    permite sintetizar y probar en placa el camino PCIe -> registros
--              ANTES de tener los GTY. En esta fase clk_tx viene de un MMCM
--              sobre el reloj de placa, y gty_txdata se lleva a unos pocos
--              pines/ILA para observarlo. Cuando se anhadan los GTY, clk_tx
--              pasa a ser TXUSRCLK2 y gty_txdata va a los TXDATA.
-- COMO SE USA: es el 'top' declarado en create_project_ab.tcl. La IP XDMA se
--              instancia por TCL (fase 1b) y se conecta a este bloque.
-- CONECTADO A: XDMA M_AXI_LITE -> axil_bridge -> ab_top -> (futuro) GTY.
-- IMPORTANTE:  este fichero se compila como VHDL-93 (no 2008) porque Vivado
--              no admite un top VHDL-2008 como modulo referenciado en un
--              Block Design. Sus MODULOS HIJOS si son VHDL-2008: la
--              restriccion afecta solo al fichero raiz de la referencia.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ab_synth_top is
  generic (
    G_VERSION : std_logic_vector(31 downto 0) := x"1A081002"
  );
  port (
    -- reloj y reset del dominio host (los da el XDMA: axi_aclk/axi_aresetn)
    axi_aclk    : in  std_logic;
    axi_aresetn : in  std_logic;
    -- AXI4-Lite esclavo desde el XDMA
    s_axi_awaddr  : in  std_logic_vector(31 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(31 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    -- dominio de transmision (fase 1: MMCM; fase 2: TXUSRCLK2 del GTY)
    clk_tx      : in  std_logic;
    -- salidas de datos (fase 1: a ILA/pines de test; fase 2: a los GTY)
    gty_txdata  : out std_logic_vector(5*64-1 downto 0);
    frame_pulse : out std_logic
  );
end entity;

architecture rtl of ab_synth_top is
  signal wr_en, rd_en, rd_valid : std_logic;
  signal wr_addr, rd_addr : unsigned(11 downto 0);
  signal wr_data, rd_data : std_logic_vector(31 downto 0);
  signal sym_cnt_i : unsigned(7 downto 0);
  -- OJO VHDL-93: en un port map el actual debe ser una SENAL, no una
  -- expresion. En 2008 valdria "rst => not axi_aresetn", pero este fichero
  -- debe ser 93 para poder usarse como modulo referenciado en un Block
  -- Design de Vivado (limitacion de la herramienta: el top de la referencia
  -- no puede ser VHDL-2008). Por eso la inversion va en una senal aparte.
  signal rst_i : std_logic;
begin
  rst_i <= not axi_aresetn;                         -- reset activo alto
  -- traduce AXI-Lite a la interfaz de indices del reg_file
  u_axil : entity work.axil_bridge
    port map (
      clk => axi_aclk, rstn => axi_aresetn,
      awaddr => s_axi_awaddr, awvalid => s_axi_awvalid, awready => s_axi_awready,
      wdata => s_axi_wdata, wstrb => s_axi_wstrb, wvalid => s_axi_wvalid,
      wready => s_axi_wready, bresp => s_axi_bresp, bvalid => s_axi_bvalid,
      bready => s_axi_bready, araddr => s_axi_araddr, arvalid => s_axi_arvalid,
      arready => s_axi_arready, rdata => s_axi_rdata, rresp => s_axi_rresp,
      rvalid => s_axi_rvalid, rready => s_axi_rready,
      wr_en => wr_en, wr_addr => wr_addr, wr_data => wr_data,
      rd_en => rd_en, rd_addr => rd_addr, rd_data => rd_data,
      rd_valid => rd_valid);

  -- el nodo transmisor completo
  u_ab : entity work.ab_top
    generic map (G_VERSION => G_VERSION, N_LANES => 5)
    port map (
      clk_host => axi_aclk, rst => rst_i,
      wr_en => wr_en, wr_addr => wr_addr, wr_data => wr_data,
      rd_en => rd_en, rd_addr => rd_addr, rd_data => rd_data,
      rd_valid => rd_valid,
      clk_tx => clk_tx, gty_txdata => gty_txdata,
      frame_pulse => frame_pulse, sym_cnt => sym_cnt_i);
end architecture;
