"""load.py — cargadores de contenido: secuencia, formas de onda, squashing.

QUE ES:      las tres funciones que llenan las memorias del gateware, con los
             MISMOS formatos que el software original (verificados en
             tb_seq_bram, tb_tx_datapath y tb_squash_lut).
"""
from .regs import IDX_SEQ_BASE, IDX_WAVE_BASE, IDX_SQUASH

def write_fixed_sequence(be, states):
    """Carga la secuencia fija de 256 estados (0..5) en la ventana 400..431.

    Empaquetado identico a write_fixed_sequence_with_qubit_mapping:
    la palabra w lleva los estados w*8..w*8+7, el primero en los bits [23:21].
    """
    assert len(states) == 256, "la secuencia es de 256 estados"
    for w in range(32):                              # 32 palabras
        word = 0
        for ii in range(8):                          # 8 estados por palabra
            st = states[w*8 + ii] & 0b111            # 3 bits por estado
            word |= st << (3 * (7 - ii))             # ii=0 en bits altos
        be.write(IDX_SEQ_BASE + w, word)             # una escritura por palabra

def write_waveform(be, state, lane, pattern16):
    """Escribe la forma de onda (16 muestras) de una (estado, linea).

    El indice es 500+estado y la palabra empaqueta [18:16]=linea,
    [15:0]=patron, siendo el bit 0 la muestra MAS ANTIGUA (primera en el
    tiempo). Ejemplos del sistema (una muestra=50 ps, un bin=2 muestras):
      z0 (pulso temprano, bin 0)  -> 0x0003 (muestras 0-1)
      z1 (pulso tardio,   bin 2)  -> 0x0030 (muestras 4-5)
      x0 (ambos pulsos)           -> 0x0033
      reloj del DAC (8+8)         -> 0x00FF
    """
    word = ((lane & 0b111) << 16) | (pattern16 & 0xFFFF)
    be.write(IDX_WAVE_BASE + (state & 0b111), word)

def load_default_waveforms(be, n_lanes=5):
    """Carga el juego por defecto: z0/z1/x0 en las lineas de datos y el
    patron de reloj en la ultima linea, para los 6 estados."""
    base = {0: 0x0003, 1: 0x0030, 2: 0x0033,   # z0/z1/x0 con decoy 0
            3: 0x0003, 4: 0x0030, 5: 0x0033}   # idem con decoy 1
    for st in range(6):
        for lane in range(n_lanes - 1):        # lineas de datos
            write_waveform(be, st, lane, base[st])
        write_waveform(be, st, n_lanes - 1, 0x00FF)  # linea de reloj DAC

def load_squashing_table(be, rows, clear_field=None):
    """Carga las 256 filas de 10 bits por el mecanismo secuencial (810).

    'rows' es la lista de 256 enteros que genera toro_squashing_table (o el
    fichero de tabla ya calculado). Si se pasa clear_field (el campo que el
    reg_file convierte en squash_clear), se pulsa antes para ir a la fila 0.
    """
    assert len(rows) == 256, "la tabla es de 256 filas"
    if clear_field is not None:
        clear_field.pulse()                    # puntero de carga a 0
    for row in rows:                           # el puntero autoincrementa:
        be.write(IDX_SQUASH, row & 0x3FF)      # una escritura = una fila

def identity_squash_rows():
    """Tabla 'identidad' de banco de pruebas: cada bit de entrada resuelto
    a su bit de salida, sin sorteo (suficiente con un clic por simbolo).
    Direccion: [7]=Z1 [6]=Z0 [5]=X2 [4]=X1 [3]=X0; fila: [9..5] = idem."""
    rows = []
    for a in range(256):
        row = 0
        row |= ((a >> 7) & 1) << 9             # Z1
        row |= ((a >> 6) & 1) << 8             # Z0
        row |= ((a >> 5) & 1) << 7             # X2
        row |= ((a >> 4) & 1) << 6             # X1
        row |= ((a >> 3) & 1) << 5             # X0
        rows.append(row)
    return rows
