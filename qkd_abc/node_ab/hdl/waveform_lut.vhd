--------------------------------------------------------------------------------
-- waveform_lut.vhd
--------------------------------------------------------------------------------
-- QUE ES:      la tabla que convierte cada estado (3 bits, 0..5) en su forma
--              de onda de 16 muestras de 50 ps, para cada una de las N_LANES
--              lineas fisicas (laser + D0..D2 del DAC + reloj del DAC).
-- PARA QUE:    toda la "personalidad" del transmisor (z0 = pulso temprano,
--              z1 = tardio, x0 = ambos; niveles de decoy del DAC) es CONTENIDO
--              de esta tabla, no logica: cambiar un pulso es escribir 16 bits
--              desde Python sin resintetizar. Y como las 5 lineas salen de la
--              misma consulta en el mismo ciclo, su sincronia es por
--              construccion.
-- COMO SE USA: carga por la ventana 500..507 del reg_file: el indice (0..7) es
--              el estado, y wdata empaqueta [18:16]=linea, [15:0]=patron
--              (asi una escritura = una celda). Consulta: 4 estados por ciclo
--              -> por linea, palabra de 64 bits = 4 simbolos concatenados.
-- CONECTADO A: reg_file (wave_we/addr/data) -> aqui; state mux (tx_datapath)
--              -> direcciones; salida -> bit_order/inversion -> word_bit_delay
--              -> GTY TXDATA.
-- CONVENIO:    patron(0) = muestra mas antigua (primera en el tiempo), igual
--              que en todo el sistema.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity waveform_lut is
  generic ( N_LANES : natural := 5 );                -- laser + 3 DAC + clk DAC
  port (
    -- carga desde el host (ventana 500..507 del reg_file)
    wclk   : in  std_logic;
    we     : in  std_logic;                          -- pulso de escritura
    wstate : in  unsigned(2 downto 0);               -- estado (= indice-500)
    wdata  : in  std_logic_vector(31 downto 0);      -- [18:16]=linea [15:0]=patron
    -- consulta (dominio tx): 4 estados simultaneos
    rclk   : in  std_logic;
    st0, st1, st2, st3 : in unsigned(2 downto 0);    -- estados de los 4 simbolos
    -- salida: por linea, 64 bits = {simbolo3, simbolo2, simbolo1, simbolo0}
    lane_word : out std_logic_vector(N_LANES*64-1 downto 0)
  );
end entity;

architecture rtl of waveform_lut is
  -- tabla: 8 estados x N_LANES lineas x 16 muestras (640 bits: LUTRAM)
  type lut_t is array (0 to 7, 0 to N_LANES-1) of std_logic_vector(15 downto 0);
  signal lut : lut_t := (others => (others => (others => '0')));
begin
  -- CARGA: una celda (estado, linea) por escritura
  process(wclk)
    variable lane : integer range 0 to 7;            -- linea destino
  begin
    if rising_edge(wclk) then
      if we = '1' then
        lane := to_integer(unsigned(wdata(18 downto 16)));  -- campo de linea
        if lane < N_LANES then                       -- ignora lineas fuera de
          lut(to_integer(wstate), lane) <= wdata(15 downto 0);  -- rango
        end if;
      end if;
    end if;
  end process;

  -- CONSULTA: para cada linea, concatena los 4 patrones (simbolo 0 en los
  -- bits bajos = mas antiguo, coherente con el convenio temporal global)
  process(rclk) begin
    if rising_edge(rclk) then
      for L in 0 to N_LANES-1 loop
        lane_word(L*64 + 15 downto L*64 +  0) <= lut(to_integer(st0), L);
        lane_word(L*64 + 31 downto L*64 + 16) <= lut(to_integer(st1), L);
        lane_word(L*64 + 47 downto L*64 + 32) <= lut(to_integer(st2), L);
        lane_word(L*64 + 63 downto L*64 + 48) <= lut(to_integer(st3), L);
      end loop;
    end if;
  end process;
end architecture;
