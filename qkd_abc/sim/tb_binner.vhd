library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_binner is end entity;

architecture sim of tb_binner is
  constant W : natural := 64;
  signal clk  : std_logic := '0';
  signal din  : std_logic_vector(W-1 downto 0) := (others=>'0');
  signal bins : std_logic_vector(31 downto 0);
begin
  clk <= not clk after 5 ns;

  dut : entity work.binner
    generic map (W=>64, SAMPLES_PER_BIN=>2, BINS_PER_SYMBOL=>8)
    port map (clk=>clk, din=>din, bins=>bins);

  process
    variable lfsr : unsigned(63 downto 0) := x"0123456789ABCDEF";
    variable dv   : std_logic_vector(W-1 downto 0);
    variable exp_now, exp_prev : std_logic_vector(31 downto 0) := (others=>'0');
    variable have_prev : boolean := false;
    variable fails : integer := 0;

    function model(d : std_logic_vector(W-1 downto 0)) return std_logic_vector is
      variable r : std_logic_vector(31 downto 0);
    begin
      for s in 0 to 3 loop
        for b in 0 to 7 loop
          r(s*8+b) := d(16*s + 2*b) or d(16*s + 2*b + 1);
        end loop;
      end loop;
      return r;
    end function;
  begin
    wait until rising_edge(clk);
    for t in 0 to 499 loop
      for i in 0 to W-1 loop
        lfsr := lfsr(62 downto 0) & (lfsr(63) xor lfsr(62) xor lfsr(60) xor lfsr(59));
        dv(i) := lfsr(0);
      end loop;
      din <= dv;
      exp_now := model(dv);

      wait until rising_edge(clk);

      if have_prev then
        if bins /= exp_prev then
          report "FALLO t="&integer'image(t) severity error;
          fails := fails + 1;
        end if;
      end if;
      exp_prev  := exp_now;
      have_prev := true;
    end loop;

    if fails = 0 then
      report "==================  TEST PASSED  ==================" severity note;
    else
      report "==================  TEST FAILED  ==================" severity failure;
    end if;
    wait;
  end process;
end architecture;
