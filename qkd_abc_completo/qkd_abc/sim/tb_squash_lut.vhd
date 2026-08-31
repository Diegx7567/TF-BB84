-- tb_squash_lut: carga la tabla con f(i) = (i*7+3) mod 1024 usando el
-- mecanismo secuencial (clear + 256 escrituras) y consulta 200 ciclos con 4
-- direcciones pseudoaleatorias por ciclo comprobando las 4 salidas.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_squash_lut is end entity;
architecture sim of tb_squash_lut is
  signal clk : std_logic := '0';
  signal we, wclear : std_logic := '0';
  signal wdata : std_logic_vector(9 downto 0) := (others=>'0');
  signal a0,a1,a2,a3 : std_logic_vector(7 downto 0) := (others=>'0');
  signal o0,o1,o2,o3 : std_logic_vector(9 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.squash_lut
        port map (wclk=>clk, we=>we, wclear=>wclear, wdata=>wdata,
                  rclk=>clk, addr0=>a0, addr1=>a1, addr2=>a2, addr3=>a3,
                  out0=>o0, out1=>o1, out2=>o2, out3=>o3);
  process
    function f(i:integer) return integer is begin return (i*7+3) mod 1024; end;
    variable lfsr : unsigned(31 downto 0) := x"0BADF00D";
    variable v0,v1,v2,v3 : integer;                  -- direcciones del ciclo
    variable p0,p1,p2,p3 : integer := 0;             -- las del ciclo anterior
    variable have_prev : boolean := false;
    variable fails : integer := 0;
  begin
    -- carga: clear del puntero + 256 filas en orden
    wait until rising_edge(clk);
    wclear <= '1'; wait until rising_edge(clk); wclear <= '0';
    for i in 0 to 255 loop
      wdata <= std_logic_vector(to_unsigned(f(i),10));
      we <= '1';
      wait until rising_edge(clk);
    end loop;
    we <= '0';
    wait until rising_edge(clk);
    -- consulta con verificacion (latencia 1: comparo con las addr previas)
    for t in 0 to 199 loop
      lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
      v0 := to_integer(lfsr(7 downto 0));
      v1 := to_integer(lfsr(15 downto 8));
      v2 := to_integer(lfsr(23 downto 16));
      v3 := to_integer(lfsr(31 downto 24));
      a0 <= std_logic_vector(to_unsigned(v0,8));
      a1 <= std_logic_vector(to_unsigned(v1,8));
      a2 <= std_logic_vector(to_unsigned(v2,8));
      a3 <= std_logic_vector(to_unsigned(v3,8));
      wait until rising_edge(clk);   -- el DUT registra out=mem(addr actual)
      wait for 1 ns;                 -- deja asentar la salida
      if to_integer(unsigned(o0)) /= f(v0) or
         to_integer(unsigned(o1)) /= f(v1) or
         to_integer(unsigned(o2)) /= f(v2) or
         to_integer(unsigned(o3)) /= f(v3) then
        report "FALLO t="&integer'image(t) severity error;
        fails := fails + 1;
      end if;
    end loop;
    if fails=0 then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
