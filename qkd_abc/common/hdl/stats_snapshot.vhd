--------------------------------------------------------------------------------
-- stats_snapshot.vhd
--------------------------------------------------------------------------------
-- QUE ES:      registro sombra de N contadores con handshake Data_Ready/Ack.
-- PARA QUE:    que Python lea SIEMPRE un conjunto coherente: todos los
--              contadores del MISMO intervalo de integracion. Sin esto, cada
--              lectura PCIe veria un instante distinto y las tasas saldrian
--              inconsistentes (es el patron STAT_* del sistema original).
-- COMO SE USA: los contadores viven en el mismo dominio que este bloque; al
--              vencer G_BLOCK_CYC ciclos se copian a 'shadow' y data_ready=1;
--              el host lee y pulsa ack_stb (STAT_Acknoledge_Read) para
--              liberar. Mientras data_ready=1 la sombra NO cambia (los bloques
--              nuevos se descartan), que es lo que asume el bucle de Python.
-- CONECTADO A: entradas = contadores vivos (histogramas no: tienen su propio
--              doble banco); shadow -> palabras de estado del reg_file;
--              data_ready -> STAT_Data_Ready_regr; ack_stb <- cdc_pulse desde
--              el reg_file; block_time -> STAT_BlockSiftingTimeCnt.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qkd_pkg.all;                              -- reg_array_t

entity stats_snapshot is
  generic (
    N           : natural := 8;                    -- numero de contadores
    G_BLOCK_CYC : natural := 312_500_000           -- ciclos por bloque (1 s)
  );
  port (
    clk        : in  std_logic;                    -- dominio de los contadores
    counters   : in  reg_array_t(0 to N-1);        -- contadores vivos
    ack_stb    : in  std_logic;                    -- pulso de ack (ya en clk)
    data_ready : out std_logic;                    -- hay bloque sin leer
    block_time : out std_logic_vector(31 downto 0);-- duracion real del bloque
    shadow     : out reg_array_t(0 to N-1)         -- copia congelada
  );
end entity;

architecture rtl of stats_snapshot is
  signal blk_cnt : unsigned(31 downto 0) := (others => '0'); -- ciclos del bloque
  signal rdy     : std_logic := '0';                          -- flag interno
begin
  process(clk) begin
    if rising_edge(clk) then
      blk_cnt <= blk_cnt + 1;                       -- avanza el tiempo de bloque

      if to_integer(blk_cnt) = G_BLOCK_CYC-1 then   -- fin de bloque:
        blk_cnt <= (others => '0');                 -- reinicia el temporizador
        if rdy = '0' then                           -- solo si el host ya leyo:
          shadow     <= counters;                   -- copia atomica (mismo ciclo)
          block_time <= std_logic_vector(blk_cnt);  -- duracion (=G_BLOCK_CYC-1)
          rdy        <= '1';                        -- avisa al host
        end if;                                     -- si rdy=1: bloque descartado
      end if;

      if ack_stb = '1' then                         -- el host confirmo lectura:
        rdy <= '0';                                 -- libera para el siguiente
      end if;
    end if;
  end process;
  data_ready <= rdy;                                -- expone el flag
end architecture;
