--------------------------------------------------------------------------------
-- seq_bram.vhd
--------------------------------------------------------------------------------
-- BRAM de la secuencia de estados.
--
-- El PC escribe 32 palabras de 32 bits (indices 400..431) mediante el reg_file.
-- Cada palabra empaqueta 8 estados de 3 bits (8*3 = 24 bits usados de 32),
-- exactamente como write_fixed_sequence_with_qubit_mapping del software:
--
--   value = sum_{ii=0..7}  (state[i*8+ii] & 0b111) << (3 * (7 - ii))
--
-- Es decir: el primer estado del grupo va en los bits [23:21], el segundo en
-- [20:18], ..., el octavo en [2:0].
--
-- Lado de lectura (dominio de transmision en Alice, o de recepcion en Bob):
-- se pide el numero de simbolo (0..255) y se devuelve su estado de 3 bits.
-- Internamente: palabra = symbol / 8, posicion = symbol mod 8.
--
-- Uso:
--   * Alice: fuente de estados para la secuencia fija.
--   * Bob:   copia local contra la que compara la matriz de coincidencias.
--
-- La escritura (puerto A) va en clk_wr (dominio host); la lectura (puerto B) en
-- clk_rd (dominio tx/rx). La BRAM de doble puerto resuelve el cruce de dominios
-- para el dato; el software solo recarga la secuencia en estados != RUN, cuando
-- no hay lectura critica en curso.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seq_bram is
  port (
    -- puerto A: escritura desde el reg_file (dominio host)
    clk_wr  : in  std_logic;
    we      : in  std_logic;
    waddr   : in  unsigned(4 downto 0);              -- 0..31 (indice - 400)
    wdata   : in  std_logic_vector(31 downto 0);

    -- puerto B: lectura por numero de simbolo (dominio tx/rx)
    clk_rd  : in  std_logic;
    sym     : in  unsigned(7 downto 0);              -- 0..255
    state   : out std_logic_vector(2 downto 0)       -- estado del simbolo
  );
end entity;

architecture rtl of seq_bram is
  type ram_t is array (0 to 31) of std_logic_vector(31 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  signal rword : std_logic_vector(31 downto 0);
  signal rpos  : unsigned(2 downto 0);
begin

  ----------------------------------------------------------------------------
  -- Escritura (puerto A)
  ----------------------------------------------------------------------------
  process(clk_wr) begin
    if rising_edge(clk_wr) then
      if we = '1' then
        ram(to_integer(waddr)) <= wdata;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Lectura (puerto B): registra la palabra y la posicion, luego extrae
  -- los 3 bits del estado. El estado ii ocupa los bits [3*(7-ii)+2 : 3*(7-ii)].
  ----------------------------------------------------------------------------
  process(clk_rd)
    variable pos : integer range 0 to 7;
    variable lo  : integer range 0 to 21;
  begin
    if rising_edge(clk_rd) then
      -- etapa 1: lee la palabra que contiene el simbolo y guarda su posicion
      rword <= ram(to_integer(sym(7 downto 3)));      -- sym / 8
      rpos  <= sym(2 downto 0);                        -- sym mod 8

      -- etapa 2: extrae los 3 bits segun la posicion
      pos := to_integer(rpos);
      lo  := 3 * (7 - pos);
      state <= rword(lo + 2 downto lo);
    end if;
  end process;

end architecture;
