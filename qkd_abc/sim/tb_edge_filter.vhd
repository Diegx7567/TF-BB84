-- tb_edge_filter: alimenta un flujo con pulsos de anchura 1..8 en fases
-- aleatorias (incluidas fronteras de palabra) y comprueba contra un modelo con
-- acarreo que la salida marca exactamente las muestras de flanco 0->1.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_edge_filter is end entity;
architecture sim of tb_edge_filter is
  constant W : natural := 64;
  signal clk : std_logic := '0';
  signal enable : std_logic := '1';
  signal din : std_logic_vector(W-1 downto 0) := (others=>'0');
  signal dout : std_logic_vector(W-1 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.edge_filter generic map (W=>W)
        port map (clk=>clk, enable=>enable, din=>din, dout=>dout);
  process
    variable lfsr : unsigned(31 downto 0) := x"DEAD10CC";
    variable dv, dprev_bit_model : std_logic_vector(W-1 downto 0);
    variable carry_model : std_logic := '0';        -- modelo del acarreo
    variable exp_now, exp_prev : std_logic_vector(W-1 downto 0) := (others=>'0');
    variable have_prev : boolean := false;
    variable fails : integer := 0;
    variable run : integer := 0;                    -- longitud de pulso restante
  begin
    wait until rising_edge(clk);
    for t in 0 to 399 loop
      -- genera una palabra con pulsos de anchura variable
      for i in 0 to W-1 loop
        if run > 0 then
          dv(i) := '1'; run := run - 1;             -- continua el pulso
        else
          lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
          if lfsr(3 downto 0) = x"7" then           -- prob ~1/16 de empezar
            run := to_integer(lfsr(6 downto 4)) + 1;-- anchura 1..8
            dv(i) := '1'; run := run - 1;
          else
            dv(i) := '0';
          end if;
        end if;
      end loop;
      -- modelo: flanco = din AND NOT muestra_anterior (con acarreo)
      for i in 0 to W-1 loop
        if i = 0 then dprev_bit_model(0) := carry_model;
        else dprev_bit_model(i) := dv(i-1); end if;
        exp_now(i) := dv(i) and not dprev_bit_model(i);
      end loop;
      carry_model := dv(W-1);                       -- acarreo para la proxima
      din <= dv;
      wait until rising_edge(clk);                  -- el DUT registra aqui
      if have_prev then
        if dout /= exp_prev then
          report "FALLO t="&integer'image(t) severity error;
          fails := fails + 1;
        end if;
      end if;
      exp_prev := exp_now; have_prev := true;
    end loop;
    if fails=0 then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
