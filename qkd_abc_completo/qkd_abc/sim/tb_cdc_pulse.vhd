-- tb_cdc_pulse: envia 50 pulsos desde un dominio de 100 MHz a otro de 77 MHz
-- (relojes inconmensurables) y comprueba que llegan exactamente 50.
library ieee;
use ieee.std_logic_1164.all;

entity tb_cdc_pulse is end entity;
architecture sim of tb_cdc_pulse is
  signal src_clk, dst_clk : std_logic := '0';
  signal src_pulse, dst_pulse : std_logic := '0';
  signal rx_count : integer := 0;                     -- pulsos recibidos
begin
  src_clk <= not src_clk after 5 ns;                  -- 100 MHz
  dst_clk <= not dst_clk after 6500 ps;               -- ~77 MHz (asincrono)
  dut : entity work.cdc_pulse
        port map (src_clk=>src_clk, src_pulse=>src_pulse,
                  dst_clk=>dst_clk, dst_pulse=>dst_pulse);
  -- contador de pulsos en el destino
  process(dst_clk) begin
    if rising_edge(dst_clk) then
      if dst_pulse='1' then rx_count <= rx_count + 1; end if;
    end if;
  end process;
  -- emisor: 50 pulsos separados lo bastante para que cada toggle cruce
  process begin
    wait for 100 ns;
    for i in 1 to 50 loop
      wait until rising_edge(src_clk);
      src_pulse <= '1';                               -- pulso de 1 ciclo
      wait until rising_edge(src_clk);
      src_pulse <= '0';
      wait for 100 ns;                                -- separacion > 3 ciclos dst
    end loop;
    wait for 300 ns;                                  -- deja llegar el ultimo
    if rx_count = 50 then report "TEST PASSED" severity note;
    else report "TEST FAILED: rx="&integer'image(rx_count) severity failure;
    end if;
    wait;
  end process;
end architecture;
