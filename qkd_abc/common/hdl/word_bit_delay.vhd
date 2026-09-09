--------------------------------------------------------------------------------
-- word_bit_delay.vhd
--------------------------------------------------------------------------------
-- Retardo programable de un flujo de palabras, con resolucion de UNA muestra.
--
-- Uso en el sistema QKD:
--   * Alice: una instancia por linea de salida (laser + 3 datos DAC + reloj DAC),
--            controlada por DelayOutput0xS..DelayOutput4xS. Alinea las lineas
--            entre si antes de los GTY.
--   * Bob:   una instancia por canal de deteccion (Z y X), controlada por
--            DelayInput0xS / DelayInput1xS. Alinea las muestras recibidas con
--            la rejilla de bins antes del binner.
--
-- El flujo llega en palabras de W bits (W = 64 con datapath GTY de 64 bits).
-- Cada bit de la palabra es una muestra de 50 ps. El retardo 'delay' se expresa
-- en muestras (0 .. MAX_DELAY) y se descompone en:
--     coarse = delay / W    -> retroceso en palabras enteras (memoria circular)
--     fine   = delay mod W   -> desplazamiento dentro de la palabra (barrel)
--
-- Convenio de bits (IMPORTANTE, debe coincidir con el resto del diseno):
--   din(0)      = muestra mas antigua de la palabra
--   din(W-1)    = muestra mas reciente
--   Un retardo positivo hace que la salida en el instante t sea la entrada en
--   el instante (t - delay).
--
-- Latencia: la salida esta registrada; el dato valido aparece unos ciclos
-- despues de aplicar 'din' (ver READMEtb para el valido exacto usado en el TB).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity word_bit_delay is
  generic (
    W         : natural := 64;      -- bits (muestras) por palabra
    MAX_DELAY : natural := 2047     -- retardo maximo en muestras (11 bits)
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                         -- sincrono, activo alto
    delay  : in  unsigned(10 downto 0);             -- retardo en muestras
    din    : in  std_logic_vector(W-1 downto 0);
    dout   : out std_logic_vector(W-1 downto 0)
  );
end entity;

architecture rtl of word_bit_delay is

  -- profundidad de la memoria circular: numero de palabras que hay que poder
  -- retroceder (coarse maximo) mas 2 de guarda (para leer tambien la anterior).
  constant DEPTH : natural := (MAX_DELAY / W) + 3;

  type ram_t is array (0 to DEPTH-1) of std_logic_vector(W-1 downto 0);
  signal ram  : ram_t := (others => (others => '0'));

  signal wptr : integer range 0 to DEPTH-1 := 0;

  -- descomposicion registrada del retardo (mejora el timing: no dividimos en
  -- el camino critico, lo hacemos una vez por ciclo sobre 'delay')
  signal coarse : integer range 0 to DEPTH-1 := 0;
  signal fine   : integer range 0 to W-1    := 0;

  -- palabra retrasada y su anterior, para el barrel
  signal w_del  : std_logic_vector(W-1 downto 0) := (others => '0');
  signal w_prev : std_logic_vector(W-1 downto 0) := (others => '0');

  -- registros de la palabra de entrada, para el bypass de coarse=0.
  -- El registro de bypass hace que la latencia del camino coarse=0 coincida
  -- con la del camino por memoria (latencia total uniforme: 3 ciclos).
  signal din_q1 : std_logic_vector(W-1 downto 0) := (others => ('0'));  -- din(t-1)

begin

  --------------------------------------------------------------------------
  -- Escritura en la memoria circular y descomposicion del retardo
  --------------------------------------------------------------------------
  process(clk)
    variable rd_del  : integer range 0 to DEPTH-1;
    variable rd_prev : integer range 0 to DEPTH-1;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        wptr   <= 0;
        coarse <= 0;
        fine   <= 0;
        w_del  <= (others => '0');
        w_prev <= (others => '0');
      else
        -- 1) guarda la palabra entrante y desplaza los registros de bypass
        ram(wptr) <= din;
        din_q1    <= din;

        -- 2) descompone el retardo (registrado)
        coarse <= to_integer(delay) / W;
        fine   <= to_integer(delay) mod W;

        -- 3) lee la palabra retrasada y la inmediatamente anterior.
        --    Para coarse=0 la "palabra retrasada" seria la que se escribe en
        --    este mismo ciclo (hazard de lectura-durante-escritura), asi que
        --    tomamos las palabras ya registradas: con dos etapas de bypass la
        --    latencia coincide con la del camino por memoria.
        --      w_del  = din(t-1)  (equivalente a leer la palabra recien escrita)
        --      w_prev = din(t-2)
        if coarse = 0 then
          w_del  <= din;
          w_prev <= din_q1;
        else
          rd_del  := (wptr - coarse + DEPTH) mod DEPTH;
          rd_prev := (rd_del - 1 + DEPTH) mod DEPTH;
          w_del  <= ram(rd_del);
          w_prev <= ram(rd_prev);
        end if;

        -- 4) avanza el puntero de escritura
        if wptr = DEPTH-1 then
          wptr <= 0;
        else
          wptr <= wptr + 1;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------
  -- Barrel shifter fino. Queremos que la salida cumpla, para la palabra cuya
  -- primera muestra global es gout (= la de w_del):
  --     dout(i) = muestra[gout + i - fine]
  -- Con w_del = muestras[gout .. gout+W-1] y w_prev la palabra anterior,
  -- la ventana correcta sobre la concatenacion (w_prev en la parte baja,
  -- w_del en la alta) empieza en (W - fine):
  --
  --   cat = w_del & w_prev   (2W bits; [2W-1..W]=w_del, [W-1..0]=w_prev)
  --   dout = cat( (W-fine)+W-1  downto  (W-fine) )
  --
  -- Para fine=0 -> start=W -> dout = w_del (sin desplazamiento fino). Correcto.
  --------------------------------------------------------------------------
  process(clk)
    variable cat   : std_logic_vector(2*W-1 downto 0);
    variable start : integer range 0 to W;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        dout <= (others => '0');
      else
        cat   := w_del & w_prev;   -- [2W-1..W]=w_del (alta), [W-1..0]=w_prev (baja)
        start := W - fine;
        dout  <= cat(start + W - 1 downto start);
      end if;
    end if;
  end process;

end architecture;
