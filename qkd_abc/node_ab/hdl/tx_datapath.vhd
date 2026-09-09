--------------------------------------------------------------------------------
-- tx_datapath.vhd
--------------------------------------------------------------------------------
-- QUE ES:      el corazon del transmisor: contador de simbolo, memoria de
--              secuencia propia, mux de fuente (fija/sorteada), consulta a la
--              waveform_lut y postproceso por linea (SwitchMSB + inversion).
-- PARA QUE:    produce, por ciclo de 312,5 MHz, una palabra de 64 muestras
--              (4 simbolos) POR LINEA, lista para el word_bit_delay y el GTY.
--              Genera ademas el frame_pulse (pseudo-address) cada 256 simbolos
--              para el canal de servicio.
-- COMO SE USA: la secuencia fija se carga por la ventana 400..431 (mismo
--              formato de 8 estados de 3 bits por palabra del software);
--              use_fixed selecciona fija (BER/calibracion) o sorteada (clave).
--              msb_first implementa el SwitchMSB_S_regw: invierte el orden
--              temporal DE LAS 16 MUESTRAS DE CADA SIMBOLO (el simbolo es la
--              unidad fisica; documentado en la sesion del SwitchMSB).
--              inv(L) invierte la polaridad de la linea L (InvDn del original).
-- CONECTADO A: reg_file (seq_we/addr/data, use_fixed, msb_first, inv, clear)
--              + state_chooser + waveform_lut (instanciada dentro) ->
--              lane_word -> word_bit_delay (uno por linea, en el top) -> GTY.
-- PIPELINE (latencia total 4 ciclos, constante):
--   e0: sym_cnt valido; direccion de palabra a la RAM de secuencia
--   e1: palabra de secuencia disponible (RAM registrada)
--   e2: 4 estados extraidos y muxeados con el chooser (registro)
--   e3: salida de la waveform_lut (registro interno de la LUT)
--   e4: postproceso msb_first/inv registrado -> lane_word
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tx_datapath is
  generic ( N_LANES : natural := 5 );
  port (
    -- dominio host: carga de secuencia (ventana 400..431 del reg_file)
    clk_host : in  std_logic;
    seq_we   : in  std_logic;
    seq_addr : in  unsigned(4 downto 0);             -- palabra 0..31
    seq_data : in  std_logic_vector(31 downto 0);    -- 8 estados de 3 bits
    -- dominio host: carga de formas de onda (ventana 500..507)
    wave_we   : in  std_logic;
    wave_addr : in  unsigned(2 downto 0);            -- estado 0..7
    wave_data : in  std_logic_vector(31 downto 0);   -- [18:16]=linea [15:0]=patron
    -- dominio tx (312,5 MHz)
    clk_tx    : in  std_logic;
    clear     : in  std_logic;                       -- ClearSeqxS (pulso CDC)
    enable    : in  std_logic;                       -- pausa/arranque
    use_fixed : in  std_logic;                       -- 1=secuencia, 0=sorteo
    msb_first : in  std_logic;                       -- SwitchMSB_S_regw
    inv       : in  std_logic_vector(N_LANES-1 downto 0);  -- InvDn por linea
    ch0, ch1, ch2, ch3 : in unsigned(2 downto 0);    -- estados del chooser
    -- salidas
    lane_word   : out std_logic_vector(N_LANES*64-1 downto 0); -- a los delays
    frame_pulse : out std_logic;                     -- cada 256 simbolos
    sym_cnt_out : out unsigned(7 downto 0)           -- para el SC / depuracion
  );
end entity;

architecture rtl of tx_datapath is
  -- RAM de secuencia propia (32x32, escritura host / lectura tx: SDP 2 relojes)
  type seq_ram_t is array (0 to 31) of std_logic_vector(31 downto 0);
  signal seq_ram : seq_ram_t := (others => (others => '0'));

  signal sym_cnt : unsigned(7 downto 0) := (others => '0');  -- simbolo actual
  -- etapa 1: palabra de secuencia y bits de seleccion retrasados
  signal seq_word_q : std_logic_vector(31 downto 0) := (others => '0');
  signal half_q     : std_logic := '0';              -- mitad de palabra (bit 2)
  -- etapa 2: los 4 estados ya elegidos (fija o sorteo)
  signal st0_q, st1_q, st2_q, st3_q : unsigned(2 downto 0) := (others => '0');
  -- chooser retrasado 2 etapas para alinear con la ruta de la secuencia
  signal ch0_q1,ch1_q1,ch2_q1,ch3_q1 : unsigned(2 downto 0) := (others=>'0');
  -- salida cruda de la LUT (etapa 3)
  signal lut_word : std_logic_vector(N_LANES*64-1 downto 0);
  -- frame_pulse alineado con el pipeline
  signal fp_e0, fp_e1, fp_e2, fp_e3 : std_logic := '0';

  -- extrae el estado en la posicion ii (0..7) de una palabra de secuencia,
  -- con el convenio del software: ii=0 en los bits [23:21], ii=7 en [2:0]
  function get_state(w : std_logic_vector(31 downto 0); ii : integer)
    return unsigned is
  begin
    return unsigned(w(3*(7-ii)+2 downto 3*(7-ii)));
  end function;

  -- invierte el orden de los 16 bits de un simbolo (SwitchMSB)
  function rev16(v : std_logic_vector(15 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0);
  begin
    for i in 0 to 15 loop r(i) := v(15-i); end loop; -- bit i <- bit 15-i
    return r;
  end function;
begin
  ----------------------------------------------------------------------------
  -- Escritura de la secuencia (dominio host)
  ----------------------------------------------------------------------------
  process(clk_host) begin
    if rising_edge(clk_host) then
      if seq_we = '1' then
        seq_ram(to_integer(seq_addr)) <= seq_data;   -- una palabra por acceso
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Pipeline de transmision (dominio tx)
  ----------------------------------------------------------------------------
  process(clk_tx) begin
    if rising_edge(clk_tx) then
      if clear = '1' then
        sym_cnt <= (others => '0');                  -- reinicio del origen
      elsif enable = '1' then
        sym_cnt <= sym_cnt + 4;                      -- 4 simbolos por ciclo
      end if;

      -- e0 -> e1: lectura de la palabra que contiene sym_cnt..sym_cnt+3.
      -- Como sym_cnt es multiplo de 4, los 4 simbolos caen en la MISMA mitad
      -- de una palabra de 8 estados: palabra = sym_cnt/8, mitad = bit 2.
      seq_word_q <= seq_ram(to_integer(sym_cnt(7 downto 3)));
      half_q     <= sym_cnt(2);

      -- chooser retrasado para llegar a e2 a la vez que la secuencia
      ch0_q1 <= ch0; ch1_q1 <= ch1; ch2_q1 <= ch2; ch3_q1 <= ch3;

      -- e1 -> e2: extraccion de los 4 estados y mux de fuente
      if use_fixed = '1' then
        if half_q = '0' then                         -- primera mitad: ii=0..3
          st0_q <= get_state(seq_word_q, 0);
          st1_q <= get_state(seq_word_q, 1);
          st2_q <= get_state(seq_word_q, 2);
          st3_q <= get_state(seq_word_q, 3);
        else                                         -- segunda mitad: ii=4..7
          st0_q <= get_state(seq_word_q, 4);
          st1_q <= get_state(seq_word_q, 5);
          st2_q <= get_state(seq_word_q, 6);
          st3_q <= get_state(seq_word_q, 7);
        end if;
      else                                           -- fuente sorteada
        st0_q <= ch0_q1; st1_q <= ch1_q1;
        st2_q <= ch2_q1; st3_q <= ch3_q1;
      end if;

      -- e4: postproceso por linea y por simbolo: SwitchMSB + inversion
      for L in 0 to N_LANES-1 loop
        for s in 0 to 3 loop
          if msb_first = '1' then                    -- invierte el tiempo
            lane_word(L*64+16*s+15 downto L*64+16*s) <=
              (rev16(lut_word(L*64+16*s+15 downto L*64+16*s))
               xor (15 downto 0 => inv(L)));         -- y aplica polaridad
          else
            lane_word(L*64+16*s+15 downto L*64+16*s) <=
              (lut_word(L*64+16*s+15 downto L*64+16*s)
               xor (15 downto 0 => inv(L)));         -- solo polaridad
          end if;
        end loop;
      end loop;

      -- frame_pulse: sym_cnt pasa por 252 en e0 -> retrasar hasta e4
      if sym_cnt = to_unsigned(252, 8) and enable = '1' then
        fp_e0 <= '1';
      else
        fp_e0 <= '0';
      end if;
      fp_e1 <= fp_e0; fp_e2 <= fp_e1; fp_e3 <= fp_e2;
      frame_pulse <= fp_e3;                          -- alineado con lane_word
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- La LUT de formas de onda (e2 -> e3: su lectura esta registrada dentro)
  ----------------------------------------------------------------------------
  u_lut : entity work.waveform_lut
    generic map ( N_LANES => N_LANES )
    port map (
      wclk   => clk_host,  we  => wave_we,
      wstate => wave_addr, wdata => wave_data,
      rclk   => clk_tx,
      st0 => st0_q, st1 => st1_q, st2 => st2_q, st3 => st3_q,
      lane_word => lut_word
    );

  sym_cnt_out <= sym_cnt;                            -- expone el contador
end architecture;
