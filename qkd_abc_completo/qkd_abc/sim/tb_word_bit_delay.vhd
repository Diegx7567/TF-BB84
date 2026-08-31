--------------------------------------------------------------------------------
-- tb_word_bit_delay.vhd  —  testbench autocomprobante
--------------------------------------------------------------------------------
-- Estrategia:
--   * Genera un flujo de muestras conocido (un contador global de muestras
--     serializado en palabras de W bits): la muestra de indice global g vale
--     g mod 2 ... no: para poder distinguir todas las muestras usamos una
--     secuencia pseudoaleatoria reproducible (LFSR) como valor de cada muestra.
--   * Mantiene un modelo de referencia: una cola con TODAS las muestras
--     emitidas. La salida en un instante debe ser la ventana de W muestras
--     que empieza 'delay' muestras por detras de la ultima entrada consumida.
--   * Aplica varios retardos fijos (incluye 0, extremos y aleatorios) y para
--     cada uno comprueba muestra a muestra durante muchas palabras.
--
-- La latencia del DUT (en palabras) se mide y se compensa automaticamente al
-- principio de cada tramo, buscando el desplazamiento que hace coincidir la
-- salida con el modelo. Asi el TB no depende de un valor de latencia hardcode.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_word_bit_delay is
end entity;

architecture sim of tb_word_bit_delay is

  constant W         : natural := 64;
  constant MAX_DELAY : natural := 2047;
  constant CLKP      : time    := 10 ns;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal delay : unsigned(10 downto 0) := (others => '0');
  signal din   : std_logic_vector(W-1 downto 0) := (others => '0');
  signal dout  : std_logic_vector(W-1 downto 0);

  -- historial de todas las muestras emitidas (modelo de referencia)
  constant HIST : natural := 400000;         -- suficiente para el test
  type samp_arr is array (0 to HIST-1) of std_logic;
  signal hist_samples : samp_arr := (others => '0');
  signal n_emitted    : integer := 0;        -- muestras emitidas hasta ahora

  signal test_failed : boolean := false;

  -- LFSR de 16 bits para generar muestras reproducibles
  function next_lfsr(v : unsigned(15 downto 0)) return unsigned is
    variable b : std_logic;
  begin
    b := v(15) xor v(13) xor v(12) xor v(10);
    return v(14 downto 0) & b;
  end function;

begin

  --------------------------------------------------------------------------
  clk <= not clk after CLKP/2;

  dut : entity work.word_bit_delay
    generic map (W => W, MAX_DELAY => MAX_DELAY)
    port map (clk => clk, rst => rst, delay => delay, din => din, dout => dout);

  --------------------------------------------------------------------------
  -- Proceso principal: genera el flujo, aplica retardos y comprueba
  --------------------------------------------------------------------------
  main : process
    variable lfsr    : unsigned(15 downto 0) := x"ACE1";
    variable word    : std_logic_vector(W-1 downto 0);
    variable emitted : integer := 0;

    -- emite una palabra nueva (W muestras) y la registra en el historial
    procedure emit_word is
      variable wv : std_logic_vector(W-1 downto 0);
    begin
      for i in 0 to W-1 loop
        lfsr := next_lfsr(lfsr);
        wv(i) := lfsr(0);
        hist_samples(emitted) <= lfsr(0);
        emitted := emitted + 1;
      end loop;
      din <= wv;
      n_emitted <= emitted;
      wait until rising_edge(clk);
    end procedure;

    -- comprueba una palabra de salida contra el modelo, para un retardo dado
    -- 'first_in_idx' = indice global de la muestra 0 de la palabra que el DUT
    -- deberia estar sacando ahora (se ajusta con la latencia medida).
    procedure check_word(dly : integer; first_in_idx : integer;
                         ok : inout boolean) is
      variable expected : std_logic;
      variable src      : integer;
    begin
      for i in 0 to W-1 loop
        src := first_in_idx + i - dly;         -- muestra fuente
        if src >= 0 then
          expected := hist_samples(src);
          if dout(i) /= expected then
            report "MISMATCH delay=" & integer'image(dly) &
                   " word_first=" & integer'image(first_in_idx) &
                   " bit=" & integer'image(i) &
                   " got=" & std_logic'image(dout(i)) &
                   " exp=" & std_logic'image(expected)
              severity error;
            ok := false;
          end if;
        end if;
      end loop;
    end procedure;

    -- ejecuta un tramo con un retardo fijo: primero mide la latencia (en
    -- palabras) buscando el offset que casa, luego comprueba N palabras.
    procedure run_delay(dly : integer) is
      variable ok       : boolean := true;
      variable lat      : integer := -1;
      variable base_idx : integer;
      variable trial    : integer;
      variable good     : boolean;
      variable src      : integer;
    begin
      delay <= to_unsigned(dly, 11);
      -- llena el pipeline y el historial con margen
      for k in 0 to (MAX_DELAY/W) + 8 loop
        emit_word;
      end loop;

      -- mide la latencia: prueba offsets 1..12 palabras y elige el que casa
      -- en una palabra limpia (usamos la palabra actual de entrada como ref)
      base_idx := n_emitted - W;   -- indice global de la palabra recien puesta
      for trial in 1 to 20 loop
        good := true;
        -- la palabra que sale ahora corresponde a la entrada de hace 'trial'
        -- palabras: su primera muestra global es base_idx - (trial-1)*W
        for i in 0 to W-1 loop
          src := (base_idx - (trial-1)*W) + i - dly;
          if src >= 0 then
            if dout(i) /= hist_samples(src) then good := false; end if;
          end if;
        end loop;
        if good and lat < 0 then lat := trial; end if;
      end loop;

      if lat < 0 then
        report "No se pudo medir latencia para delay=" & integer'image(dly)
          severity error;
        test_failed <= true;
        return;
      end if;

      -- comprueba 300 palabras nuevas con la latencia medida
      for k in 0 to 149 loop
        base_idx := n_emitted - W;                 -- palabra en la entrada ahora
        check_word(dly, base_idx - (lat-1)*W, ok);  -- palabra en la salida ahora
        emit_word;
      end loop;

      if not ok then
        test_failed <= true;
        report "FALLO en delay=" & integer'image(dly) severity error;
      else
        report "OK delay=" & integer'image(dly) &
               " (latencia " & integer'image(lat) & " palabras)"
          severity note;
      end if;
    end procedure;

    variable seed1 : positive := 42;
    variable seed2 : positive := 7;
    variable rr    : real;
    variable rdly  : integer;
  begin
    -- reset
    rst <= '1';
    din <= (others => '0');
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- casos deterministas primero
    run_delay(0);
    run_delay(1);
    run_delay(W-1);
    run_delay(W);
    run_delay(W+1);
    run_delay(2*W+5);
    run_delay(MAX_DELAY);

    -- casos aleatorios
    for t in 0 to 7 loop
      uniform(seed1, seed2, rr);
      rdly := integer(floor(rr * real(MAX_DELAY)));
      run_delay(rdly);
    end loop;

    if test_failed then
      report "==================  TEST FAILED  ==================" severity failure;
    else
      report "==================  TEST PASSED  ==================" severity note;
    end if;
    wait;
  end process;

end architecture;
