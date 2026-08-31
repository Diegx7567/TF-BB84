--------------------------------------------------------------------------------
-- qkd_pkg.vhd
--------------------------------------------------------------------------------
-- QUE ES:      paquete de tipos y constantes compartidos por todo el gateware.
-- PARA QUE:    evitar redefinir en cada modulo el tipo "array de palabras de
--              32 bits" (usado por el snapshot de estadisticas y los tops) y
--              centralizar las constantes del sistema.
-- COMO SE USA: "use work.qkd_pkg.all;" en cualquier modulo.
-- CONECTADO A: no tiene puertos; es solo codigo.
--------------------------------------------------------------------------------
library ieee;                                  -- libreria estandar IEEE
use ieee.std_logic_1164.all;                   -- tipos std_logic / vector

package qkd_pkg is
  -- array generico de palabras de 32 bits (contadores, registros sombra...)
  type reg_array_t is array (natural range <>) of std_logic_vector(31 downto 0);

  -- constantes del sistema (documentacion ejecutable):
  constant C_SAMPLE_PS     : natural := 50;    -- 1 muestra = 50 ps (20 GS/s)
  constant C_BIN_PS        : natural := 100;   -- 1 bin = 100 ps = 2 muestras
  constant C_SYMBOL_PS     : natural := 800;   -- 1 simbolo = 800 ps = 8 bins
  constant C_SYMS_PER_SEQ  : natural := 256;   -- longitud de la secuencia
  constant C_N_STATES      : natural := 6;     -- z0/z1/x0 x decoy mu0/mu1
  constant C_N_OUTCOMES    : natural := 5;     -- z0,z1,x0,x1,x2 tras squashing
end package;
