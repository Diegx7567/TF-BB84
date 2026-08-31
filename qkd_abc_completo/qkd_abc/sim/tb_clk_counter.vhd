-- tb_clk_counter: clk_host de 10 ns y clk_meas de 4 ns; con ventana de 500
-- ciclos host (5000 ns) se esperan ~1250 ciclos medidos (tolerancia ±3 por la
-- sincronizacion Gray). Comprueba dos ventanas consecutivas y el rearme.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_clk_counter is end entity;
architecture sim of tb_clk_counter is
  signal clk_host, clk_meas : std_logic := '0';
  signal latch_stb, clear_stb : std_logic := '0';
  signal count_win : std_logic_vector(31 downto 0);
begin
  clk_host <= not clk_host after 5 ns;                -- 100 MHz
  clk_meas <= not clk_meas after 2 ns;                -- 250 MHz
  dut : entity work.clk_counter generic map (G_WIN_CYCLES => 500)
        port map (clk_meas=>clk_meas, clk_host=>clk_host,
                  latch_stb=>latch_stb, clear_stb=>clear_stb,
                  count_win=>count_win);
  process
    variable c1, c2 : integer;
    variable ok : boolean := true;
  begin
    -- rearme inicial (replica del write(2,1)... del software)
    wait for 50 ns;
    wait until rising_edge(clk_host); latch_stb<='1';
    wait until rising_edge(clk_host); latch_stb<='0';
    -- espera dos ventanas completas y lee tras cada una
    wait for 5100 ns;                                 -- > 1 ventana
    c1 := to_integer(unsigned(count_win));
    wait for 5000 ns;                                 -- otra ventana
    c2 := to_integer(unsigned(count_win));
    -- esperado: 500 ciclos host * (10ns/4ns) = 1250 medidos
    if abs(c1-1250) > 3 then ok := false;
      report "ventana1="&integer'image(c1) severity error; end if;
    if abs(c2-1250) > 3 then ok := false;
      report "ventana2="&integer'image(c2) severity error; end if;
    if ok then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
