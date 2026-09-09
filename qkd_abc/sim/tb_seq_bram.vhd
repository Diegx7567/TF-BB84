--------------------------------------------------------------------------------
-- tb_seq_bram.vhd
--------------------------------------------------------------------------------
-- Comprueba que seq_bram devuelve, para cada simbolo 0..255, el mismo estado
-- que se empaqueto siguiendo la convencion del software
-- (write_fixed_sequence_with_qubit_mapping):
--     value[palabra] = sum_ii  state[palabra*8+ii] << (3*(7-ii))
--
-- Genera una secuencia de referencia pseudoaleatoria de 256 estados (0..5),
-- la empaqueta y la escribe, luego lee los 256 simbolos y verifica.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_seq_bram is end entity;

architecture sim of tb_seq_bram is
  signal clk   : std_logic := '0';
  signal we    : std_logic := '0';
  signal waddr : unsigned(4 downto 0) := (others=>'0');
  signal wdata : std_logic_vector(31 downto 0) := (others=>'0');
  signal sym   : unsigned(7 downto 0) := (others=>'0');
  signal state : std_logic_vector(2 downto 0);

  type seq_t is array (0 to 255) of integer range 0 to 7;
  signal ref : seq_t;

  signal fails : integer := 0;
begin
  clk <= not clk after 5 ns;

  dut : entity work.seq_bram
    port map (clk_wr=>clk, we=>we, waddr=>waddr, wdata=>wdata,
              clk_rd=>clk, sym=>sym, state=>state);

  process
    variable lfsr : unsigned(15 downto 0) := x"1234";
    variable st   : integer;
    variable word : unsigned(31 downto 0);
    variable rd   : integer;
  begin
    -- genera secuencia de referencia (estados 0..5)
    for i in 0 to 255 loop
      lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      ref(i) <= to_integer(lfsr(7 downto 0)) mod 6;
    end loop;
    wait until rising_edge(clk);

    -- empaqueta y escribe 32 palabras
    for w in 0 to 31 loop
      word := (others=>'0');
      for ii in 0 to 7 loop
        st := ref(w*8 + ii);
        word := word or shift_left(to_unsigned(st,32), 3*(7-ii));
      end loop;
      waddr <= to_unsigned(w,5);
      wdata <= std_logic_vector(word);
      we    <= '1';
      wait until rising_edge(clk);
    end loop;
    we <= '0';
    wait until rising_edge(clk);

    -- lee los 256 simbolos y compara (latencia de lectura = 2 ciclos)
    for s in 0 to 255 loop
      sym <= to_unsigned(s,8);
      wait until rising_edge(clk);
      wait until rising_edge(clk);            -- espera la latencia
      wait until rising_edge(clk);
      rd := to_integer(unsigned(state));
      if rd /= ref(s) then
        report "FALLO simbolo "&integer'image(s)&" got="&integer'image(rd)&
               " exp="&integer'image(ref(s)) severity error;
        fails <= fails + 1;
      end if;
    end loop;

    if fails = 0 then
      report "==================  TEST PASSED  ==================" severity note;
    else
      report "==================  TEST FAILED  ==================" severity failure;
    end if;
    wait;
  end process;
end architecture;
