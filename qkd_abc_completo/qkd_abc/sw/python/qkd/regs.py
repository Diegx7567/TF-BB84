"""regs.py — el mapa de indices y campos de ab_top y c_top.

QUE ES:      la transcripcion 1:1 de las cabeceras de ab_top.vhd y c_top.vhd.
             Si cambias un campo en el VHDL, cambialo aqui (y solo aqui).
"""
from .bridge import Field

# indices comunes -------------------------------------------------------------
IDX_VERSION      = 0        # version del gateware (AA MM DD VV)
IDX_LATCH        = 2        # strobe CLKCTL (rearme de frecuencimetros)
IDX_CLEAR_CNT    = 3        # strobe CLKCTL
IDX_SEQ_BASE     = 400      # ventana de secuencia: 32 palabras
IDX_WAVE_BASE    = 500      # ventana de formas de onda: 8 estados
IDX_SQUASH       = 810      # carga secuencial de la tabla de squashing
IDX_STATUS_BASE  = 64       # primera palabra de estado

class AbRegs:
    """Campos del transmisor (ab_top). Palabra 6 = control principal."""
    def __init__(self, be):
        self.be = be
        self.enable     = Field(be, 6, 0, 1)    # [0] marcha/paro
        self.use_fixed  = Field(be, 6, 1, 1)    # [1] secuencia fija / sorteo
        self.msb_first  = Field(be, 6, 2, 1)    # [2] SwitchMSB_S_regw
        self.inv        = Field(be, 6, 3, 5)    # [7:3] inversion por linea
        self.clear_seq  = Field(be, 6, 8, 1)    # [8] flanco = reinicio origen
        self.prob_z0_up   = Field(be, 9, 0, 8)  # umbrales del sorteo
        self.prob_z1_up   = Field(be, 9, 8, 8)
        self.prob_dec0_up = Field(be, 9, 16, 8)
        # delays de linea: palabra 14+L/2, campo bajo/alto de 11 bits
        self.delay = [Field(be, 14 + L//2, 16*(L % 2), 11) for L in range(5)]
        self.frame_count = Field(be, 70, 0, 32) # tramas emitidas (estado)
        self.clkctl_tx   = Field(be, 73, 0, 32) # frecuencimetro tx (estado)

class CRegs:
    """Campos del receptor (c_top)."""
    def __init__(self, be):
        self.be = be
        self.enable      = Field(be, 6, 0, 1)   # [0] marcha/paro
        self.filter_edge = Field(be, 6, 1, 1)   # [1] FilterByEdge
        self.clear       = Field(be, 6, 8, 1)   # [8] flanco = clear general
        self.phase_clr   = Field(be, 6, 9, 1)   # [9] flanco = ancla de trama
        # delays de canal: palabra 14+C/2, campo bajo/alto de 11 bits
        self.delay = [Field(be, 14 + C//2, 16*(C % 2), 11) for C in range(4)]
        self.hist_addr = Field(be, 20, 0, 6)    # bin a leer (0..63)
        self.hist_sel  = Field(be, 20, 8, 2)    # canal a leer (0..3)
        self.coinc_idx = Field(be, 21, 0, 5)    # celda de la matriz (0..29)
        self.hist_data  = Field(be, 70, 0, 32)  # dato del bin (estado)
        self.coinc_data = Field(be, 71, 0, 32)  # dato de la celda (estado)
        self.clkctl_rx  = Field(be, 73, 0, 32)  # frecuencimetro rx (estado)
