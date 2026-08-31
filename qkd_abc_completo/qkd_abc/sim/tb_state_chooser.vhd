-- tb_state_chooser: alimenta el chooser con el prbs_gen real y replica el
-- sorteo en un modelo con el MISMO LFSR: la comparacion es exacta, no
-- estadistica. Umbrales del sistema original: 100/201/100.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_state_chooser is end entity;
architecture sim of tb_state_chooser is
  signal clk : std_logic := '0';
  signal clear, enable : std_logic := '0';
  signal rnd : std_logic_vector(63 downto 0);
  signal st0,st1,st2,st3 : unsigned(2 downto 0);
begin
  clk <= not clk after 5 ns;
  u_prbs : entity work.prbs_gen generic map (NBITS=>64)
           port map (clk=>clk, clear=>clear, enable=>enable, dout=>rnd);
  dut : entity work.state_chooser
        port map (clk=>clk, enable=>enable,
                  prob_z0_up=>to_unsigned(100,8),
                  prob_z1_up=>to_unsigned(201,8),
                  prob_dec0_up=>to_unsigned(100,8),
                  rnd=>rnd, st0=>st0, st1=>st1, st2=>st2, st3=>st3);
  process
    variable v : std_logic_vector(30 downto 0) := (others=>'1'); -- modelo LFSR
    variable b : std_logic;
    variable w : std_logic_vector(63 downto 0);      -- palabra rnd del modelo
    variable rb, rd : integer;                       -- bytes base/decoy
    variable base, dec, exp : integer;
    variable got : integer;
    variable fails : integer := 0;
  begin
    wait until rising_edge(clk);
    clear <= '1'; wait until rising_edge(clk); clear <= '0';
    enable <= '1';
    -- cebado del pipeline: tras 2 flancos, st* refleja la 1a palabra w1;
    -- a partir de ahi, cada flanco adicional avanza UNA palabra, asi que el
    -- bucle hace un solo wait por iteracion (modelo y DUT en paso cerrado)
    wait until rising_edge(clk);                     -- dout <= w1
    for t in 0 to 499 loop
      -- el modelo genera la palabra w_(t+1), la que el chooser registrara
      -- en el siguiente flanco
      for i in 0 to 63 loop
        b := v(30) xor v(27);
        v := v(29 downto 0) & b;
        w(i) := b;
      end loop;
      wait until rising_edge(clk);                   -- st* <= f(w_(t+1))
      wait for 1 ns;
      for k in 0 to 3 loop
        rb := to_integer(unsigned(w(16*k+7  downto 16*k)));
        rd := to_integer(unsigned(w(16*k+15 downto 16*k+8)));
        if    rb < 100 then base := 0;
        elsif rb < 201 then base := 1;
        else                base := 2; end if;
        if rd < 100 then dec := 0; else dec := 1; end if;
        exp := base + 3*dec;
        case k is
          when 0 => got := to_integer(st0);
          when 1 => got := to_integer(st1);
          when 2 => got := to_integer(st2);
          when 3 => got := to_integer(st3);
        end case;
        if got /= exp then
          report "FALLO t="&integer'image(t)&" k="&integer'image(k)
            severity error;
          fails := fails + 1;
        end if;
      end loop;
    end loop;
    if fails=0 then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
