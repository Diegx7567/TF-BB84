--------------------------------------------------------------------------------
-- ab_top.vhd  —  TOP DE INTEGRACION de los transmisores A y B
--------------------------------------------------------------------------------
-- QUE ES:      el nivel que cablea reg_file + prbs + chooser + tx_datapath +
--              deskew por linea, y expone los puertos que iran a los GTY.
-- PARA QUE:    es el esqueleto del proyecto de Vivado de A y de B (identicos:
--              solo cambia la constante de version). Los GTY y el canal de
--              servicio se anhaden como IPs del wizard sobre estos puertos.
-- COMO SE USA: gty_txdata(L) -> TXDATA del GTY de la linea L (0=laser,
--              1..3=DAC D0..D2, 4=reloj DAC); clk_tx <- TXUSRCLK2 (312,5 MHz);
--              la interfaz host (wr/rd) la genera el puente XDMA/Xillybus.
-- MAPA DE CAMPOS usado por este top (palabra logica = indice - 6):
--   palabra 6 : [0]=enable [1]=use_fixed [2]=msb_first [7:3]=inv(4:0)
--               [8]=clear_seq (flanco de subida => pulso)
--   palabra 9 : [7:0]=prob_z0_up [15:8]=prob_z1_up [23:16]=prob_dec0_up
--   palabras 14..16 : delays de linea, 2 por palabra de 11 bits
--               (14.0=L0, 14.16=L1, 15.0=L2, 15.16=L3, 16.0=L4)
--   estado 70 : contador de tramas (pseudo-address extendido)
--   estado 73 : CLKCTL clk_tx (ventana en clk_host)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qkd_pkg.all;

entity ab_top is
  generic (
    G_VERSION : std_logic_vector(31 downto 0) := x"1A_08_10_02";
    N_LANES   : natural := 5
  );
  port (
    -- host (desde XDMA/Xillybus)
    clk_host : in  std_logic;
    rst      : in  std_logic;
    wr_en    : in  std_logic;
    wr_addr  : in  unsigned(11 downto 0);
    wr_data  : in  std_logic_vector(31 downto 0);
    rd_en    : in  std_logic;
    rd_addr  : in  unsigned(11 downto 0);
    rd_data  : out std_logic_vector(31 downto 0);
    rd_valid : out std_logic;
    -- dominio de transmision (TXUSRCLK2 de los GTY)
    clk_tx   : in  std_logic;
    -- hacia los TXDATA de los 5 GTY (ya con deskew aplicado)
    gty_txdata : out std_logic_vector(N_LANES*64-1 downto 0);
    -- hacia el canal de servicio (pendiente de integrar el framer)
    frame_pulse : out std_logic;
    sym_cnt     : out unsigned(7 downto 0)
  );
end entity;

architecture rtl of ab_top is
  constant CFG_W : natural := 58;                    -- palabras 6..63
  signal cfg_flat : std_logic_vector(32*CFG_W-1 downto 0);
  signal st_flat  : std_logic_vector(32*42-1 downto 0) := (others=>'0');
  -- acceso comodo a una palabra de configuracion (palabra logica l = idx-6).
  -- OJO VHDL: el rango del valor devuelto se NORMALIZA a (31 downto 0) via
  -- variable local; si se devolviera el slice directo, conservaria los
  -- indices originales (32l+31 downto 32l) y un posterior (7 downto 0)
  -- quedaria fuera de rango (fue el bound-check de la primera version).
  function cfgw(f : std_logic_vector; l : natural) return std_logic_vector is
    variable v : std_logic_vector(31 downto 0);      -- rango normalizado
  begin
    v := f(32*l+31 downto 32*l);                     -- copia la palabra l
    return v;                                        -- ahora es (31 downto 0)
  end function;

  signal latch_stb, clear_stb : std_logic;
  signal seq_we    : std_logic;
  signal seq_addr  : unsigned(4 downto 0);
  signal seq_data  : std_logic_vector(31 downto 0);
  signal wave_we   : std_logic;
  signal wave_addr : unsigned(2 downto 0);
  signal wave_data : std_logic_vector(31 downto 0);
  signal squash_we, squash_clear : std_logic;        -- sin uso en A/B
  signal squash_data : std_logic_vector(31 downto 0);

  -- campos ya troceados (dominio host)
  signal enable_h, use_fixed_h, msb_h : std_logic;
  signal inv_h    : std_logic_vector(N_LANES-1 downto 0);
  signal clr_h, clr_h_d, clr_stb_h : std_logic := '0';
  -- sus versiones sincronizadas al dominio tx (niveles cuasi-estaticos: 2FF)
  signal en_s1,en_s2, uf_s1,uf_s2, mb_s1,mb_s2 : std_logic := '0';
  signal inv_s1, inv_s2 : std_logic_vector(N_LANES-1 downto 0) := (others=>'0');
  signal clear_tx : std_logic;

  signal rnd64 : std_logic_vector(63 downto 0);
  signal ch0, ch1, ch2, ch3 : unsigned(2 downto 0);
  signal lane_raw : std_logic_vector(N_LANES*64-1 downto 0);
  signal fp_i : std_logic;
  signal sym_i : unsigned(7 downto 0);
  signal clkctl_tx : std_logic_vector(31 downto 0);
  signal frame_count : unsigned(31 downto 0) := (others=>'0');
begin
  ----------------------------------------------------------------------------
  -- Banco de registros: el contrato con Python
  ----------------------------------------------------------------------------
  u_regs : entity work.reg_file
    generic map ( G_VERSION => G_VERSION )
    port map (
      clk => clk_host, rst => rst,
      wr_en => wr_en, wr_addr => wr_addr, wr_data => wr_data,
      rd_en => rd_en, rd_addr => rd_addr, rd_data => rd_data,
      rd_valid => rd_valid,
      cfg_out => cfg_flat, st_in => st_flat,
      latch_stb => latch_stb, clear_stb => clear_stb,
      seq_we => seq_we, seq_addr => seq_addr, seq_data => seq_data,
      wave_we => wave_we, wave_addr => wave_addr, wave_data => wave_data,
      squash_we => squash_we, squash_clear => squash_clear,
      squash_data => squash_data );

  -- troceo de la palabra logica 0 (indice 6) y 3 (indice 9) — ver cabecera
  enable_h    <= cfgw(cfg_flat,0)(0);
  use_fixed_h <= cfgw(cfg_flat,0)(1);
  msb_h       <= cfgw(cfg_flat,0)(2);
  inv_h       <= cfgw(cfg_flat,0)(7 downto 3);
  clr_h       <= cfgw(cfg_flat,0)(8);

  -- flanco de subida de clear_seq en host -> pulso -> CDC al dominio tx
  process(clk_host) begin
    if rising_edge(clk_host) then
      clr_h_d   <= clr_h;                            -- retardo para el flanco
      clr_stb_h <= clr_h and not clr_h_d;            -- pulso de 1 ciclo
    end if;
  end process;
  u_cdc_clr : entity work.cdc_pulse
    port map (src_clk=>clk_host, src_pulse=>clr_stb_h,
              dst_clk=>clk_tx, dst_pulse=>clear_tx);

  -- niveles cuasi-estaticos al dominio tx (doble FF plano; en Vivado, XPM)
  process(clk_tx) begin
    if rising_edge(clk_tx) then
      en_s1<=enable_h;   en_s2<=en_s1;               -- enable
      uf_s1<=use_fixed_h;uf_s2<=uf_s1;               -- use_fixed
      mb_s1<=msb_h;      mb_s2<=mb_s1;               -- msb_first
      inv_s1<=inv_h;     inv_s2<=inv_s1;             -- inversiones
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Fuente aleatoria y sorteador (para clave real)
  ----------------------------------------------------------------------------
  u_prbs : entity work.prbs_gen generic map (NBITS=>64)
    port map (clk=>clk_tx, clear=>clear_tx, enable=>en_s2, dout=>rnd64);

  u_choo : entity work.state_chooser
    port map (clk=>clk_tx, enable=>en_s2,
              prob_z0_up   => unsigned(cfgw(cfg_flat,3)(7 downto 0)),
              prob_z1_up   => unsigned(cfgw(cfg_flat,3)(15 downto 8)),
              prob_dec0_up => unsigned(cfgw(cfg_flat,3)(23 downto 16)),
              rnd=>rnd64, st0=>ch0, st1=>ch1, st2=>ch2, st3=>ch3);

  ----------------------------------------------------------------------------
  -- El ensamblador (secuencia + LUT + SwitchMSB + inv)
  ----------------------------------------------------------------------------
  u_txdp : entity work.tx_datapath generic map (N_LANES=>N_LANES)
    port map (clk_host=>clk_host,
              seq_we=>seq_we, seq_addr=>seq_addr, seq_data=>seq_data,
              wave_we=>wave_we, wave_addr=>wave_addr, wave_data=>wave_data,
              clk_tx=>clk_tx, clear=>clear_tx, enable=>en_s2,
              use_fixed=>uf_s2, msb_first=>mb_s2, inv=>inv_s2,
              ch0=>ch0, ch1=>ch1, ch2=>ch2, ch3=>ch3,
              lane_word=>lane_raw, frame_pulse=>fp_i, sym_cnt_out=>sym_i);

  ----------------------------------------------------------------------------
  -- Deskew por linea: DelayOutputLxS (palabras logicas 8..10, 2 por palabra)
  ----------------------------------------------------------------------------
  gen_dly : for L in 0 to N_LANES-1 generate
    signal dly_L : unsigned(10 downto 0);
  begin
    -- linea L: palabra 8 + L/2, campo bajo si L par, alto si L impar
    dly_L <= unsigned(cfgw(cfg_flat, 8 + L/2)(16*(L mod 2)+10 downto 16*(L mod 2)));
    u_d : entity work.word_bit_delay
      generic map (W=>64, MAX_DELAY=>2047)
      port map (clk=>clk_tx, rst=>'0', delay=>dly_L,
                din=>lane_raw(L*64+63 downto L*64),
                dout=>gty_txdata(L*64+63 downto L*64));
  end generate;

  ----------------------------------------------------------------------------
  -- Instrumentacion: frecuencimetro del dominio tx + contador de tramas
  ----------------------------------------------------------------------------
  u_cc : entity work.clk_counter generic map (G_WIN_CYCLES=>250_000_000)
    port map (clk_meas=>clk_tx, clk_host=>clk_host,
              latch_stb=>latch_stb, clear_stb=>clear_stb,
              count_win=>clkctl_tx);
  process(clk_tx) begin
    if rising_edge(clk_tx) then
      if fp_i='1' then frame_count <= frame_count + 1; end if;
    end if;
  end process;
  -- palabras de estado: indice 70 = palabra 6, indice 73 = palabra 9
  -- (la palabra de estado w corresponde al indice 64+w: G_ST_LO=64)
  st_flat(32*6+31 downto 32*6) <= std_logic_vector(frame_count);
  st_flat(32*9+31 downto 32*9) <= clkctl_tx;

  frame_pulse <= fp_i;
  sym_cnt     <= sym_i;
end architecture;
