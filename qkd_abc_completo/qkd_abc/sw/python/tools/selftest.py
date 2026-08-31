#!/usr/bin/env python3
"""selftest.py — autotest de un par transmisor/receptor.

QUE ES:      el guion de arranque que ejecuta, en orden, los mismos pasos que
             el TB de humo del gateware, pero desde el PC real:
             version -> carga -> habilitacion -> lectura -> QBER.
COMO SE USA: python3 selftest.py --node ab     (en el PC de A o B)
             python3 selftest.py --node c      (en el PC de C)
             anhade --simulate para probar el flujo sin placa.
"""
import argparse, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from qkd.backend import Backend
from qkd.regs import AbRegs, CRegs, IDX_VERSION
from qkd.load import (write_fixed_sequence, load_default_waveforms,
                      load_squashing_table, identity_squash_rows)
from qkd.measure import read_histogram, read_coincidence_matrix, qber_z

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--node", choices=["ab", "c"], required=True)
    ap.add_argument("--simulate", action="store_true")
    args = ap.parse_args()

    be = Backend(simulate=args.simulate)         # transporte (XDMA o simulado)

    # paso 1: la version identifica el bitstream (y prueba el enlace PCIe)
    ver = be.read(IDX_VERSION)
    print(f"[1] version del gateware: 0x{ver:08X}")

    if args.node == "ab":
        r = AbRegs(be)
        # paso 2: cargar secuencia fija (todo z0mu0 para el banco) y formas
        write_fixed_sequence(be, [0]*256)
        load_default_waveforms(be)
        print("[2] secuencia y formas de onda cargadas")
        # paso 3: configurar y arrancar
        r.msb_first.set(1)                        # b0 primero en el tiempo
        r.use_fixed.set(1)                        # secuencia fija
        r.clear_seq.pulse()                       # origen de simbolo a 0
        r.enable.set(1)                           # marcha
        print("[3] transmisor en marcha")
        # paso 4: comprobar que el dominio tx esta vivo (frecuencimetro)
        be.write(2, 1)                            # rearme CLKCTL (como el
        be.write(3, 1)                            # software original)
        print(f"[4] clkctl_tx = {r.clkctl_tx.get()} (tras la ventana)")
        print(f"    tramas emitidas: {r.frame_count.get()}")

    else:
        r = CRegs(be)
        # paso 2: secuencia esperada + tabla de squashing
        write_fixed_sequence(be, [0]*256)
        load_squashing_table(be, identity_squash_rows())
        print("[2] secuencia esperada y tabla de squashing cargadas")
        # paso 3: configurar y arrancar
        r.filter_edge.set(1)                      # filtro de flanco
        r.clear.pulse()                           # contadores a 0
        r.phase_clr.pulse()                       # ancla de trama
        r.enable.set(1)
        print("[3] receptor en marcha")
        # paso 4: histograma del canal Z y QBER de la matriz
        h0 = read_histogram(r, 0)
        print(f"[4] histograma canal 0 (Z): max={max(h0)} en bin {h0.index(max(h0))}")
        m = read_coincidence_matrix(r)
        q, err, tot = qber_z(m)
        print(f"[5] QBER-Z = {q:.4f}  ({err} errores / {tot} comprobaciones)")

if __name__ == "__main__":
    main()
