-- tb_prbs_gen: genera 200 palabras de 64 bits y las compara bit a bit contra
-- un modelo del mismo LFSR ejecutado en el propio testbench.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_prbs_gen is end entity;
architecture sim of tb_prbs_gen is
  signal clk    : std_logic := '0';
  signal clear  : std_logic := '1';
  signal enable : std_logic := '0';
  signal dout   : std_logic_vector(63 downto 0);
begin
  clk <= not clk after 5 ns;                          -- reloj de 100 MHz
  dut : entity work.prbs_gen generic map (NBITS => 64)
        port map (clk=>clk, clear=>clear, enable=>enable, dout=>dout);
  process
    variable v : std_logic_vector(30 downto 0) := (others=>'1'); -- modelo LFSR
    variable b : std_logic;
    variable exp : std_logic_vector(63 downto 0);
    variable fails : integer := 0;
  begin
    wait until rising_edge(clk);
    clear <= '0'; enable <= '1';                      -- arranca el DUT
    for w in 0 to 199 loop                            -- 200 palabras
      -- el modelo genera la palabra esperada ANTES de mirar la salida
      for i in 0 to 63 loop
        b := v(30) xor v(27);                         -- misma realimentacion
        v := v(29 downto 0) & b;
        exp(i) := b;
      end loop;
      wait until rising_edge(clk);                    -- el DUT registra
      wait for 1 ns;                                  -- deja asentar la senal
      if dout /= exp then
        report "FALLO palabra "&integer'image(w) severity error;
        fails := fails + 1;
      end if;
    end loop;
    if fails=0 then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
