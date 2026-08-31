# Sistema QKD time-bin de tres nodos (A, B → C) sobre KCU116

Réplica completa del gateware + software del sistema `control_qkd_toro`,
extendida a la topología de tres nodos: **A y B transmiten** (arquitectura
Alice, 5 líneas a 20 Gb/s) y **C recibe y compara** (4 canales a 20 GS/s,
squashing, matriz de coincidencias). Cada módulo VHDL está comentado línea a
línea y verificado con un testbench autocomprobante. **Regresión: 16/16
TEST PASSED** (log en `docs/regresion_16de16.txt`).

```
qkd_abc/
├── common/hdl/      módulos compartidos por los tres nodos
├── node_ab/hdl/     transmisor (idéntico para A y B)
├── node_c/hdl/      receptor / comparador
├── sim/             17 testbenches (GHDL, VHDL-2008)
├── sw/c/            pcilib_shim.c + Makefile (transporte XDMA)
├── sw/python/       paquete qkd + tools/selftest.py
├── vivado/          create_project_ab.tcl / create_project_c.tcl
├── docs/            figuras + log de regresión
└── run_all_tests.sh suite completa
```

## Convenios del sistema (válidos en TODOS los módulos)

- **1 muestra = 50 ps** (20 GS/s por línea GTY). `bit(0)` de cada palabra es la
  muestra **más antigua**.
- **1 símbolo = 800 ps** = 16 muestras = 8 bins de 100 ps. Z0 = bin 0
  (temprano), Z1 = bin 2 (tardío), X0 = ambos; tras el interferómetro,
  X0/X1/X2 = bins 0/2/4.
- **Datapath de 64 bits a 312,5 MHz** = 4 símbolos por ciclo.
- **Secuencia = 256 estados de 3 bits**, empaquetados 8 por palabra con el
  primer estado en los bits [23:21] (formato exacto de
  `write_fixed_sequence_with_qubit_mapping`).
- **Estados**: z0μ0=0, z1μ0=1, x0μ0=2, z0μ1=3, z1μ1=4, x0μ1=5.
- El **readback** de los registros de configuración es obligatorio: el software
  hace read-modify-write campo a campo (clase `Field`/`bridge_io`).

## Mapa del bridge implementado por los tops

| Índice | Qué | Nodo |
|---|---|---|
| 0 | Versión (AA MM DD VV) | A/B/C |
| 2, 3 | Strobes CLKCTL (rearme de frecuencímetros) | A/B/C |
| 6 | Control: [0]=enable, [1]=use_fixed / filter_edge, [2]=SwitchMSB, [7:3]=inv, [8]=clear (flanco), [9]=phase_clr (flanco, solo C) | A/B, C |
| 9 | Umbrales del sorteo: z0_up[7:0], z1_up[15:8], dec0_up[23:16] | A/B |
| 14–16 | Delays (deskew), 2 campos de 11 bits por palabra | A/B (5), C (4) |
| 20 | [5:0]=hist_addr, [9:8]=hist_sel | C |
| 21 | [4:0]=coinc_idx | C |
| 70 | Estado: frame_count (A/B) / hist_data (C) | A/B, C |
| 71 | Estado: coinc_data | C |
| 73 | Estado: CLKCTL del dominio tx/rx | A/B/C |
| 400–431 | Ventana de secuencia (32×8 estados) | A/B/C |
| 500–507 | Ventana de formas de onda ([18:16]=línea, [15:0]=patrón) | A/B |
| 810 | Carga secuencial de la tabla de squashing (256×10) | C |

## Los bloques, en el orden del flujo de datos

**Transmisor (ab_top):** `reg_file` → (`prbs_gen` → `state_chooser` |
`seq_ram` interna) → `tx_datapath` (mux de fuente → `waveform_lut` →
SwitchMSB por símbolo → inversión por línea) → 5 × `word_bit_delay` →
GTY TXDATA. `frame_pulse` cada 256 símbolos (pseudo-address del canal de
servicio). Instrumentación: `clk_counter` del dominio tx.

**Receptor (c_top):** 4 × (GTY RXDATA → `word_bit_delay` → `edge_filter` →
`binner` → `histogram`). Canales 0 (Z) y 1 (X) forman la dirección
{Z1,Z0,X2,X1,X0,R2,R1,R0} con los bits R del `prbs_gen` → `squash_lut`
(4 puertos) → outcome → `coincidence_matrix` (30 contadores) contra la
`seq_bram` local (secuencia esperada, 4 lectores). CDC: `cdc_pulse` para los
strobes, doble FF para los niveles.

Cada fichero VHDL lleva en cabecera: QUÉ ES / PARA QUÉ / CÓMO SE USA /
CONECTADO A, y comentarios por línea en el cuerpo.

## Cómo ejecutar la verificación

```bash
sudo apt install ghdl          # o el binario de ghdl.github.io
./run_all_tests.sh             # 16 testbenches; todos deben decir TEST PASSED
```

Nota: `tb_word_bit_delay` es el más lento (historial de 400k muestras); dale
un par de minutos.

## Cómo llevarlo a las placas

1. **Proyectos**: `cd vivado && vivado -mode batch -source create_project_ab.tcl
   -tclargs nodo_a` (y `nodo_b`, `create_project_c.tcl`).
2. **IPs pendientes de wizard** (documentado también en los TCL):
   XDMA (AXI-Lite → puente wr/rd del top), GTY (A/B: 4 TX del quad FMC a
   20 Gb/s raw + SFP del gate; C: 4 RX **en el mismo quad**, RXUSRCLK2 común),
   y más adelante el canal de servicio a 2,5 Gb/s.
3. **Reloj**: referencia única de 156,25 MHz a ambos quads de cada placa.
   C es el maestro del sistema; en mesa, distribución eléctrica (fanout);
   entre salas, CDR + Si5328 con `EnableRecClk`.
4. **Software**: `cd sw/c && make`, luego
   `python3 sw/python/tools/selftest.py --node ab` (o `--node c`).
   El shim asume `/dev/xdma0_user` (driver XDMA de Xilinx cargado).

## Qué queda fuera de este paquete (siguiente iteración)

- Canal de servicio: framer 8b10b + FSM de arranque + pseudo-address
  (el `frame_pulse` ya existe; falta el enlace).
- XDC con pines reales del FMC HTG-X4SMA y del SFP.
- Integración del mapeo legado de histogramas (índices 200–263/300–363
  con lectura invertida 363−i) si se quiere compatibilidad total con la GUI
  original; los 4 canales ya son accesibles por hist_sel/hist_addr.
- La medida de fase A↔B (SYSMON / heterodino) y la estabilización del
  interferómetro: ver `docs/figuras/abc_f2_fase.png`.

## Errores reales cazados por los testbenches (léelo: es el valor de esto)

1. `histogram` perdía 1 cuenta por ventana (asignación del cierre pisaba los
   incrementos del mismo ciclo).
2. `ab_top`: rangos de retorno de función sin normalizar → bound check.
3. `c_top`: múltiples drivers desde `generate` → habría dado 'X'.
4. `c_top`/`ab_top`: offset de las palabras de estado (índice 71 ≠ palabra 1,
   es la palabra 7 con base 64) → el humo de C leyó "celda 0 vacía".
5. (Sesiones previas) `word_bit_delay`: barrel invertido, hazard
   read-during-write, latencia no uniforme.

Todos corregidos y cubiertos por la regresión.
