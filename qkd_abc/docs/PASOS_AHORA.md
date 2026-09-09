# Qué tienes que hacer, paso a paso

**Respuestas rápidas a tus dudas:**

- **¿Está PCIe?** Sí. La IP XDMA se instancia y se cablea sola por TCL.
- **¿Tengo que crear los GTY?** **No, todavía no.** La fase 1 se sintetiza
  sin ningún GTY, a propósito. Si metes PCIe y GTY a la vez y algo falla, no
  sabes cuál de los dos es. Los GTY son la fase 2.
- **¿Qué copio a mano?** Nada de código. Solo descomprimes el ZIP.

---

## PASO 1 — Descomprimir (2 minutos)

Descomprime `qkd_abc_completo.zip` en una ruta **sin espacios ni acentos**
(Vivado sufre con ellos). Por ejemplo `C:/proyectos/qkd_abc` o
`~/proyectos/qkd_abc`.

Comprueba que existe `qkd_abc/vivado/` con estos ficheros:

```
00_run_sim.tcl        01_create_ab.tcl      02_build_bd_ab.tcl
03_run_build.tcl      TODO_EN_UNO_ab.tcl    kcu116_fase1.xdc
```

---

## PASO 2 — Compilar (un solo comando)

Abre Vivado, y en la **consola TCL** (pestaña de abajo):

```tcl
cd C:/proyectos/qkd_abc/vivado
set argv nodo_a
source TODO_EN_UNO_ab.tcl
```

(en Windows usa `/` en las rutas TCL aunque sea Windows)

O sin abrir la GUI, desde una terminal:

```bash
cd ~/proyectos/qkd_abc/vivado
vivado -mode batch -source TODO_EN_UNO_ab.tcl -tclargs nodo_a
```

Esto hace **todo**: crea el proyecto, añade las 14 fuentes VHDL como VHDL-2008,
instancia XDMA y MMCM, aplica el XDC verificado, monta el Block Design, y
lanza síntesis + implementación + bitstream.

**Tarda 20–40 minutos**, la mayor parte implementando el XDMA. Es normal.

**Al terminar debe decir:**
```
>>> LISTO. Bitstream en ./nodo_a/nodo_a.runs/impl_1/bd_ab_wrapper.bit
```

Y va a imprimir una lista de relojes: **cópiamela y pégamela**, la necesito
para afinar las restricciones de CDC (los nombres reales dependen de cómo
instancie Vivado el MMCM).

---

## PASO 3 — Comprobar antes de tocar la placa

Si quieres validar la lógica antes (opcional pero recomendable, 1 minuto):

```tcl
set argv tb_axil_bridge
source 00_run_sim.tcl
```

Debe imprimir `TEST PASSED`. Ese test hace escrituras y lecturas AXI-Lite
contra el diseño real y comprueba el readback, que es justo lo que vas a
probar luego desde el PC.

---

## PASO 4 — Programar la placa

1. **Hardware Manager** → `Open Target` → `Auto Connect` → `Program Device`
   → elige `bd_ab_wrapper.bit`.
2. **Apaga y enciende el PC** (reinicio completo, no *reboot* caliente).
   PCIe solo enumera dispositivos durante el arranque: si programas la FPGA
   con el PC encendido, el sistema no la verá.

> Si tu placa está en un PC distinto al que tiene Vivado, copia el `.bit` y
> prográmalo allí, o carga el bitstream en la flash de la KCU116 para que
> arranque sola.

---

## PASO 5 — Ver la tarjeta desde el sistema

```bash
lspci | grep -i xilinx
```

Debe aparecer una línea. Si no aparece: no llegó a programarse antes del
arranque, o el bitstream no incluye el XDMA.

Luego instala el driver XDMA de Xilinx (repo `Xilinx/dma_ip_drivers`,
carpeta `XDMA/linux-kernel`):

```bash
cd dma_ip_drivers/XDMA/linux-kernel/xdma
make && sudo make install
sudo modprobe xdma
ls /dev/xdma*          # debe existir /dev/xdma0_user
```

---

## PASO 6 — El hito: leer la versión

```bash
cd ~/proyectos/qkd_abc/sw/c && make
cd ../python && python3 tools/selftest.py --node ab
```

**Resultado esperado:**

```
[1] versión del gateware: 0x1A081002
```

Si sale eso, **la fase 1 está terminada**: PCIe, AXI-Lite, el puente y el banco
de registros funcionan de punta a punta. Todo lo demás (cargar secuencias,
formas de onda, leer histogramas) es llamar funciones que ya están escritas y
verificadas.

Si sale `0x00000000` o basura: el enlace PCIe está pero el BAR no apunta donde
debe. Mándame la salida y lo miramos.

---

## Qué NO tienes que hacer todavía

- ❌ Crear GTY / Transceiver Wizard
- ❌ Conectar nada al FMC o a los SFP
- ❌ Preocuparte por los 156,25 MHz o el Si570
- ❌ Tocar los `.vhd`

Todo eso es fase 2, y solo tiene sentido cuando el paso 6 dé la versión.

---

## Resumen de las fases

| Fase | Qué prueba | Hardware |
|---|---|---|
| **1 (ahora)** | PCIe + registros | Solo la KCU116 en el PC |
| 2 | GTY TX + time-bins reales | + loopback SFP |
| 3 | Las 4 líneas del DAC + deskew | + FMC X4SMA puenteado |
| 4 | Deskew entre quads | + cables SMA iguales |
| 5 | Canal de servicio entre chips | + Nexys Video |
| 6–7 | Sistema de 3 nodos | Faltan 2 KCU116 |
