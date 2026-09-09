--------------------------------------------------------------------------------
-- clk_counter.vhd
--------------------------------------------------------------------------------
-- QUE ES:      frecuencimetro: cuenta ciclos de un reloj "bajo prueba"
--              (clk_meas) durante una ventana fija medida en el reloj del
--              host, y publica la cuenta al final de cada ventana.
-- PARA QUE:    es el instrumento de is_clock_recovered() de Python: al
--              conmutar EnableRecClk, la cuenta debe cambiar >=1900 en 2 s si
--              el reloj recuperado esta vivo. Una instancia por dominio
--              (host, tx/rx, sc, refclk conmutado).
-- COMO SE USA: latch_stb/clear_stb (indices 2/3 del bridge) rearman la
--              ventana, replicando la secuencia write(2,1);write(3,1);... del
--              software. count_win se cablea a CLKCTL_ClkN_Counter_regr.
-- CONECTADO A: reg_file (strobes y palabra de estado) y al reloj a medir.
-- COMO FUNCIONA: contador binario libre en clk_meas -> conversion a codigo
--              Gray (solo 1 bit cambia por ciclo: cruzar dominios es seguro)
--              -> doble FF en clk_host -> Gray a binario -> resta entre dos
--              capturas separadas por la ventana.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clk_counter is
  generic (
    G_WIN_CYCLES : natural := 250_000_000    -- ventana en ciclos de clk_host
  );                                          -- (2 s a 125 MHz; en TB, pocos)
  port (
    clk_meas  : in  std_logic;               -- reloj a medir
    clk_host  : in  std_logic;               -- reloj de referencia (host)
    latch_stb : in  std_logic;               -- indice 2: rearma la ventana
    clear_stb : in  std_logic;               -- indice 3: idem (mismo efecto)
    count_win : out std_logic_vector(31 downto 0)  -- ciclos de clk_meas/ventana
  );
end entity;

architecture rtl of clk_counter is
  signal cnt_bin   : unsigned(31 downto 0) := (others => '0'); -- contador libre
  signal cnt_gray  : std_logic_vector(31 downto 0) := (others => '0'); -- en Gray
  signal g_s1,g_s2 : std_logic_vector(31 downto 0) := (others => '0'); -- 2FF sync
  signal snap_prev : unsigned(31 downto 0) := (others => '0'); -- captura anterior
  signal win_cnt   : natural range 0 to G_WIN_CYCLES-1 := 0;   -- reloj de ventana

  -- conversion Gray -> binario (combinacional, en el dominio host)
  function g2b(g : std_logic_vector) return unsigned is
    variable b : std_logic_vector(g'range);      -- resultado parcial
  begin
    b(b'left) := g(g'left);                      -- MSB igual
    for i in g'left-1 downto g'right loop        -- del MSB-1 hacia abajo:
      b(i) := b(i+1) xor g(i);                   -- b(i)=b(i+1) xor g(i)
    end loop;
    return unsigned(b);
  end function;
begin
  -- DOMINIO MEDIDO: contador binario libre + su version en Gray registrada
  process(clk_meas) begin
    if rising_edge(clk_meas) then
      cnt_bin  <= cnt_bin + 1;                                   -- cuenta libre
      cnt_gray <= std_logic_vector(cnt_bin xor ('0' & cnt_bin(31 downto 1)));
                                                                 -- bin->Gray
    end if;
  end process;

  -- DOMINIO HOST: sincroniza el Gray, y al vencer la ventana publica la resta
  process(clk_host)
    variable now_bin : unsigned(31 downto 0);    -- valor actual ya en binario
  begin
    if rising_edge(clk_host) then
      g_s1 <= cnt_gray;                          -- 1er FF (posible metaestable)
      g_s2 <= g_s1;                              -- 2do FF (estable)
      now_bin := g2b(g_s2);                      -- de vuelta a binario

      if latch_stb = '1' or clear_stb = '1' then -- rearme desde el software:
        win_cnt   <= 0;                          -- reinicia la ventana
        snap_prev <= now_bin;                    -- y toma referencia nueva
      elsif win_cnt = G_WIN_CYCLES-1 then        -- fin de ventana:
        win_cnt   <= 0;                          -- reinicia
        count_win <= std_logic_vector(now_bin - snap_prev); -- publica la cuenta
        snap_prev <= now_bin;                    -- referencia para la siguiente
      else
        win_cnt <= win_cnt + 1;                  -- avanza la ventana
      end if;
    end if;
  end process;
end architecture;
