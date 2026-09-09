--------------------------------------------------------------------------------
-- cdc_pulse.vhd
--------------------------------------------------------------------------------
-- QUE ES:      sincronizador de PULSOS entre dos dominios de reloj (toggle +
--              doble flip-flop + detector de flanco).
-- PARA QUE:    los strobes que el host genera en clk_host (ClearSeq, latch de
--              contadores, avance de FSM, ack de estadisticas) deben llegar
--              como UN pulso limpio al dominio rapido. Cruzar un pulso "tal
--              cual" es metaestable y puede perderse o duplicarse.
-- COMO SE USA: instanciar con src_clk/dst_clk y conectar el pulso.
-- CONECTADO A: reg_file (latch_stb, clear_stb, squash_clear...) -> dominios
--              tx_usr / rx_usr de los tops.
-- NOTA:        en Vivado, anhade "set_max_delay -datapath_only" sobre 'tgl';
--              aqui usamos FFs planos para que sea simulable sin XPM.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity cdc_pulse is
  port (
    src_clk   : in  std_logic;   -- reloj del dominio origen (p.ej. clk_host)
    src_pulse : in  std_logic;   -- pulso de 1 ciclo en el dominio origen
    dst_clk   : in  std_logic;   -- reloj del dominio destino (p.ej. rx_usr)
    dst_pulse : out std_logic    -- pulso de 1 ciclo en el dominio destino
  );
end entity;

architecture rtl of cdc_pulse is
  signal tgl        : std_logic := '0';  -- toggle: cambia con cada pulso origen
  signal sync1      : std_logic := '0';  -- 1er FF de sincronizacion en destino
  signal sync2      : std_logic := '0';  -- 2do FF (salida ya estable)
  signal sync2_d    : std_logic := '0';  -- retardo para detectar flanco
begin
  -- DOMINIO ORIGEN: convertir el pulso en un cambio de nivel (toggle).
  -- Un nivel cruza dominios sin perderse; un pulso de 1 ciclo puede no verse.
  process(src_clk) begin
    if rising_edge(src_clk) then
      if src_pulse = '1' then          -- cada pulso origen...
        tgl <= not tgl;                -- ...invierte el nivel
      end if;
    end if;
  end process;

  -- DOMINIO DESTINO: doble FF (resuelve metaestabilidad) + detector de flanco
  process(dst_clk) begin
    if rising_edge(dst_clk) then
      sync1   <= tgl;                  -- primer registro (puede metaestabilizar)
      sync2   <= sync1;                -- segundo registro (ya estable)
      sync2_d <= sync2;                -- copia retrasada para comparar
      dst_pulse <= sync2 xor sync2_d;  -- flanco (cambio de nivel) = 1 pulso
    end if;
  end process;
end architecture;
