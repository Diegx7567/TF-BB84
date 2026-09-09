--------------------------------------------------------------------------------
-- squash_lut.vhd
--------------------------------------------------------------------------------
-- QUE ES:      la tabla de squashing: memoria de 256 entradas x 10 bits que
--              convierte los 5 bits de deteccion {Z1,Z0,X2,X1,X0} + 3 bits
--              aleatorios {R2,R1,R0} en el resultado final del simbolo,
--              resolviendo los clics multiples al azar (sin sesgo).
-- PARA QUE:    es la "decision de estado" de C. El contenido lo genera
--              toro_squashing_table.py y NO se toca aqui: el hardware es solo
--              la memoria y su mecanismo de carga.
-- COMO SE USA: carga secuencial identica al original: cada escritura en el
--              indice 810 escribe una fila y autoincrementa el puntero;
--              squash_clear (via reg_file) lo devuelve a 0. La fila i
--              corresponde a la direccion de entrada i. En consulta, procesa
--              4 simbolos por ciclo (4 puertos de lectura = 4 replicas de la
--              tabla; 256x10 bits, replicarla es gratis).
-- CONECTADO A: reg_file (squash_we/clear/data) para la carga; binner+prbs
--              forman las direcciones; las salidas van a los contadores
--              PSIFT_* y a la coincidence_matrix.
-- FORMATO de la fila (10 bits, orden del fichero de tabla):
--              [9]=Z1 [8]=Z0 [7]=X2 [6]=X1 [5]=X0 resueltos,
--              [4]=RngReq (consumio aleatoriedad), [3:0]=stats de diagnostico.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity squash_lut is
  port (
    -- carga secuencial (dominio host, via reg_file)
    wclk   : in  std_logic;
    we     : in  std_logic;                          -- escritura indice 810
    wclear : in  std_logic;                          -- puntero a 0
    wdata  : in  std_logic_vector(9 downto 0);       -- fila de la tabla
    -- consulta: 4 simbolos por ciclo (dominio rx)
    rclk   : in  std_logic;
    addr0, addr1, addr2, addr3 : in  std_logic_vector(7 downto 0);
    out0, out1, out2, out3     : out std_logic_vector(9 downto 0)
  );
end entity;

architecture rtl of squash_lut is
  type mem_t is array (0 to 255) of std_logic_vector(9 downto 0);
  -- cuatro replicas identicas: una por puerto de lectura simultaneo
  signal mem0, mem1, mem2, mem3 : mem_t := (others => (others => '0'));
  signal wptr : unsigned(7 downto 0) := (others => '0');  -- puntero de carga
begin
  -- CARGA: cada 'we' escribe la fila actual EN LAS CUATRO replicas a la vez
  process(wclk) begin
    if rising_edge(wclk) then
      if wclear = '1' then
        wptr <= (others => '0');                     -- reinicio del puntero
      elsif we = '1' then
        mem0(to_integer(wptr)) <= wdata;             -- replica del puerto 0
        mem1(to_integer(wptr)) <= wdata;             -- replica del puerto 1
        mem2(to_integer(wptr)) <= wdata;             -- replica del puerto 2
        mem3(to_integer(wptr)) <= wdata;             -- replica del puerto 3
        wptr <= wptr + 1;                            -- autoincremento
      end if;
    end if;
  end process;

  -- CONSULTA: 4 lecturas independientes, registradas (latencia 1 ciclo)
  process(rclk) begin
    if rising_edge(rclk) then
      out0 <= mem0(to_integer(unsigned(addr0)));     -- simbolo 0 de la palabra
      out1 <= mem1(to_integer(unsigned(addr1)));     -- simbolo 1
      out2 <= mem2(to_integer(unsigned(addr2)));     -- simbolo 2
      out3 <= mem3(to_integer(unsigned(addr3)));     -- simbolo 3
    end if;
  end process;
end architecture;
