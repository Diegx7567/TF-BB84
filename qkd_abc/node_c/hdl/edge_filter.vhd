--------------------------------------------------------------------------------
-- edge_filter.vhd
--------------------------------------------------------------------------------
-- QUE ES:      filtro de flanco de subida sobre el flujo de muestras: de un
--              pulso de varias muestras sobrevive SOLO la muestra del flanco.
-- PARA QUE:    un pulso del detector dura varias muestras (200 ps = 4 muestras
--              a 20 GS/s); sin filtro contarias 4 detecciones donde hay 1.
--              Es el registro FilterByEdgexS del sistema original.
-- COMO SE USA: enable=1 filtra, enable=0 deja pasar tal cual (util para ver
--              la anchura real del pulso en el histograma).
-- CONECTADO A: entre el word_bit_delay (deskew) y el binner, uno por canal de
--              deteccion. El bit de acarreo cubre los pulsos que cruzan la
--              frontera entre palabras de 64 muestras.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity edge_filter is
  generic ( W : natural := 64 );                     -- muestras por palabra
  port (
    clk    : in  std_logic;                          -- dominio rx (312,5 MHz)
    enable : in  std_logic;                          -- FilterByEdgexS
    din    : in  std_logic_vector(W-1 downto 0);     -- muestras crudas
    dout   : out std_logic_vector(W-1 downto 0)      -- solo flancos (o copia)
  );
end entity;

architecture rtl of edge_filter is
  signal carry : std_logic := '0';                   -- ultima muestra de la
begin                                                -- palabra anterior
  process(clk)
    variable prev : std_logic_vector(W-1 downto 0);  -- muestra k-1 de cada k
  begin
    if rising_edge(clk) then
      -- prev(k) = muestra anterior a la k: para k=0 es el acarreo
      prev  := din(W-2 downto 0) & carry;
      carry <= din(W-1);                             -- guarda para la proxima
      if enable = '1' then
        dout <= din and not prev;                    -- 1 solo donde hay 0->1
      else
        dout <= din;                                 -- transparente
      end if;
    end if;
  end process;
end architecture;
