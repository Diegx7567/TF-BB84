--------------------------------------------------------------------------------
-- reg_file.vhd
--------------------------------------------------------------------------------
-- Banco de registros y decodificador de "bridge": la interfaz entre el PC y la
-- FPGA. El PC accede por una ventana de palabras de 32 bits (indices). Este
-- bloque traduce cada indice a su destino:
--
--   indice 0           -> identificacion (version/fecha), solo lectura
--   indices 2, 3       -> strobes de latch/clear de los contadores CLKCTL
--   indices 6..105     -> registros de configuracion (RW, con readback) y de
--                         estado (RO). El +6 reproduce register_increment=6.
--   indices 400..431   -> ventana de escritura a la BRAM de secuencia (Alice/Bob)
--   indices 500..507   -> ventana de escritura a la BRAM de formas de onda (Alice)
--   indice 810         -> escritura secuencial a la BRAM de squashing (Bob)
--
-- El readback de los registros de configuracion es OBLIGATORIO: el software hace
-- read-modify-write (bridge_io.write lee, modifica un campo y reescribe). Si un
-- registro de config no devolviera su valor, se corromperian los campos vecinos.
--
-- Interfaz con el host: se modela como el par pci_read/pci_write del sistema
-- original (una escritura y una lectura sincronas de 32 bits con "enable"). En
-- el sistema real esto lo genera la IP XDMA/Xillybus a partir de AXI-Lite; aqui
-- lo dejamos como un puerto simple para poder simularlo y para desacoplar el
-- banco del transporte concreto.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reg_file is
  generic (
    G_VERSION : std_logic_vector(31 downto 0) := x"1A_07_18_01";  -- AA MM DD VV
    G_CFG_LO  : natural := 6;     -- primer indice de configuracion (RW)
    G_CFG_HI  : natural := 63;    -- ultimo indice de configuracion (RW)
    G_ST_LO   : natural := 64;    -- primer indice de estado (RO)
    G_ST_HI   : natural := 105    -- ultimo indice de estado (RO)
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;

    ---------------------------------------------------------------------
    -- Interfaz host (estilo pci_read / pci_write)
    ---------------------------------------------------------------------
    wr_en      : in  std_logic;                       -- pulso de escritura
    wr_addr    : in  unsigned(11 downto 0);           -- indice (0..4095)
    wr_data    : in  std_logic_vector(31 downto 0);

    rd_en      : in  std_logic;                       -- pulso de lectura
    rd_addr    : in  unsigned(11 downto 0);
    rd_data    : out std_logic_vector(31 downto 0);
    rd_valid   : out std_logic;                       -- rd_data valido (1 ciclo)

    ---------------------------------------------------------------------
    -- Registros de configuracion hacia la logica de usuario (troceo por campo
    -- se hace fuera; aqui se exponen las palabras completas)
    ---------------------------------------------------------------------
    cfg_out    : out std_logic_vector(32*(G_CFG_HI-G_CFG_LO+1)-1 downto 0);

    ---------------------------------------------------------------------
    -- Registros de estado desde la logica de usuario (RO para el host)
    ---------------------------------------------------------------------
    st_in      : in  std_logic_vector(32*(G_ST_HI-G_ST_LO+1)-1 downto 0);

    ---------------------------------------------------------------------
    -- Strobes de los contadores CLKCTL (indices 2 y 3), un ciclo
    ---------------------------------------------------------------------
    latch_stb  : out std_logic;
    clear_stb  : out std_logic;

    ---------------------------------------------------------------------
    -- Ventana de escritura a la BRAM de secuencia (400..431)
    ---------------------------------------------------------------------
    seq_we     : out std_logic;
    seq_addr   : out unsigned(4 downto 0);            -- 0..31
    seq_data   : out std_logic_vector(31 downto 0);

    ---------------------------------------------------------------------
    -- Ventana de escritura a la BRAM de formas de onda (500..507)
    ---------------------------------------------------------------------
    wave_we    : out std_logic;
    wave_addr  : out unsigned(2 downto 0);            -- 0..7
    wave_data  : out std_logic_vector(31 downto 0);

    ---------------------------------------------------------------------
    -- Escritura secuencial a la BRAM de squashing (indice 810)
    ---------------------------------------------------------------------
    squash_we    : out std_logic;
    squash_clear : out std_logic;                     -- reinicia el puntero
    squash_data  : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of reg_file is

  constant N_CFG : natural := G_CFG_HI - G_CFG_LO + 1;
  constant N_ST  : natural := G_ST_HI  - G_ST_LO  + 1;

  type word_arr is array (natural range <>) of std_logic_vector(31 downto 0);
  signal cfg : word_arr(0 to N_CFG-1) := (others => (others => '0'));

  signal w2, w3       : std_logic := '0';
  signal w2_d, w3_d   : std_logic := '0';

begin

  ------------------------------------------------------------------------
  -- Escritura: decodifica el indice y dirige el dato a su destino
  ------------------------------------------------------------------------
  process(clk)
    variable a : natural;
  begin
    if rising_edge(clk) then
      -- valores por defecto de los strobes/ventanas (un ciclo)
      latch_stb    <= '0';
      clear_stb    <= '0';
      seq_we       <= '0';
      wave_we      <= '0';
      squash_we    <= '0';
      squash_clear <= '0';

      if rst = '1' then
        cfg  <= (others => (others => '0'));
        w2   <= '0';  w3   <= '0';
        w2_d <= '0';  w3_d <= '0';
      else
        if wr_en = '1' then
          a := to_integer(wr_addr);

          if a = 2 then
            w2 <= wr_data(0);
          elsif a = 3 then
            w3 <= wr_data(0);
          elsif a >= G_CFG_LO and a <= G_CFG_HI then
            cfg(a - G_CFG_LO) <= wr_data;
          elsif a >= 400 and a <= 431 then
            seq_we   <= '1';
            seq_addr <= to_unsigned(a - 400, 5);
            seq_data <= wr_data;
          elsif a >= 500 and a <= 507 then
            wave_we   <= '1';
            wave_addr <= to_unsigned(a - 500, 3);
            wave_data <= wr_data;
          elsif a = 810 then
            squash_we   <= '1';
            squash_data <= wr_data;
          end if;
        end if;

        -- strobes por flanco de subida de las palabras 2 y 3
        -- (el software escribe 1 y luego 0; generamos un pulso en el 0->1)
        w2_d <= w2;
        w3_d <= w3;
        if w2 = '1' and w2_d = '0' then latch_stb <= '1'; end if;
        if w3 = '1' and w3_d = '0' then clear_stb <= '1'; end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------
  -- Lectura: version, config (readback) o estado
  ------------------------------------------------------------------------
  process(clk)
    variable a : natural;
  begin
    if rising_edge(clk) then
      rd_valid <= '0';
      if rst = '1' then
        rd_data  <= (others => '0');
      elsif rd_en = '1' then
        a := to_integer(rd_addr);
        rd_valid <= '1';
        if a = 0 then
          rd_data <= G_VERSION;
        elsif a >= G_CFG_LO and a <= G_CFG_HI then
          rd_data <= cfg(a - G_CFG_LO);                       -- readback
        elsif a >= G_ST_LO and a <= G_ST_HI then
          rd_data <= st_in(32*(a - G_ST_LO) + 31 downto 32*(a - G_ST_LO));
        else
          rd_data <= (others => '0');
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------
  -- Exposicion de la config a la logica de usuario
  ------------------------------------------------------------------------
  gen_cfg : for i in 0 to N_CFG-1 generate
    cfg_out(32*i + 31 downto 32*i) <= cfg(i);
  end generate;

end architecture;
