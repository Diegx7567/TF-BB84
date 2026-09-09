-- tb_coincidence_matrix: 1000 ciclos de tuplas (valid,outcome,estado)
-- pseudoaleatorias, con colisiones deliberadas (misma celda varias veces en un
-- ciclo), contadas en paralelo por un modelo; al final se leen las 30 celdas.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_coincidence_matrix is end entity;
architecture sim of tb_coincidence_matrix is
  signal clk, clear : std_logic := '0';
  signal valid : std_logic_vector(3 downto 0) := (others=>'0');
  signal o0,o1,o2,o3, s0,s1,s2,s3 : unsigned(2 downto 0) := (others=>'0');
  signal rd_idx : unsigned(4 downto 0) := (others=>'0');
  signal rd_cnt : std_logic_vector(31 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.coincidence_matrix
        port map (clk=>clk, clear=>clear, valid=>valid,
                  out0=>o0,out1=>o1,out2=>o2,out3=>o3,
                  st0=>s0,st1=>s1,st2=>s2,st3=>s3,
                  rd_idx=>rd_idx, rd_cnt=>rd_cnt);
  process
    type m_t is array (0 to 29) of integer;
    variable model : m_t := (others=>0);             -- contadores del modelo
    variable lfsr : unsigned(31 downto 0) := x"C0FFEE11";
    variable vo, vs : integer;
    variable vv : std_logic_vector(3 downto 0);
    variable oarr, sarr : m_t;                       -- reutilizo tipo (sobra)
    variable ocyc, scyc : integer;
    variable fails : integer := 0;
    variable got : integer;
  begin
    -- clear inicial
    wait until rising_edge(clk);
    clear <= '1'; wait until rising_edge(clk); clear <= '0';
    for t in 0 to 999 loop
      -- genera 4 tuplas; outcome se limita a 0..4 y estado a 0..5
      for k in 0 to 3 loop
        lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
        vo := to_integer(lfsr(2 downto 0)) mod 5;    -- 0..4
        vs := to_integer(lfsr(5 downto 3)) mod 6;    -- 0..5
        vv(k) := lfsr(6);                            -- valid aleatorio
        case k is
          when 0 => o0<=to_unsigned(vo,3); s0<=to_unsigned(vs,3);
          when 1 => o1<=to_unsigned(vo,3); s1<=to_unsigned(vs,3);
          when 2 => o2<=to_unsigned(vo,3); s2<=to_unsigned(vs,3);
          when 3 => o3<=to_unsigned(vo,3); s3<=to_unsigned(vs,3);
        end case;
        if vv(k)='1' then                            -- el modelo cuenta igual
          model(vo*6+vs) := model(vo*6+vs) + 1;
        end if;
      end loop;
      valid <= vv;
      wait until rising_edge(clk);                   -- el DUT acumula
    end loop;
    valid <= (others=>'0');
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    -- lectura de las 30 celdas (latencia 1 de rd_cnt)
    for c in 0 to 29 loop
      rd_idx <= to_unsigned(c,5);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait for 1 ns;
      got := to_integer(unsigned(rd_cnt));
      if got /= model(c) then
        report "celda "&integer'image(c)&" got="&integer'image(got)&
               " exp="&integer'image(model(c)) severity error;
        fails := fails + 1;
      end if;
    end loop;
    if fails=0 then report "TEST PASSED" severity note;
    else report "TEST FAILED" severity failure; end if;
    wait;
  end process;
end architecture;
