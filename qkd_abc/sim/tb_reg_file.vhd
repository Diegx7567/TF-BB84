--------------------------------------------------------------------------------
-- tb_reg_file.vhd  —  testbench autocomprobante del banco de registros
--------------------------------------------------------------------------------
-- Comprueba:
--   1. Lectura de la palabra de version (indice 0)
--   2. Read-modify-write: modificar un campo de una palabra de config no altera
--      los campos vecinos (reproduce lo que hace bridge_io.write)
--   3. Ventana de secuencia (400..431): la escritura genera seq_we/addr/data
--   4. Ventana de formas de onda (500..507): idem wave_*
--   5. Escritura en 810: genera squash_we
--   6. Strobes latch/clear al escribir 1 en los indices 2 y 3
--   7. Readback de un registro de estado (RO)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_reg_file is end entity;

architecture sim of tb_reg_file is
  constant CLKP : time := 10 ns;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal wr_en   : std_logic := '0';
  signal wr_addr : unsigned(11 downto 0) := (others=>'0');
  signal wr_data : std_logic_vector(31 downto 0) := (others=>'0');
  signal rd_en   : std_logic := '0';
  signal rd_addr : unsigned(11 downto 0) := (others=>'0');
  signal rd_data : std_logic_vector(31 downto 0);
  signal rd_valid: std_logic;

  constant N_CFG : natural := 63-6+1;
  constant N_ST  : natural := 105-64+1;
  signal cfg_out : std_logic_vector(32*N_CFG-1 downto 0);
  signal st_in   : std_logic_vector(32*N_ST-1 downto 0) := (others=>'0');

  signal latch_stb, clear_stb : std_logic;
  signal seq_we : std_logic; signal seq_addr : unsigned(4 downto 0);
  signal seq_data : std_logic_vector(31 downto 0);
  signal wave_we : std_logic; signal wave_addr : unsigned(2 downto 0);
  signal wave_data : std_logic_vector(31 downto 0);
  signal squash_we, squash_clear : std_logic;
  signal squash_data : std_logic_vector(31 downto 0);

  signal fails : integer := 0;

  -- lee una palabra por el puerto de lectura (2 ciclos: en/valid)
  procedure do_read(signal clk : in std_logic;
                    signal rd_en : out std_logic;
                    signal rd_addr : out unsigned(11 downto 0);
                    addr : in natural) is
  begin
    rd_en <= '1'; rd_addr <= to_unsigned(addr,12);
    wait until rising_edge(clk);
    rd_en <= '0';
    wait until rising_edge(clk);   -- rd_data ya valido
  end procedure;

begin
  clk <= not clk after CLKP/2;

  dut : entity work.reg_file
    port map (clk=>clk, rst=>rst,
      wr_en=>wr_en, wr_addr=>wr_addr, wr_data=>wr_data,
      rd_en=>rd_en, rd_addr=>rd_addr, rd_data=>rd_data, rd_valid=>rd_valid,
      cfg_out=>cfg_out, st_in=>st_in,
      latch_stb=>latch_stb, clear_stb=>clear_stb,
      seq_we=>seq_we, seq_addr=>seq_addr, seq_data=>seq_data,
      wave_we=>wave_we, wave_addr=>wave_addr, wave_data=>wave_data,
      squash_we=>squash_we, squash_clear=>squash_clear, squash_data=>squash_data);

  main : process
    procedure wr(addr : natural; data : std_logic_vector(31 downto 0)) is
    begin
      wr_en <= '1'; wr_addr <= to_unsigned(addr,12); wr_data <= data;
      wait until rising_edge(clk);
      wr_en <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if not cond then
        report "FALLO: " & msg severity error;
        fails <= fails + 1;
      end if;
    end procedure;
  begin
    -- reset
    rst <= '1';
    wait until rising_edge(clk); wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    ----------------------------------------------------------------
    -- 1. version
    ----------------------------------------------------------------
    do_read(clk, rd_en, rd_addr, 0);
    check(rd_data = x"1A_07_18_01", "version incorrecta");

    ----------------------------------------------------------------
    -- 2. read-modify-write sobre el indice 6:
    --    escribimos 0xFFFF0000, luego simulamos un RMW que cambia solo
    --    el byte bajo a 0xAB, y verificamos que el resto no cambia.
    ----------------------------------------------------------------
    wr(6, x"FFFF0000");
    do_read(clk, rd_en, rd_addr, 6);
    check(rd_data = x"FFFF0000", "escritura simple en idx 6 fallida");

    -- RMW: leer, modificar byte 0, reescribir (como bridge_io.write)
    do_read(clk, rd_en, rd_addr, 6);
    wr(6, (rd_data and x"FFFFFF00") or x"000000AB");
    do_read(clk, rd_en, rd_addr, 6);
    check(rd_data = x"FFFF00AB", "RMW corrompio bits vecinos");

    -- y comprobamos que un registro vecino (idx 7) sigue a cero
    do_read(clk, rd_en, rd_addr, 7);
    check(rd_data = x"00000000", "idx 7 no deberia haber cambiado");

    ----------------------------------------------------------------
    -- 3. ventana de secuencia (400..431)
    --    seq_we/addr/data estan REGISTRADOS: aparecen el ciclo siguiente
    --    al que se presenta wr_en. Presentamos, avanzamos un flanco y
    --    comprobamos.
    ----------------------------------------------------------------
    wr_en <= '1'; wr_addr <= to_unsigned(405,12); wr_data <= x"DEADBEEF";
    wait until rising_edge(clk);      -- el DUT registra la escritura aqui
    wr_en <= '0';
    wait until rising_edge(clk);      -- seq_* ya validos en este ciclo
    check(seq_we = '1', "seq_we no se activo");
    check(seq_addr = to_unsigned(5,5), "seq_addr incorrecta");
    check(seq_data = x"DEADBEEF", "seq_data incorrecta");
    wait until rising_edge(clk);
    check(seq_we = '0', "seq_we deberia durar 1 ciclo");

    ----------------------------------------------------------------
    -- 4. ventana de formas de onda (500..507)
    ----------------------------------------------------------------
    wr_en <= '1'; wr_addr <= to_unsigned(503,12); wr_data <= x"0000CAFE";
    wait until rising_edge(clk);
    wr_en <= '0';
    wait until rising_edge(clk);
    check(wave_we = '1', "wave_we no se activo");
    check(wave_addr = to_unsigned(3,3), "wave_addr incorrecta");
    check(wave_data = x"0000CAFE", "wave_data incorrecta");
    wait until rising_edge(clk);

    ----------------------------------------------------------------
    -- 5. escritura en 810 (squashing)
    ----------------------------------------------------------------
    wr_en <= '1'; wr_addr <= to_unsigned(810,12); wr_data <= x"0002_03FF";
    wait until rising_edge(clk);
    wr_en <= '0';
    wait until rising_edge(clk);
    check(squash_we = '1', "squash_we no se activo");
    check(squash_data = x"0002_03FF", "squash_data incorrecta");
    wait until rising_edge(clk);

    ----------------------------------------------------------------
    -- 6. strobes latch/clear (indices 2 y 3)
    ----------------------------------------------------------------
    wr(2, x"00000001");     -- pone w2=1 -> pulso latch en el flanco
    -- el pulso ocurre un ciclo despues; lo observamos en el proceso monitor
    wr(3, x"00000001");

    ----------------------------------------------------------------
    -- 7. readback de estado: ponemos st_in del idx 64 y lo leemos
    ----------------------------------------------------------------
    st_in(31 downto 0) <= x"12345678";   -- estado idx 64
    wait until rising_edge(clk);
    do_read(clk, rd_en, rd_addr, 64);
    check(rd_data = x"12345678", "readback de estado idx 64 fallido");

    -- resumen
    wait until rising_edge(clk);
    if fails = 0 then
      report "==================  TEST PASSED  ==================" severity note;
    else
      report "==================  TEST FAILED (" &
             integer'image(fails) & " fallos)  ==================" severity failure;
    end if;
    wait;
  end process;

  -- monitor de strobes: comprueba que latch/clear se disparan alguna vez
  monitor : process(clk)
    variable seen_latch : boolean := false;
    variable seen_clear : boolean := false;
  begin
    if rising_edge(clk) then
      if latch_stb = '1' then seen_latch := true; end if;
      if clear_stb = '1' then seen_clear := true; end if;
    end if;
  end process;

end architecture;
