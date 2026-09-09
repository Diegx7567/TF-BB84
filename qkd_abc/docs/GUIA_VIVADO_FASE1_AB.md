# Guía paso a paso — Vivado, FASE 1 (nodos A y B)

**Objetivo de esta fase:** que el PC vea la FPGA por PCIe, lea la versión en el
índice 0 y escriba/lea registros. Sin GTY todavía. Cuando esto funcione, todo
el resto se apoya en terreno firme.

No tienes que copiar código a mano: descomprime el ZIP y los scripts añaden
los ficheros solos.

---

## Paso 0 — Preparar la carpeta

Descomprime `qkd_abc_completo.zip` donde quieras, por ejemplo en
`C:\proyectos\qkd_abc` o `~/proyectos/qkd_abc`. Debe quedarte:

```
qkd_abc/
├── common/hdl/     ← 9 ficheros .vhd
├── node_ab/hdl/    ← 5 ficheros .vhd
├── node_c/hdl/     ← 6 ficheros .vhd
├── sim/            ← 18 testbenches
├── vivado/         ← los 4 scripts TCL de esta guía
├── sw/
└── docs/
```

**Regla importante:** ejecuta siempre los TCL **desde la carpeta `vivado/`**,
porque las rutas a las fuentes son relativas (`../common/hdl/...`).

---

## Paso 1 — Crear el proyecto (todo en TCL)

En Vivado, abre la consola TCL (pestaña inferior) y escribe:

```tcl
cd C:/proyectos/qkd_abc/vivado
set argv nodo_a
source 01_create_ab.tcl
```

(en Windows usa barras normales `/` en las rutas de TCL, aunque sea Windows)

O desde una terminal, sin abrir la GUI:

```bash
cd ~/proyectos/qkd_abc/vivado
vivado -mode batch -source 01_create_ab.tcl -tclargs nodo_a
```

**Qué hace:** crea el proyecto para XCKU5P, añade las 13 fuentes VHDL marcadas
como **VHDL-2008** (imprescindible: el código usa tipos sin restringir), pone
`ab_synth_top` como top, mete los testbenches en el fileset de simulación,
instancia las IP XDMA y MMCM, y escribe un XDC inicial.

**Qué deberías ver:** `### Proyecto nodo_a creado.` y ningún error rojo.

> ⚠️ **Verifica los pines del XDC.** Los `PACKAGE_PIN` que he puesto para
> `sysclk_p/n` (AK17/AK16) son los típicos de la KCU116, pero **contrástalos
> con el XDC maestro de tu placa** (Xilinx lo distribuye en el Board Store, o
> mira el esquemático). Un pin mal puesto no falla en síntesis: falla en placa
> y cuesta horas.

---

## Paso 2 — Comprobar que simula dentro de Vivado

Antes de sintetizar, confirma que el entorno está bien montado:

```tcl
set argv tb_ab_top_smoke
source 00_run_sim.tcl
```

En la consola debe aparecer `TEST PASSED`. Si aparece, tu proyecto tiene las
fuentes bien y en VHDL-2008. (Este mismo test ya pasa en GHDL; aquí solo
confirmas que Vivado lo lee igual.)

Prueba también el del puente AXI, que es el que importa en esta fase:

```tcl
set argv tb_axil_bridge
source 00_run_sim.tcl
```

---

## Paso 3 — Block Design: unir XDMA + MMCM + nuestro top

```tcl
source 02_build_bd_ab.tcl
```

**Qué hace:** crea el Block Design, saca los puertos de PCIe al exterior,
conecta `M_AXI_LITE` del XDMA a nuestro `s_axi`, cablea `axi_aclk`/`axi_aresetn`,
enchufa el MMCM a `clk_tx`, asigna el mapa de direcciones y genera el wrapper.

**Si algo falla aquí**, lo más probable es el nombre de la interfaz AXI. Abre
el Block Design (`Open Block Design`) y conecta a mano `M_AXI_LITE` con el
puerto `s_axi` del bloque `bd_ab_top`: es un solo cable y Vivado lo autocompleta.

---

## Paso 4 — Sintetizar y generar el bitstream

```tcl
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```

o en batch: `vivado -mode batch -source 03_run_build.tcl -tclargs nodo_a`

**Qué mirar al terminar:**
- `timing_summary.rpt` → **WNS positivo**. Si el camino crítico está en el
  barrel shifter del `word_bit_delay`, avísame: la solución está documentada
  (registrarlo en dos etapas).
- `utilization.rpt` → deberías ir muy holgado en un XCKU5P.

---

## Paso 5 — Programar y probar desde el PC

1. Programa el bitstream (Hardware Manager) y **reinicia el PC** — PCIe solo
   enumera dispositivos en el arranque.
2. Comprueba que el sistema ve la tarjeta: `lspci | grep Xilinx`
3. Instala el driver XDMA de Xilinx (repositorio `dma_ip_drivers`), carga el
   módulo y verifica que existe `/dev/xdma0_user`.
4. Compila el shim y lanza el autotest:

```bash
cd qkd_abc/sw/c && make
cd ../python && python3 tools/selftest.py --node ab
```

**Resultado esperado:** `[1] versión del gateware: 0x1A081002`.

Esa línea es el hito de la fase 1: significa que PCIe, AXI-Lite, el puente y el
banco de registros funcionan de punta a punta. A partir de ahí, escribir la
secuencia y las formas de onda es solo llamar a las funciones que ya están
escritas y verificadas.

---

## Qué viene después (fase 2)

Cuando el paso 5 dé la versión correcta:

1. Añadir el **GTY Transceiver Wizard**: 5 canales TX a 20 Gb/s raw, datapath
   de 64 bits, `TXUSRCLK2` a 312,5 MHz, referencia de 156,25 MHz.
2. Sustituir el MMCM: `clk_tx` pasa a ser `TXUSRCLK2` del GTY.
3. Conectar `gty_txdata` a los `TXDATA` (los 5×64 bits ya salen en el orden
   correcto, con SwitchMSB e inversión aplicados).
4. Probar con el **loopback SFP**: paso 2 de la escalera de pruebas, donde ya
   ves time-bins reales en el histograma.

Dime cuando tengas el resultado del paso 1 (o el error que salga) y seguimos.
