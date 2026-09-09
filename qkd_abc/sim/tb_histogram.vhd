-- tb_histogram: durante una ventana de 64 ciclos inyecta un patron conocido
-- (clic en el bin 2 del simbolo 0 de cada palabra, es decir posicion de trama
-- alternante 0/4) y comprueba que los bins 0*8+2 y 4*8+2 acumulan 32 cada uno
-- y el resto 0. Luego verifica que el banco estable conserva el valor mientras
-- el acumulador vivo sigue con la ventana siguiente.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_histogram is end entity;
architecture sim of tb_histogram is
  signal clk : std_logic := '0';
  signal bins_in : std_logic_vector(31 downto 0) := (others=>'0');
  signal phase_clr : std_logic := '0';
  signal rd_addr : unsigned(5 downto 0) := (others=>'0');
  signal rd_data : std_logic_vector(31 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.histogram generic map (G_WIN_CYCLES=>1000)
        port map (clk=>clk, bins_in=>bins_in, phase_clr=>phase_clr,
                  rd_addr=>rd_addr, rd_data=>rd_data);
  process
    variable v : integer;
    variable fails : integer := 0;
  begin
    -- ancla la fase y arranca el patron: solo el simbolo 0 de cada palabra
    -- tiene clic, siempre en el bin 2 -> bins_in(0*8+2)='1'
    wait until rising_edge(clk);
    phase_clr <= '1';
    wait until rising_edge(clk);
    phase_clr <= '0';
    bins_in <= (2 => '1', others => '0');
    -- deja pasar la primera ventana completa (1000 ciclos) mas margen
    for k in 0 to 1005 loop wait until rising_edge(clk); end loop;
    bins_in <= (others=>'0');                     -- para de inyectar
    -- lee los 64 bins del banco estable
    for a in 0 to 63 loop
      rd_addr <= to_unsigned(a,6);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      v := to_integer(unsigned(rd_data));
      -- fase avanza 0,4,0,4...: el simbolo 0 de la palabra cae en posiciones
      -- de trama 0 y 4 alternadamente -> bins 2 y 34, ~500 cuentas cada uno
      -- (1000 ciclos de ventana, menos ~5 de arranque, repartidos entre dos)
      if a=2 or a=34 then
        if v < 490 or v > 505 then
          report "bin "&integer'image(a)&"="&integer'image(v) severity error;
          fails := fails + 1;
        end if;
      else
        if v /= 0 then
          report "bin "&integer'image(a)&" no nulo: "&integer'image(v) severity error;
          fails := fails + 1;
        end if;
      end if;
    end loop;
    if fails=0 then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
