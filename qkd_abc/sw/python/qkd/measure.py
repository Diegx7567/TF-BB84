"""measure.py — lecturas: histogramas, matriz de coincidencias y QBER.

QUE ES:      las funciones de medida que el bucle de estadisticas llama cada
             bloque, replicando las formulas del original
             (StatisticsFormulasToro): QBER-Z = errores / comprobaciones.
"""

def read_histogram(cregs, channel):
    """Devuelve los 64 bins del canal (0..3) leyendo por hist_sel/hist_addr."""
    cregs.hist_sel.set(channel)                 # elige el canal
    bins = []
    for a in range(64):                         # bin a bin
        cregs.hist_addr.set(a)                  # direcciona
        bins.append(cregs.hist_data.get())      # y lee el dato
    return bins

def read_coincidence_matrix(cregs):
    """Devuelve la matriz 5x6 (filas=outcome, columnas=estado esperado)."""
    m = [[0]*6 for _ in range(5)]
    for c in range(30):                         # celda a celda
        cregs.coinc_idx.set(c)                  # direcciona
        m[c // 6][c % 6] = cregs.coinc_data.get()
    return m

def qber_z(matrix):
    """QBER de la base Z a partir de la matriz.

    outcomes: 0=Z0 1=Z1; estados: 0/3=z0(mu0/mu1), 1/4=z1(mu0/mu1).
    Acierto: (Z0,z0*) o (Z1,z1*). Error: (Z0,z1*) o (Z1,z0*).
    Las columnas x0 (2/5) no cuentan: son cruce de base, se descartan
    en el sifting igual que en el sistema original.
    """
    ok  = matrix[0][0] + matrix[0][3] + matrix[1][1] + matrix[1][4]
    err = matrix[0][1] + matrix[0][4] + matrix[1][0] + matrix[1][3]
    total = ok + err
    return (err / total) if total else float("nan"), err, total
