"""bridge.py — la clase de campo del bridge (replica de bridge_io).

QUE ES:      un campo = (indice base, desplazamiento, mascara). La escritura
             es read-modify-write: lee la palabra, sustituye SOLO los bits
             del campo y reescribe. Exactamente el patron del software
             original — y la razon por la que el reg_file DEBE devolver en
             lectura lo escrito (readback), verificado en tb_reg_file.
COMO SE USA: campo = Field(be, base=6, shift=3, width=5); campo.set(0b10110)
CONECTADO A: Backend (transporte) y al mapa de regs.py.
"""

class Field:
    def __init__(self, backend, base: int, shift: int = 0, width: int = 32):
        self.be = backend                 # transporte
        self.base = base                  # indice de la palabra
        self.shift = shift                # primer bit del campo
        self.mask = (1 << width) - 1      # mascara de 'width' bits

    def get(self) -> int:
        """Lee la palabra y extrae el campo."""
        word = self.be.read(self.base)               # palabra completa
        return (word >> self.shift) & self.mask      # solo el campo

    def set(self, value: int) -> None:
        """Read-modify-write: preserva los bits vecinos de la palabra."""
        word = self.be.read(self.base)               # 1) lee lo que hay
        word &= ~(self.mask << self.shift)           # 2) borra el campo
        word |= (value & self.mask) << self.shift    # 3) inserta el valor
        self.be.write(self.base, word)               # 4) reescribe

    def pulse(self) -> None:
        """Flanco 0->1->0 (los tops convierten el flanco en pulso interno)."""
        self.set(0)                                  # asegura nivel bajo
        self.set(1)                                  # flanco de subida
        self.set(0)                                  # vuelve a bajo
