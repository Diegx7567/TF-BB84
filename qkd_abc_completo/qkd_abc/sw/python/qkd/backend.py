"""backend.py — carga del shim C y primitivas pci_read / pci_write.

QUE ES:      el unico punto del paquete que toca la biblioteca C.
PARA QUE:    aislar el transporte (XDMA hoy, Xillybus si se decide luego):
             el resto del paquete solo ve read(idx) / write(idx, val).
CONECTADO A: pcilib.so (sw/c) -> BAR del XDMA -> reg_file de la FPGA.
"""
import ctypes                    # FFI estandar de Python para llamar a C
import os

class Backend:
    def __init__(self, libpath: str = None, simulate: bool = False):
        # modo simulado: un diccionario hace de "FPGA" (para tests sin placa)
        self.simulate = simulate
        self._mem = {}                       # memoria del modo simulado
        if simulate:
            return
        # localiza la biblioteca junto a este fichero si no se indica ruta
        if libpath is None:
            libpath = os.path.join(os.path.dirname(__file__),
                                   "..", "..", "c", "pcilib.so")
        self.lib = ctypes.CDLL(os.path.abspath(libpath))   # carga el shim
        self.lib.pci_read.restype = ctypes.c_int           # int pci_read(int)
        self.lib.pci_read.argtypes = [ctypes.c_int]
        self.lib.pci_write.restype = ctypes.c_int          # int pci_write(int,int)
        self.lib.pci_write.argtypes = [ctypes.c_int, ctypes.c_int]

    def read(self, index: int) -> int:
        """Lee la palabra de 32 bits del indice dado (sin signo)."""
        if self.simulate:
            return self._mem.get(index, 0)
        return self.lib.pci_read(index) & 0xFFFFFFFF  # a sin-signo

    def write(self, index: int, value: int) -> None:
        """Escribe la palabra de 32 bits del indice dado."""
        if self.simulate:
            self._mem[index] = value & 0xFFFFFFFF
            return
        self.lib.pci_write(index, value & 0xFFFFFFFF)
