-- tb_stats_snapshot: contadores que avanzan cada ciclo; comprueba que
-- (1) al vencer el bloque la sombra captura valores coherentes,
-- (2) la sombra NO cambia mientras data_ready=1 aunque venzan mas bloques,
-- (3) tras ack_stb llega un bloque nuevo con valores mayores.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qkd_pkg.all;

entity tb_stats_snapshot is end entity;
architecture sim of tb_stats_snapshot is
  signal clk : std_logic := '0';
  signal counters : reg_array_t(0 to 3) := (others=>(others=>'0'));
  signal ack_stb, data_ready : std_logic := '0';
  signal block_time : std_logic_vector(31 downto 0);
  signal shadow : reg_array_t(0 to 3);
begin
  clk <= not clk after 5 ns;
  dut : entity work.stats_snapshot generic map (N=>4, G_BLOCK_CYC=>100)
        port map (clk=>clk, counters=>counters, ack_stb=>ack_stb,
                  data_ready=>data_ready, block_time=>block_time, shadow=>shadow);
  -- contadores vivos: cnt(i) = ciclos*(i+1), coherentes entre si por definicion
  process(clk)
    variable t : integer := 0;
  begin
    if rising_edge(clk) then
      t := t + 1;
      for i in 0 to 3 loop
        counters(i) <= std_logic_vector(to_unsigned(t*(i+1), 32));
      end loop;
    end if;
  end process;
  process
    variable s0a, s0b : integer;
    variable ok : boolean := true;
  begin
    wait until data_ready = '1';                       -- primer bloque listo
    wait for 1 ns;
    s0a := to_integer(unsigned(shadow(0)));
    -- coherencia: shadow(i) debe ser (i+1)*shadow(0) exactamente
    for i in 1 to 3 loop
      if to_integer(unsigned(shadow(i))) /= (i+1)*s0a then
        ok := false; report "incoherente i="&integer'image(i) severity error;
      end if;
    end loop;
    -- congelacion: espera 3 bloques mas SIN ack; la sombra no debe moverse
    wait for 3 us;
    if to_integer(unsigned(shadow(0))) /= s0a then
      ok := false; report "la sombra cambio sin ack" severity error; end if;
    -- ack y bloque nuevo
    wait until rising_edge(clk); ack_stb<='1';
    wait until rising_edge(clk); ack_stb<='0';
    wait until data_ready = '1';
    wait for 1 ns;
    s0b := to_integer(unsigned(shadow(0)));
    if s0b <= s0a then ok := false;
      report "el bloque nuevo no avanzo" severity error; end if;
    if ok then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
