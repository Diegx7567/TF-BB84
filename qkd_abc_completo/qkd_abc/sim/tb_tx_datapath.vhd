-- tb_tx_datapath: carga una secuencia de 256 estados y una tabla de formas de
-- onda con patrones distinguibles por (estado,linea); deja correr el pipeline
-- y compara lane_word contra un modelo bit a bit durante varias vueltas
-- completas de secuencia, en las 4 combinaciones {msb_first, inv}.
-- La latencia del DUT se mide automaticamente buscando el alineamiento.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_tx_datapath is end entity;
architecture sim of tb_tx_datapath is
  constant NL : natural := 5;                        -- lineas
  signal clk_host, clk_tx : std_logic := '0';
  signal seq_we : std_logic := '0';
  signal seq_addr : unsigned(4 downto 0) := (others=>'0');
  signal seq_data : std_logic_vector(31 downto 0) := (others=>'0');
  signal wave_we : std_logic := '0';
  signal wave_addr : unsigned(2 downto 0) := (others=>'0');
  signal wave_data : std_logic_vector(31 downto 0) := (others=>'0');
  signal clear, enable : std_logic := '0';
  signal use_fixed : std_logic := '1';
  signal msb_first : std_logic := '0';
  signal inv : std_logic_vector(NL-1 downto 0) := (others=>'0');
  signal ch : unsigned(2 downto 0) := (others=>'0');
  signal lane_word : std_logic_vector(NL*64-1 downto 0);
  signal frame_pulse : std_logic;
  signal sym_cnt_out : unsigned(7 downto 0);

  -- modelo en el TB ----------------------------------------------------------
  type seq_t is array (0 to 255) of integer range 0 to 5;
  signal ref_seq : seq_t;
  -- patron de referencia por (estado, linea): valores elegidos para que la
  -- inversion temporal (rev16) cambie el valor (no palindromos)
  function pat(st, ln : integer) return std_logic_vector is
    variable v : unsigned(15 downto 0);
  begin
    v := to_unsigned((st*4099 + ln*257 + 7) mod 65536, 16);
    v(0) := '1'; v(15) := '0';                       -- asegura no-palindromo
    return std_logic_vector(v);
  end function;
  function rev16(v : std_logic_vector(15 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0);
  begin
    for i in 0 to 15 loop r(i) := v(15-i); end loop;
    return r;
  end function;
begin
  clk_host <= not clk_host after 4 ns;               -- 125 MHz (host)
  clk_tx   <= not clk_tx   after 1600 ps;            -- 312,5 MHz (tx)

  dut : entity work.tx_datapath generic map (N_LANES => NL)
    port map (clk_host=>clk_host, seq_we=>seq_we, seq_addr=>seq_addr,
              seq_data=>seq_data, wave_we=>wave_we, wave_addr=>wave_addr,
              wave_data=>wave_data, clk_tx=>clk_tx, clear=>clear,
              enable=>enable, use_fixed=>use_fixed, msb_first=>msb_first,
              inv=>inv, ch0=>ch, ch1=>ch, ch2=>ch, ch3=>ch,
              lane_word=>lane_word, frame_pulse=>frame_pulse,
              sym_cnt_out=>sym_cnt_out);

  main : process
    variable lfsr : unsigned(15 downto 0) := x"5A5A";
    variable word : unsigned(31 downto 0);
    variable st   : integer;
    -- comprueba una configuracion (msb, inv) durante n_words palabras
    procedure check_config(msbv : std_logic; invv : std_logic;
                           tag : string) is
      variable exp    : std_logic_vector(NL*64-1 downto 0);
      variable p      : std_logic_vector(15 downto 0);
      variable lat    : integer := -1;
      variable base_s : integer;                     -- primer simbolo esperado
      variable good   : boolean;
      variable fails  : integer := 0;
    begin
      msb_first <= msbv;
      inv <= (others => invv);
      -- reinicia el origen para conocer la fase absoluta
      wait until rising_edge(clk_tx); clear <= '1';
      wait until rising_edge(clk_tx); clear <= '0'; enable <= '1';
      -- deja llenar el pipeline
      for k in 0 to 9 loop wait until rising_edge(clk_tx); end loop;
      -- mide la latencia: la salida actual corresponde a los simbolos
      -- (sym_cnt_out - 4*lat) .. +3, prueba lat = 1..8
      for trial in 1 to 8 loop
        base_s := (to_integer(sym_cnt_out) - 4*trial) mod 256;
        good := true;
        for L in 0 to NL-1 loop
          for s in 0 to 3 loop
            p := pat(ref_seq((base_s+s) mod 256), L);
            if msbv='1' then p := rev16(p); end if;
            if invv='1' then p := not p; end if;
            if lane_word(L*64+16*s+15 downto L*64+16*s) /= p then
              good := false;
            end if;
          end loop;
        end loop;
        if good and lat < 0 then lat := trial; end if;
      end loop;
      assert lat > 0 report "sin latencia valida en "&tag severity error;
      if lat < 0 then report "TEST FAILED" severity failure; end if;
      -- verifica 200 palabras (3+ vueltas de secuencia) con esa latencia
      for w in 0 to 199 loop
        wait until rising_edge(clk_tx);
        wait for 100 ps;
        base_s := (to_integer(sym_cnt_out) - 4*lat) mod 256;
        for L in 0 to NL-1 loop
          for s in 0 to 3 loop
            p := pat(ref_seq((base_s+s) mod 256), L);
            if msbv='1' then p := rev16(p); end if;
            if invv='1' then p := not p; end if;
            if lane_word(L*64+16*s+15 downto L*64+16*s) /= p then
              fails := fails + 1;
            end if;
          end loop;
        end loop;
      end loop;
      enable <= '0';
      if fails /= 0 then
        report "FALLOS en "&tag&": "&integer'image(fails) severity error;
        report "TEST FAILED" severity failure;
      else
        report "config "&tag&" OK (lat="&integer'image(lat)&")" severity note;
      end if;
    end procedure;
  begin
    -- 1) genera y carga la secuencia de referencia (256 estados 0..5)
    for i in 0 to 255 loop
      lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      ref_seq(i) <= to_integer(lfsr(7 downto 0)) mod 6;
    end loop;
    wait for 20 ns;
    for w in 0 to 31 loop                            -- 32 palabras via "host"
      word := (others=>'0');
      for ii in 0 to 7 loop
        st := ref_seq(w*8+ii);
        word := word or shift_left(to_unsigned(st,32), 3*(7-ii));
      end loop;
      wait until rising_edge(clk_host);
      seq_addr <= to_unsigned(w,5);
      seq_data <= std_logic_vector(word);
      seq_we <= '1';
      wait until rising_edge(clk_host);
      seq_we <= '0';
    end loop;
    -- 2) carga la tabla de formas de onda: celda a celda
    for st_i in 0 to 5 loop
      for ln in 0 to NL-1 loop
        wait until rising_edge(clk_host);
        wave_addr <= to_unsigned(st_i,3);
        wave_data <= "0000000000000" & std_logic_vector(to_unsigned(ln,3))
                     & pat(st_i, ln);
        wave_we <= '1';
        wait until rising_edge(clk_host);
        wave_we <= '0';
      end loop;
    end loop;
    wait for 50 ns;
    -- 3) las cuatro configuraciones
    check_config('0','0',"normal");
    check_config('1','0',"msb_first");
    check_config('0','1',"invertido");
    check_config('1','1',"msb+inv");
    report "TEST PASSED" severity note;
    wait;
  end process;
end architecture;
