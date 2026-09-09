--------------------------------------------------------------------------------
-- state_chooser.vhd
--------------------------------------------------------------------------------
-- QUE ES:      el sorteador de estados para clave real: para cada simbolo
--              compara un byte aleatorio con dos umbrales para elegir la base
--              (Z0/Z1/X0) y otro byte con un tercer umbral para el decoy.
-- PARA QUE:    replica el mecanismo ProbZ0UpxS/ProbZ1UpxS/ProbDec0UpxS del
--              sistema original (valores tipicos 100/201/100: P(Z0)=P(Z1)=39%,
--              P(X0)=22%, P(mu0)=39%). Umbrales de 8 bits: probabilidad en
--              unidades de 1/256.
-- COMO SE USA: rnd trae 64 bits frescos por ciclo (prbs_gen o QRNG): el
--              simbolo k usa rnd(16k+7..16k) para la base y rnd(16k+15..16k+8)
--              para el decoy. La codificacion de salida es la del
--              state_to_number_map: estado = base + 3*decoy
--              (z0mu0=0 z1mu0=1 x0mu0=2 z0mu1=3 z1mu1=4 x0mu1=5).
-- CONECTADO A: prbs_gen -> aqui -> mux de fuente del tx_datapath (cuando
--              UseRndDataxS=1); umbrales <- campos del reg_file (CDC nivel).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity state_chooser is
  port (
    clk          : in  std_logic;                    -- dominio tx
    enable       : in  std_logic;                    -- avanza cada ciclo
    prob_z0_up   : in  unsigned(7 downto 0);         -- umbral P(Z0)
    prob_z1_up   : in  unsigned(7 downto 0);         -- umbral P(Z0)+P(Z1)
    prob_dec0_up : in  unsigned(7 downto 0);         -- umbral P(mu0)
    rnd          : in  std_logic_vector(63 downto 0);-- 16 bits por simbolo
    st0, st1, st2, st3 : out unsigned(2 downto 0)    -- estados sorteados
  );
end entity;

architecture rtl of state_chooser is
begin
  process(clk)
    variable r_base  : unsigned(7 downto 0);         -- byte del sorteo de base
    variable r_decoy : unsigned(7 downto 0);         -- byte del sorteo de decoy
    variable base    : integer range 0 to 2;         -- 0=Z0 1=Z1 2=X0
    variable dec     : integer range 0 to 1;         -- 0=mu0 1=mu1
    variable st      : unsigned(2 downto 0);         -- estado final
  begin
    if rising_edge(clk) then
      if enable = '1' then
        for k in 0 to 3 loop                         -- 4 simbolos por ciclo
          r_base  := unsigned(rnd(16*k+7  downto 16*k));    -- byte bajo
          r_decoy := unsigned(rnd(16*k+15 downto 16*k+8));  -- byte alto

          if    r_base < prob_z0_up then base := 0;  -- [0, z0up) -> Z0
          elsif r_base < prob_z1_up then base := 1;  -- [z0up, z1up) -> Z1
          else                           base := 2;  -- resto -> X0
          end if;

          if r_decoy < prob_dec0_up then dec := 0;   -- [0, dec0up) -> mu0
          else                           dec := 1;   -- resto -> mu1
          end if;

          st := to_unsigned(base + 3*dec, 3);        -- codificacion 0..5
          case k is                                  -- reparte a las salidas
            when 0 => st0 <= st;
            when 1 => st1 <= st;
            when 2 => st2 <= st;
            when 3 => st3 <= st;
          end case;
        end loop;
      end if;
    end if;
  end process;
end architecture;
