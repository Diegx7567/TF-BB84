-- tb_axil_bridge: emula un maestro AXI-Lite (como el XDMA) escribiendo y
-- leyendo indices, con un reg_file real detras. Comprueba que:
--  (1) una escritura AXI en la direccion 4*i llega al indice i,
--  (2) la lectura devuelve lo escrito (readback, imprescindible para el RMW),
--  (3) la version se lee en el indice 0,
--  (4) los handshake terminan (no se cuelga ninguna transaccion).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_axil_bridge is end entity;
architecture sim of tb_axil_bridge is
  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';
  signal awaddr, araddr, wdata, rdata : std_logic_vector(31 downto 0) := (others=>'0');
  signal awvalid, awready, wvalid, wready, bvalid, bready : std_logic := '0';
  signal arvalid, arready, rvalid, rready : std_logic := '0';
  signal wstrb : std_logic_vector(3 downto 0) := "1111";
  signal bresp, rresp : std_logic_vector(1 downto 0);
  -- interfaz sencilla hacia el top
  signal wr_en, rd_en, rd_valid : std_logic;
  signal wr_addr, rd_addr : unsigned(11 downto 0);
  signal wr_data, rd_data : std_logic_vector(31 downto 0);
  signal gty : std_logic_vector(5*64-1 downto 0);
  signal fp : std_logic; signal sc : unsigned(7 downto 0);
  signal clk_tx : std_logic := '0';
begin
  clk <= not clk after 4 ns;
  clk_tx <= not clk_tx after 1600 ps;

  dut : entity work.axil_bridge
    port map (clk=>clk, rstn=>rstn,
      awaddr=>awaddr, awvalid=>awvalid, awready=>awready,
      wdata=>wdata, wstrb=>wstrb, wvalid=>wvalid, wready=>wready,
      bresp=>bresp, bvalid=>bvalid, bready=>bready,
      araddr=>araddr, arvalid=>arvalid, arready=>arready,
      rdata=>rdata, rresp=>rresp, rvalid=>rvalid, rready=>rready,
      wr_en=>wr_en, wr_addr=>wr_addr, wr_data=>wr_data,
      rd_en=>rd_en, rd_addr=>rd_addr, rd_data=>rd_data, rd_valid=>rd_valid);

  -- top real detras: valida la cadena AXI -> reg_file -> AXI
  top : entity work.ab_top
    port map (clk_host=>clk, rst=>'0',
      wr_en=>wr_en, wr_addr=>wr_addr, wr_data=>wr_data,
      rd_en=>rd_en, rd_addr=>rd_addr, rd_data=>rd_data, rd_valid=>rd_valid,
      clk_tx=>clk_tx, gty_txdata=>gty, frame_pulse=>fp, sym_cnt=>sc);

  process
    variable got : integer;
    variable fails : integer := 0;
    -- escritura AXI-Lite completa
    procedure axi_write(idx : natural; val : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      awaddr <= std_logic_vector(to_unsigned(idx*4, 32));  -- indice -> bytes
      wdata  <= val;
      awvalid <= '1'; wvalid <= '1'; bready <= '1';
      wait until rising_edge(clk) and awready = '1';
      awvalid <= '0';
      if wready /= '1' then
        wait until rising_edge(clk) and wready = '1';
      end if;
      wvalid <= '0';
      wait until rising_edge(clk) and bvalid = '1';     -- espera respuesta
      wait until rising_edge(clk);
      bready <= '0';
    end procedure;
    -- lectura AXI-Lite completa
    procedure axi_read(idx : natural; result : out integer) is
    begin
      wait until rising_edge(clk);
      araddr <= std_logic_vector(to_unsigned(idx*4, 32));
      arvalid <= '1'; rready <= '1';
      wait until rising_edge(clk) and arready = '1';
      arvalid <= '0';
      wait until rising_edge(clk) and rvalid = '1';
      result := to_integer(unsigned(rdata));
      wait until rising_edge(clk);
      rready <= '0';
    end procedure;
  begin
    wait for 40 ns; rstn <= '1'; wait for 40 ns;

    -- (3) version en el indice 0
    axi_read(0, got);
    if got /= 16#1A081002# then
      report "version inesperada: "&integer'image(got) severity error;
      fails := fails + 1;
    end if;

    -- (1)+(2) escribe y relee varios indices de configuracion
    axi_write(6, x"0000A5A5");
    axi_read(6, got);
    if got /= 16#A5A5# then
      report "readback 6 = "&integer'image(got) severity error;
      fails := fails + 1;
    end if;

    axi_write(9, x"00C86401");     -- umbrales: dec0=200 z1=100 z0=1
    axi_read(9, got);
    if got /= 16#C86401# then
      report "readback 9 = "&integer'image(got) severity error;
      fails := fails + 1;
    end if;

    -- comprueba que la palabra 6 no se corrompio al escribir la 9 (RMW seguro)
    axi_read(6, got);
    if got /= 16#A5A5# then
      report "la palabra 6 se corrompio: "&integer'image(got) severity error;
      fails := fails + 1;
    end if;

    if fails = 0 then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
