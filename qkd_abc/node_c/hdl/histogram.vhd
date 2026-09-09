--------------------------------------------------------------------------------
-- histogram.vhd
--------------------------------------------------------------------------------
-- QUE ES:      histograma temporal de 64 bins = 8 simbolos de trama x 8 bins
--              de 100 ps, con doble banco (acumulador vivo + copia estable).
-- PARA QUE:    es el observable principal de C (donde cae el foton dentro del
--              ojo) y lo que dibuja la GUI; de la asimetria de sus bins sale
--              la senal de error del lazo de retardo (Arduino). La ventana de
--              8 simbolos (6,4 ns = periodo de 156,25 MHz) permite ver la
--              estructura del patron, no solo la forma del pulso.
-- COMO SE USA: bins_in llega del binner (32 bits = 4 simbolos x 8 bins por
--              ciclo); phase_clr ancla el origen de la trama (lo pulsa la FSM
--              de arranque al sincronizar). rd_addr/rd_data exponen la copia
--              estable; en el top se cablean a los indices 300..363 (Z) o
--              200..263 (X) EN ORDEN INVERTIDO (363-i), como lee Python.
-- CONECTADO A: binner -> aqui -> reg_file (estado). Una instancia por canal.
-- DETALLE:     la fase avanza 4 mod 8 por ciclo, asi que los 4 simbolos de una
--              palabra caen en posiciones de trama DISTINTAS: cada acumulador
--              recibe como mucho 1 incremento por ciclo (sin arbol de suma).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity histogram is
  generic (
    G_WIN_CYCLES : natural := 6_250_000     -- ciclos por ventana (20 ms a
  );                                         -- 312,5 MHz; en TB, pocos)
  port (
    clk       : in  std_logic;               -- dominio rx
    bins_in   : in  std_logic_vector(31 downto 0); -- 4 simbolos x 8 bins
    phase_clr : in  std_logic;                -- ancla el origen de trama
    rd_addr   : in  unsigned(5 downto 0);     -- bin 0..63 (banco estable)
    rd_data   : out std_logic_vector(31 downto 0)  -- cuentas de ese bin
  );
end entity;

architecture rtl of histogram is
  type acc_t is array (0 to 63) of unsigned(31 downto 0);
  signal acc   : acc_t := (others => (others => '0'));  -- acumulador vivo
  signal snap  : acc_t := (others => (others => '0'));  -- copia estable
  signal phase : unsigned(2 downto 0) := (others => '0'); -- simbolo de trama 0..7
  signal wcnt  : natural range 0 to G_WIN_CYCLES-1 := 0;  -- reloj de ventana
begin
  process(clk)
    variable pos : integer range 0 to 7;      -- posicion de trama del simbolo
  begin
    if rising_edge(clk) then
      -- acumulacion: 4 simbolos por ciclo, cada uno en su posicion de trama
      for s in 0 to 3 loop
        pos := to_integer(phase + s) mod 8;   -- (phase+s) mod 8
        for b in 0 to 7 loop
          if bins_in(s*8 + b) = '1' then      -- hubo clic en ese bin:
            acc(pos*8 + b) <= acc(pos*8 + b) + 1;  -- incrementa su contador
          end if;
        end loop;
      end loop;

      if phase_clr = '1' then
        phase <= (others => '0');             -- reancla el origen de trama
      else
        phase <= phase + 4;                   -- 4 simbolos consumidos (mod 8)
      end if;

      -- doble banco: al vencer la ventana, copia y limpia
      if wcnt = G_WIN_CYCLES-1 then
        wcnt <= 0;
        snap <= acc;                          -- copia atomica al banco estable
        acc  <= (others => (others => '0'));  -- reinicia el vivo
      else
        wcnt <= wcnt + 1;
      end if;

      rd_data <= std_logic_vector(snap(to_integer(rd_addr)));  -- lectura reg.
    end if;
  end process;
end architecture;
