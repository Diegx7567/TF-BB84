--------------------------------------------------------------------------------
-- binner.vhd
--------------------------------------------------------------------------------
-- Convierte una palabra de W muestras de 50 ps en bins de 100 ps.
--
-- A 20 GS/s con W=64:  64 muestras = 4 simbolos de 16 muestras = 4*8 bins.
-- Cada bin de 100 ps es el OR de SAMPLES_PER_BIN muestras consecutivas
-- (2 a 20 GS/s, 3 a 30 GS/s).
--
-- Parametrizado para soportar 20 o 30 GS/s sin cambiar el codigo:
--   SAMPLES_PER_BIN     = muestras por bin (2 o 3)
--   BINS_PER_SYMBOL     = 8 (fijo: 800 ps / 100 ps)
--   SYMS_PER_WORD       = W / (SAMPLES_PER_BIN*BINS_PER_SYMBOL)
--
-- Entrada:  din(W-1..0), din(0) = muestra mas antigua, ya alineada por el deskew.
-- Salida:   bins, SYMS_PER_WORD * BINS_PER_SYMBOL bits, un bit por bin.
--           bins(s*8 + b) = bin b del simbolo s de esta palabra.
--
-- Sin logica de acarreo entre palabras: como W es multiplo de
-- SAMPLES_PER_BIN*BINS_PER_SYMBOL, cada palabra contiene simbolos completos.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity binner is
  generic (
    W               : natural := 64;
    SAMPLES_PER_BIN : natural := 2;      -- 2 a 20 GS/s, 3 a 30 GS/s
    BINS_PER_SYMBOL : natural := 8
  );
  port (
    clk  : in  std_logic;
    din  : in  std_logic_vector(W-1 downto 0);
    -- ancho = SYMS_PER_WORD * BINS_PER_SYMBOL = W / SAMPLES_PER_BIN.
    -- Para W=64, SAMPLES_PER_BIN=2 -> 32 bits (4 simbolos x 8 bins).
    bins : out std_logic_vector(W/SAMPLES_PER_BIN - 1 downto 0)
  );
end entity;

--------------------------------------------------------------------------------
-- Nota sobre el ancho de 'bins': para mantener el ejemplo concreto y evitar
-- expresiones genericas ilegibles en el puerto, fijamos el caso W=64,
-- SAMPLES_PER_BIN=2, BINS_PER_SYMBOL=8 -> 4 simbolos * 8 bins = 32 bits.
-- Si cambias los genericos, ajusta el ancho del puerto en consecuencia (o usa
-- un paquete con una constante; aqui lo dejamos explicito para el TB).
--------------------------------------------------------------------------------

architecture rtl of binner is
  constant SYMS_PER_WORD : natural := W / (SAMPLES_PER_BIN*BINS_PER_SYMBOL);
  constant N_BINS        : natural := SYMS_PER_WORD * BINS_PER_SYMBOL;
begin

  process(clk)
    variable acc : std_logic;
    variable base : integer;
  begin
    if rising_edge(clk) then
      for s in 0 to SYMS_PER_WORD-1 loop
        for b in 0 to BINS_PER_SYMBOL-1 loop
          -- primera muestra de este bin dentro de la palabra
          base := s*(SAMPLES_PER_BIN*BINS_PER_SYMBOL) + b*SAMPLES_PER_BIN;
          acc := '0';
          for k in 0 to SAMPLES_PER_BIN-1 loop
            acc := acc or din(base + k);
          end loop;
          bins(s*BINS_PER_SYMBOL + b) <= acc;
        end loop;
      end loop;
    end if;
  end process;

end architecture;
