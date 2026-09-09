--------------------------------------------------------------------------------
-- prbs_gen.vhd
--------------------------------------------------------------------------------
-- QUE ES:      generador pseudoaleatorio PRBS-31 (polinomio x^31 + x^28 + 1,
--              ITU-T O.150) que produce NBITS bits nuevos por ciclo.
-- PARA QUE:    (1) fuente de estados aleatorios del state_chooser en A/B;
--              (2) los 3 bits R2R1R0 que desempatan multiclics en C;
--              (3) patrones de test del enlace.
--              Periodo 2^31-1 bits (~1,7 s de datos a 1,25 Gsimbolo/s).
-- COMO SE USA: enable=1 avanza; clear reinicia a la semilla (todo unos).
-- CONECTADO A: state_chooser (A/B), squash_lut vía bits R (C), tx de test.
-- NOTA:        para clave real se sustituye por el QRNG con el mismo puerto
--              (por eso la salida es un simple bus de NBITS bits).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity prbs_gen is
  generic (
    NBITS : natural := 64                    -- bits nuevos por ciclo (<= 64)
  );
  port (
    clk    : in  std_logic;                  -- reloj del dominio consumidor
    clear  : in  std_logic;                  -- reinicio sincrono a la semilla
    enable : in  std_logic;                  -- avanza NBITS bits por ciclo
    dout   : out std_logic_vector(NBITS-1 downto 0)  -- dout(0)=primer bit
  );
end entity;

architecture rtl of prbs_gen is
  -- estado del LFSR de 31 bits; semilla = todo unos (estado prohibido = 0)
  signal lfsr : std_logic_vector(30 downto 0) := (others => '1');
begin
  process(clk)
    variable v : std_logic_vector(30 downto 0);  -- copia de trabajo del estado
    variable b : std_logic;                      -- bit nuevo de cada iteracion
  begin
    if rising_edge(clk) then
      if clear = '1' then
        lfsr <= (others => '1');                 -- vuelve a la semilla
      elsif enable = '1' then
        v := lfsr;                               -- parte del estado actual
        for i in 0 to NBITS-1 loop               -- desenrolla NBITS pasos
          b := v(30) xor v(27);                  -- realimentacion x^31+x^28
          v := v(29 downto 0) & b;               -- desplaza e inserta el bit
          dout(i) <= b;                          -- bit i-esimo de esta palabra
        end loop;
        lfsr <= v;                               -- guarda el estado avanzado
      end if;
    end if;
  end process;
end architecture;
