-- tb_ab_top_smoke: prueba de humo del top de A/B: carga secuencia y LUT por la
-- interfaz host REAL (indices 400.. y 500..), habilita por el registro 6, y
-- comprueba que (1) gty_txdata produce el patron esperado del estado leido y
-- (2) frame_pulse late cada 64 ciclos (256 simbolos).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ab_top_smoke is end entity;
architecture sim of tb_ab_top_smoke is
  signal clk_host, clk_tx : std_logic := '0';
  signal rst : std_logic := '1';
  signal wr_en, rd_en : std_logic := '0';
  signal wr_addr, rd_addr : unsigned(11 downto 0) := (others=>'0');
  signal wr_data : std_logic_vector(31 downto 0) := (others=>'0');
  signal rd_data : std_logic_vector(31 downto 0);
  signal rd_valid : std_logic;
  signal gty_txdata : std_logic_vector(5*64-1 downto 0);
  signal frame_pulse : std_logic;
  signal sym_cnt : unsigned(7 downto 0);
  procedure wr(signal clk : in std_logic; signal en : out std_logic;
               signal a : out unsigned(11 downto 0);
               signal d : out std_logic_vector(31 downto 0);
               addr : natural; val : std_logic_vector(31 downto 0)) is
  begin
    wait until rising_edge(clk);
    a <= to_unsigned(addr,12); d <= val; en <= '1';
    wait until rising_edge(clk);
    en <= '0';
  end procedure;
begin
  clk_host <= not clk_host after 4 ns;
  clk_tx   <= not clk_tx after 1600 ps;
  dut : entity work.ab_top
    port map (clk_host=>clk_host, rst=>rst, wr_en=>wr_en, wr_addr=>wr_addr,
              wr_data=>wr_data, rd_en=>rd_en, rd_addr=>rd_addr,
              rd_data=>rd_data, rd_valid=>rd_valid, clk_tx=>clk_tx,
              gty_txdata=>gty_txdata, frame_pulse=>frame_pulse,
              sym_cnt=>sym_cnt);
  process
    variable t_prev : time;
    variable fails : integer := 0;
    variable seen : integer := 0;
  begin
    wait for 40 ns; rst <= '0'; wait for 40 ns;
    -- secuencia: todo estado 5 (cada palabra = 8 estados '101' empaquetados)
    for w in 0 to 31 loop
      wr(clk_host, wr_en, wr_addr, wr_data, 400+w, x"00B6DB6D");
      -- 0x00B6DB6D = "101" x8 en [23:0] (101101101101101101101101)
    end loop;
    -- LUT: estado 5, lineas 0..4 con patron 0xA001 (no palindromo)
    for ln in 0 to 4 loop
      wr(clk_host, wr_en, wr_addr, wr_data, 505,
         std_logic_vector(to_unsigned(ln,16)) & x"A001"
         );
    end loop;
    -- OJO al formato: wdata[18:16]=linea, [15:0]=patron; el to_unsigned(ln,16)
    -- de arriba pone la linea en [31:16], cuyos bits [18:16] son ln si ln<8.
    -- registro 6: enable=1, use_fixed=1 -> 0x...0003
    wr(clk_host, wr_en, wr_addr, wr_data, 6, x"00000003");
    -- espera y comprueba: todas las lineas deben sacar 4x 0xA001
    wait for 1 us;
    for k in 0 to 9 loop
      wait until rising_edge(clk_tx);
      wait for 100 ps;
      for L in 0 to 4 loop
        for s in 0 to 3 loop
          if gty_txdata(L*64+16*s+15 downto L*64+16*s) /= x"A001" then
            fails := fails + 1;
          end if;
        end loop;
      end loop;
    end loop;
    if fails /= 0 then
      report "datos incorrectos: "&integer'image(fails) severity error;
      report "TEST FAILED" severity failure;
    end if;
    -- frame_pulse cada 64 ciclos de clk_tx (256 simbolos / 4 por ciclo)
    wait until frame_pulse = '1';
    t_prev := now;
    wait until frame_pulse = '0';
    wait until frame_pulse = '1';
    if (now - t_prev) /= 64 * 3200 ps then
      report "periodo de trama incorrecto" severity error;
      report "TEST FAILED" severity failure;
    end if;
    report "TEST PASSED" severity note;
    wait;
  end process;
end architecture;
