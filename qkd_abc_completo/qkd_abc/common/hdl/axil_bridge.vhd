--------------------------------------------------------------------------------
-- axil_bridge.vhd
--------------------------------------------------------------------------------
-- QUE ES:      puente AXI4-Lite esclavo -> interfaz sencilla wr_en/rd_en del
--              reg_file (los puertos que expone ab_top / c_top).
-- PARA QUE:    la IP XDMA de Xilinx habla AXI4-Lite por su puerto M_AXI_LITE;
--              nuestros tops hablan "indice + dato". Este bloque traduce.
--              Un indice del bridge = una palabra de 32 bits: la direccion
--              AXI en BYTES se divide entre 4 para obtener el indice
--              (addr[13:2] -> indice de 12 bits, 4096 indices = 16 KiB).
-- COMO SE USA: se instancia en el wrapper de sintesis entre el XDMA y el top.
--              Maneja los cinco canales AXI-Lite con handshake simple, una
--              transaccion en vuelo (suficiente: son accesos de registro).
-- CONECTADO A: XDMA M_AXI_LITE  <->  aqui  <->  ab_top / c_top.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axil_bridge is
  port (
    clk     : in  std_logic;                        -- axi_aclk (= clk_host)
    rstn    : in  std_logic;                        -- axi_aresetn (activo bajo)
    -- ---- AXI4-Lite esclavo (desde el XDMA) ----
    awaddr  : in  std_logic_vector(31 downto 0);    -- direccion de escritura
    awvalid : in  std_logic;
    awready : out std_logic;
    wdata   : in  std_logic_vector(31 downto 0);    -- dato de escritura
    wstrb   : in  std_logic_vector(3 downto 0);     -- (ignorado: acceso 32b)
    wvalid  : in  std_logic;
    wready  : out std_logic;
    bresp   : out std_logic_vector(1 downto 0);     -- respuesta de escritura
    bvalid  : out std_logic;
    bready  : in  std_logic;
    araddr  : in  std_logic_vector(31 downto 0);    -- direccion de lectura
    arvalid : in  std_logic;
    arready : out std_logic;
    rdata   : out std_logic_vector(31 downto 0);    -- dato leido
    rresp   : out std_logic_vector(1 downto 0);
    rvalid  : out std_logic;
    rready  : in  std_logic;
    -- ---- interfaz sencilla hacia el top ----
    wr_en    : out std_logic;
    wr_addr  : out unsigned(11 downto 0);
    wr_data  : out std_logic_vector(31 downto 0);
    rd_en    : out std_logic;
    rd_addr  : out unsigned(11 downto 0);
    rd_data  : in  std_logic_vector(31 downto 0);
    rd_valid : in  std_logic
  );
end entity;

architecture rtl of axil_bridge is
  -- maquina de escritura: espera direccion y dato, emite el pulso, responde
  type wst_t is (W_IDLE, W_DO, W_RESP);
  signal wst : wst_t := W_IDLE;
  signal aw_q : std_logic_vector(31 downto 0) := (others=>'0');
  signal w_q  : std_logic_vector(31 downto 0) := (others=>'0');
  signal aw_got, w_got : std_logic := '0';          -- ya llego cada canal

  -- maquina de lectura: acepta direccion, pulsa rd_en, espera rd_valid
  type rst_t is (R_IDLE, R_WAIT, R_RESP);
  signal rst_s : rst_t := R_IDLE;
  signal ar_q : std_logic_vector(31 downto 0) := (others=>'0');
  signal rdat_q : std_logic_vector(31 downto 0) := (others=>'0');
begin
  bresp <= "00";                                    -- OKAY siempre
  rresp <= "00";

  ----------------------------------------------------------------------------
  -- ESCRITURA
  ----------------------------------------------------------------------------
  process(clk) begin
    if rising_edge(clk) then
      if rstn = '0' then
        wst <= W_IDLE; aw_got <= '0'; w_got <= '0';
        awready <= '0'; wready <= '0'; bvalid <= '0'; wr_en <= '0';
      else
        wr_en   <= '0';                             -- pulso de 1 ciclo
        awready <= '0';
        wready  <= '0';
        case wst is
          when W_IDLE =>
            -- captura direccion y dato (pueden llegar en distinto ciclo)
            if awvalid = '1' and aw_got = '0' then
              aw_q <= awaddr; aw_got <= '1'; awready <= '1';
            end if;
            if wvalid = '1' and w_got = '0' then
              w_q <= wdata; w_got <= '1'; wready <= '1';
            end if;
            -- cuando estan los dos, emite la escritura al reg_file
            if (aw_got='1' or (awvalid='1' and aw_got='0')) and
               (w_got='1'  or (wvalid='1'  and w_got='0'))  then
              wst <= W_DO;
            end if;
          when W_DO =>
            wr_addr <= unsigned(aw_q(13 downto 2));  -- bytes -> indice
            wr_data <= w_q;
            wr_en   <= '1';                          -- un pulso
            bvalid  <= '1';                          -- responde OKAY
            wst     <= W_RESP;
          when W_RESP =>
            if bready = '1' then                     -- el maestro acepto
              bvalid <= '0'; aw_got <= '0'; w_got <= '0';
              wst <= W_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- LECTURA
  ----------------------------------------------------------------------------
  process(clk) begin
    if rising_edge(clk) then
      if rstn = '0' then
        rst_s <= R_IDLE; arready <= '0'; rvalid <= '0'; rd_en <= '0';
      else
        rd_en   <= '0';                             -- pulso de 1 ciclo
        arready <= '0';
        case rst_s is
          when R_IDLE =>
            if arvalid = '1' then
              ar_q    <= araddr;
              rd_addr <= unsigned(araddr(13 downto 2));  -- bytes -> indice
              rd_en   <= '1';                        -- pide el dato
              arready <= '1';                        -- acepta la direccion
              rst_s   <= R_WAIT;
            end if;
          when R_WAIT =>
            if rd_valid = '1' then                   -- el reg_file respondio
              rdat_q <= rd_data;
              rvalid <= '1';
              rst_s  <= R_RESP;
            end if;
          when R_RESP =>
            if rready = '1' then                     -- el maestro lo tomo
              rvalid <= '0';
              rst_s  <= R_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
  rdata <= rdat_q;
end architecture;
