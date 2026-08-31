--------------------------------------------------------------------------------
-- c_top.vhd  —  TOP DE INTEGRACION del receptor C
--------------------------------------------------------------------------------
-- QUE ES:      el nivel que cablea reg_file + 4 cadenas de deteccion
--              (deskew -> filtro de flanco -> binner -> histograma) + squash
--              (canales 0/1) + copia local de la secuencia + matriz de
--              coincidencias + PRBS para los bits R del squashing.
-- PARA QUE:    esqueleto del proyecto de Vivado de C. Los 4 RXDATA de los GTY
--              (mismo quad, misma QPLL) entran por gty_rxdata; el host lee
--              histogramas y matriz por los registros.
-- COMO SE USA (mapa de campos de este top):
--   palabra 6 : [0]=enable [1]=filter_by_edge [8]=clear (flanco->pulso)
--               [9]=phase_clr (flanco->pulso: ancla el origen de trama)
--   palabras 14..15 : delays de entrada, 2 de 11 bits por palabra
--               (14.0=ch0, 14.16=ch1, 15.0=ch2, 15.16=ch3)
--   palabra 20: [5:0]=hist_addr (bin 0..63) [9:8]=hist_sel (canal)
--   palabra 21: [4:0]=coinc_idx (celda 0..29)
--   estado 70 : hist_data (bin seleccionado del canal seleccionado)
--   estado 71 : coinc_data (celda seleccionada)
--   estado 73 : CLKCTL del dominio rx
--   NOTA: el mapeo legado 200..263/300..363 (lectura invertida 363-i) se
--   preserva en reg_file para Z/X y se conectara en la integracion Vivado;
--   aqui el acceso generico via hist_sel/hist_addr cubre los 4 canales.
-- SQUASHING:   direccion = {Z1,Z0,X2,X1,X0,R2,R1,R0}: los bits Z del canal 0,
--   los X del canal 1 (bins 0/2/4 del simbolo), los R del PRBS. Los outcomes
--   alimentan la matriz junto al estado esperado de la seq_bram local.
--   El objetivo del sistema de C es comparar A y B: por eso este top permite
--   elegir con sel_tx_seq que secuencia esperada usa la matriz (la de A o la
--   de B, cargadas en las dos mitades logicas del espacio 400..431 en dos
--   tandas; para la fase de banco basta una).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qkd_pkg.all;

entity c_top is
  generic (
    G_VERSION : std_logic_vector(31 downto 0) := x"1A_08_10_03";
    N_CH      : natural := 4                          -- canales de deteccion
  );
  port (
    clk_host : in  std_logic;
    rst      : in  std_logic;
    wr_en    : in  std_logic;
    wr_addr  : in  unsigned(11 downto 0);
    wr_data  : in  std_logic_vector(31 downto 0);
    rd_en    : in  std_logic;
    rd_addr  : in  unsigned(11 downto 0);
    rd_data  : out std_logic_vector(31 downto 0);
    rd_valid : out std_logic;
    -- dominio de recepcion (RXUSRCLK2 comun del quad)
    clk_rx   : in  std_logic;
    -- de los 4 RXDATA de los GTY (64 muestras de 50 ps por canal)
    gty_rxdata : in std_logic_vector(N_CH*64-1 downto 0)
  );
end entity;

architecture rtl of c_top is
  constant CFG_W : natural := 58;
  signal cfg_flat : std_logic_vector(32*CFG_W-1 downto 0);
  signal st_flat  : std_logic_vector(32*42-1 downto 0) := (others=>'0');
  function cfgw(f : std_logic_vector; l : natural) return std_logic_vector is
    variable v : std_logic_vector(31 downto 0);       -- rango normalizado
  begin
    v := f(32*l+31 downto 32*l);
    return v;
  end function;

  -- bridge / ventanas
  signal latch_stb, clear_stb : std_logic;
  signal seq_we : std_logic;
  signal seq_addr : unsigned(4 downto 0);
  signal seq_data : std_logic_vector(31 downto 0);
  signal wave_we : std_logic;                         -- sin uso en C
  signal wave_addr : unsigned(2 downto 0);
  signal wave_data : std_logic_vector(31 downto 0);
  signal squash_we, squash_clear : std_logic;
  signal squash_data : std_logic_vector(31 downto 0);

  -- campos host y sus sincronizaciones
  signal enable_h, filt_h : std_logic;
  signal clr_h, clr_h_d, clr_stb_h : std_logic := '0';
  signal ph_h, ph_h_d, ph_stb_h : std_logic := '0';
  signal en_s1, en_s2, ft_s1, ft_s2 : std_logic := '0';
  signal clear_rx, phase_clr_rx : std_logic;

  -- cadena por canal
  signal dly_out  : std_logic_vector(N_CH*64-1 downto 0);
  signal edge_out : std_logic_vector(N_CH*64-1 downto 0);
  type bins_arr_t is array (0 to N_CH-1) of std_logic_vector(31 downto 0);
  signal bins : bins_arr_t;

  -- lectura de histogramas
  signal hist_addr : unsigned(5 downto 0);
  type hd_t is array (0 to N_CH-1) of std_logic_vector(31 downto 0);
  signal hist_data : hd_t;

  -- squashing (canales 0=Z, 1=X) y matriz
  signal rnd12 : std_logic_vector(11 downto 0);       -- 3 bits R x 4 simbolos
  signal sq_o0, sq_o1, sq_o2, sq_o3 : std_logic_vector(9 downto 0);
  signal sym_cnt : unsigned(7 downto 0) := (others=>'0');
  -- arrays indexados por simbolo del ciclo (evitan multiples drivers desde
  -- los generate: cada iteracion escribe SOLO su elemento)
  type st3_arr_t is array (0 to 3) of std_logic_vector(2 downto 0);
  type a8_arr_t  is array (0 to 3) of std_logic_vector(7 downto 0);
  signal st_arr : st3_arr_t;                          -- estados esperados
  signal sq_a   : a8_arr_t;                           -- direcciones de squash
  -- alineacion de estados con la latencia del squash (1 ciclo)
  signal st0_q, st1_q, st2_q, st3_q : std_logic_vector(2 downto 0);
  signal valid_v : std_logic_vector(3 downto 0);
  signal out0_u, out1_u, out2_u, out3_u : unsigned(2 downto 0);
  signal coinc_cnt : std_logic_vector(31 downto 0);
  signal clkctl_rx : std_logic_vector(31 downto 0);

  -- outcome de un simbolo a partir de la fila de squash (prioridad z0>z1>x0..)
  function to_outcome(q : std_logic_vector(9 downto 0)) return unsigned is
  begin
    if    q(8)='1' then return to_unsigned(0,3);      -- Z0
    elsif q(9)='1' then return to_unsigned(1,3);      -- Z1
    elsif q(5)='1' then return to_unsigned(2,3);      -- X0
    elsif q(6)='1' then return to_unsigned(3,3);      -- X1
    else               return to_unsigned(4,3);       -- X2 (o nada; valid=0)
    end if;
  end function;
  -- hubo alguna deteccion resuelta en la fila
  function any_click(q : std_logic_vector(9 downto 0)) return std_logic is
  begin
    return q(9) or q(8) or q(7) or q(6) or q(5);
  end function;
begin
  ----------------------------------------------------------------------------
  -- Banco de registros
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

  enable_h <= cfgw(cfg_flat,0)(0);                    -- palabra 6
  filt_h   <= cfgw(cfg_flat,0)(1);
  clr_h    <= cfgw(cfg_flat,0)(8);
  ph_h     <= cfgw(cfg_flat,0)(9);

  -- flancos -> pulsos -> CDC (clear general y anclaje de fase)
  process(clk_host) begin
    if rising_edge(clk_host) then
      clr_h_d <= clr_h;  clr_stb_h <= clr_h and not clr_h_d;
      ph_h_d  <= ph_h;   ph_stb_h  <= ph_h  and not ph_h_d;
    end if;
  end process;
  u_cdc_clr : entity work.cdc_pulse
    port map (src_clk=>clk_host, src_pulse=>clr_stb_h,
              dst_clk=>clk_rx, dst_pulse=>clear_rx);
  u_cdc_ph : entity work.cdc_pulse
    port map (src_clk=>clk_host, src_pulse=>ph_stb_h,
              dst_clk=>clk_rx, dst_pulse=>phase_clr_rx);

  process(clk_rx) begin                               -- niveles cuasi-estaticos
    if rising_edge(clk_rx) then
      en_s1<=enable_h; en_s2<=en_s1;
      ft_s1<=filt_h;   ft_s2<=ft_s1;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Las 4 cadenas: deskew -> filtro de flanco -> binner -> histograma
  ----------------------------------------------------------------------------
  hist_addr <= unsigned(cfgw(cfg_flat,14)(5 downto 0));  -- palabra 20

  gen_ch : for C in 0 to N_CH-1 generate
    signal dly_C : unsigned(10 downto 0);
  begin
    -- delay del canal C: palabra 14+C/2 (indices 20..), campo bajo/alto
    dly_C <= unsigned(cfgw(cfg_flat, 8 + C/2)(16*(C mod 2)+10 downto 16*(C mod 2)));

    u_dly : entity work.word_bit_delay
      generic map (W=>64, MAX_DELAY=>2047)
      port map (clk=>clk_rx, rst=>'0', delay=>dly_C,
                din=>gty_rxdata(C*64+63 downto C*64),
                dout=>dly_out(C*64+63 downto C*64));

    u_edge : entity work.edge_filter generic map (W=>64)
      port map (clk=>clk_rx, enable=>ft_s2,
                din=>dly_out(C*64+63 downto C*64),
                dout=>edge_out(C*64+63 downto C*64));

    u_bin : entity work.binner
      generic map (W=>64, SAMPLES_PER_BIN=>2, BINS_PER_SYMBOL=>8)
      port map (clk=>clk_rx,
                din=>edge_out(C*64+63 downto C*64),
                bins=>bins(C));

    u_hist : entity work.histogram generic map (G_WIN_CYCLES=>6_250_000)
      port map (clk=>clk_rx, bins_in=>bins(C), phase_clr=>phase_clr_rx,
                rd_addr=>hist_addr, rd_data=>hist_data(C));
  end generate;

  ----------------------------------------------------------------------------
  -- Copia local de la secuencia esperada + contador de simbolo
  ----------------------------------------------------------------------------
  process(clk_rx) begin
    if rising_edge(clk_rx) then
      if clear_rx = '1' then
        sym_cnt <= (others=>'0');                     -- reancla el origen
      elsif en_s2 = '1' then
        sym_cnt <= sym_cnt + 4;                       -- 4 simbolos por ciclo
      end if;
    end if;
  end process;

  -- cuatro lectores de la secuencia (uno por simbolo del ciclo); latencia 2,
  -- igual que la ruta bins->squash_addr->outcome, quedan alineados con st*_q
  gen_seq : for K in 0 to 3 generate
    signal sym_k : unsigned(7 downto 0);
  begin
    sym_k <= sym_cnt + K;                             -- simbolo K del ciclo
    u_sq : entity work.seq_bram
      port map (clk_wr=>clk_host, we=>seq_we, waddr=>seq_addr, wdata=>seq_data,
                clk_rd=>clk_rx, sym=>sym_k, state=>st_arr(K));
  end generate;

  ----------------------------------------------------------------------------
  -- PRBS de los bits R + squashing (Z=canal 0, X=canal 1) + matriz
  ----------------------------------------------------------------------------
  u_prbs : entity work.prbs_gen generic map (NBITS=>12)
    port map (clk=>clk_rx, clear=>clear_rx, enable=>en_s2, dout=>rnd12);

  -- direccion de squash del simbolo s: {Z1,Z0,X2,X1,X0,R2,R1,R0}
  -- Z0/Z1 = bins 0/2 del canal 0; X0/X1/X2 = bins 0/2/4 del canal 1
  gen_addr : for S in 0 to 3 generate
  begin
    sq_a(S)(7) <= bins(0)(S*8+2);                     -- Z1 (bin tardio)
    sq_a(S)(6) <= bins(0)(S*8+0);                     -- Z0 (bin temprano)
    sq_a(S)(5) <= bins(1)(S*8+4);                     -- X2
    sq_a(S)(4) <= bins(1)(S*8+2);                     -- X1
    sq_a(S)(3) <= bins(1)(S*8+0);                     -- X0
    sq_a(S)(2 downto 0) <= rnd12(S*3+2 downto S*3);   -- R2 R1 R0
  end generate;

  u_squash : entity work.squash_lut
    port map (wclk=>clk_host, we=>squash_we, wclear=>squash_clear,
              wdata=>squash_data(9 downto 0),
              rclk=>clk_rx,
              addr0=>sq_a(0), addr1=>sq_a(1), addr2=>sq_a(2), addr3=>sq_a(3),
              out0=>sq_o0, out1=>sq_o1, out2=>sq_o2, out3=>sq_o3);

  -- alinear estados esperados (latencia seq=2) con outcomes (bins reg en
  -- binner + squash reg = tambien 2 desde edge_out): un registro extra comun
  process(clk_rx) begin
    if rising_edge(clk_rx) then
      st0_q <= st_arr(0); st1_q <= st_arr(1);       -- alineacion +1 ciclo
      st2_q <= st_arr(2); st3_q <= st_arr(3);
      valid_v(0) <= any_click(sq_o0) and en_s2;
      valid_v(1) <= any_click(sq_o1) and en_s2;
      valid_v(2) <= any_click(sq_o2) and en_s2;
      valid_v(3) <= any_click(sq_o3) and en_s2;
      out0_u <= to_outcome(sq_o0);
      out1_u <= to_outcome(sq_o1);
      out2_u <= to_outcome(sq_o2);
      out3_u <= to_outcome(sq_o3);
    end if;
  end process;

  u_matrix : entity work.coincidence_matrix
    port map (clk=>clk_rx, clear=>clear_rx, valid=>valid_v,
              out0=>out0_u, out1=>out1_u, out2=>out2_u, out3=>out3_u,
              st0=>unsigned(st0_q), st1=>unsigned(st1_q),
              st2=>unsigned(st2_q), st3=>unsigned(st3_q),
              rd_idx=>unsigned(cfgw(cfg_flat,15)(4 downto 0)),
              rd_cnt=>coinc_cnt);

  ----------------------------------------------------------------------------
  -- Instrumentacion y palabras de estado
  ----------------------------------------------------------------------------
  u_cc : entity work.clk_counter generic map (G_WIN_CYCLES=>250_000_000)
    port map (clk_meas=>clk_rx, clk_host=>clk_host,
              latch_stb=>latch_stb, clear_stb=>clear_stb,
              count_win=>clkctl_rx);

  -- estado 70 = hist del canal seleccionado; 71 = celda de la matriz; 73=CLKCTL
  -- OJO: la palabra de estado w corresponde al indice 64+w (G_ST_LO=64 en el
  -- reg_file), asi que 70->w6, 71->w7, 73->w9 (era el fallo del primer humo)
  st_flat(32*6+31 downto 32*6) <=
      hist_data(to_integer(unsigned(cfgw(cfg_flat,14)(9 downto 8))));
  st_flat(32*7+31 downto 32*7) <= coinc_cnt;
  st_flat(32*9+31 downto 32*9) <= clkctl_rx;
end architecture;
