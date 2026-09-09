--------------------------------------------------------------------------------
-- coincidence_matrix.vhd
--------------------------------------------------------------------------------
-- QUE ES:      la matriz de coincidencias: 30 contadores de 32 bits, uno por
--              par (lo que C detecto [5 salidas], lo que el transmisor debia
--              enviar [6 estados]). indice = outcome*6 + estado.
-- PARA QUE:    es la comparacion bit a bit EN HARDWARE de la que sale el BER/
--              QBER: la diagonal son aciertos, el resto errores o cruces de
--              base. Python la lee en los indices 850..879 y calcula QBER =
--              errores/comprobaciones (StatisticsFormulasToro).
-- COMO SE USA: por cada simbolo con deteccion valida, se presenta el resultado
--              de C (outcome 0..4) y el estado esperado (alice_state 0..5,
--              leido de la seq_bram local con el contador de simbolo). Procesa
--              4 simbolos por ciclo; clear pone todo a cero al empezar bloque.
-- CONECTADO A: squash_lut (outcomes) + seq_bram local (estados esperados) ->
--              aqui -> stats_snapshot/reg_file (lectura por rd_idx).
-- DETALLE:     dos simbolos del mismo ciclo PUEDEN caer en la misma celda
--              (misma combinacion outcome/estado), asi que cada celda suma
--              hasta 4 incrementos por ciclo (comparadores en paralelo).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity coincidence_matrix is
  port (
    clk    : in  std_logic;                          -- dominio rx
    clear  : in  std_logic;                          -- borra los 30 contadores
    -- 4 simbolos por ciclo:
    valid  : in  std_logic_vector(3 downto 0);       -- hubo deteccion valida
    out0, out1, out2, out3 : in unsigned(2 downto 0);-- outcome de C (0..4)
    st0,  st1,  st2,  st3  : in unsigned(2 downto 0);-- estado esperado (0..5)
    -- lectura por el host
    rd_idx : in  unsigned(4 downto 0);               -- celda 0..29
    rd_cnt : out std_logic_vector(31 downto 0)       -- su contador
  );
end entity;

architecture rtl of coincidence_matrix is
  type cnt_t is array (0 to 29) of unsigned(31 downto 0);
  signal cnt : cnt_t := (others => (others => '0'));
begin
  process(clk)
    -- celda a la que apunta cada uno de los 4 simbolos de este ciclo
    variable c0, c1, c2, c3 : integer range 0 to 47;
    variable inc            : integer range 0 to 4;  -- incrementos por celda
  begin
    if rising_edge(clk) then
      -- precalcula la celda de cada simbolo: outcome*6 + estado
      c0 := to_integer(out0)*6 + to_integer(st0);
      c1 := to_integer(out1)*6 + to_integer(st1);
      c2 := to_integer(out2)*6 + to_integer(st2);
      c3 := to_integer(out3)*6 + to_integer(st3);

      if clear = '1' then
        cnt <= (others => (others => '0'));          -- borrado sincrono
      else
        for c in 0 to 29 loop                        -- para cada celda:
          inc := 0;                                  -- cuenta cuantos de los 4
          if valid(0)='1' and c0=c then inc := inc+1; end if;  -- simbolos de
          if valid(1)='1' and c1=c then inc := inc+1; end if;  -- este ciclo
          if valid(2)='1' and c2=c then inc := inc+1; end if;  -- apuntan a
          if valid(3)='1' and c3=c then inc := inc+1; end if;  -- esta celda
          cnt(c) <= cnt(c) + inc;                    -- y suma de una vez
        end loop;
      end if;

      rd_cnt <= std_logic_vector(cnt(to_integer(rd_idx)));  -- lectura reg.
    end if;
  end process;
end architecture;
