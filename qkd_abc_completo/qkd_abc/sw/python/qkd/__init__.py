"""Paquete qkd: acceso al gateware de los nodos A, B y C.

Replica el contrato del software original (bridge_io + indices del bridge)
sobre el shim pcilib.so. Modulos:
  backend  - carga de la biblioteca C (pci_read / pci_write)
  bridge   - la clase de campo bridge_io (base, shift, mask) con RMW
  regs     - mapa de indices y campos de los tops ab_top / c_top
  load     - cargadores: secuencia, formas de onda, tabla de squashing
  measure  - lectura de histogramas, matriz de coincidencias y QBER
"""
