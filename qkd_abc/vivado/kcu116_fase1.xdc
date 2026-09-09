################################################################################
# kcu116_fase1.xdc — restricciones FASE 1 (bring-up del bridge PCIe)
################################################################################
# Todos los PACKAGE_PIN de este fichero estan VERIFICADOS contra
# KCU116_Rev1_0_XDC_04062017.xdc (XDC maestro de la placa).
#
# Nombres de puerto: los del XDC maestro se mantienen para que puedas
# contrastar linea a linea. Si tu top usa otros nombres, cambia solo el
# get_ports, nunca el PACKAGE_PIN.
################################################################################

#-------------------------------------------------------------------------------
# 1. Reloj de sistema de 300 MHz (SYSCLK_300)
#-------------------------------------------------------------------------------
# OJO: es DIFF_SSTL12 en el banco 66, NO LVDS. Poner LVDS aqui da error de
# compatibilidad de banco (VCCO = 1V2).
set_property PACKAGE_PIN K22         [get_ports "SYSCLK_300_P"]
set_property IOSTANDARD  DIFF_SSTL12 [get_ports "SYSCLK_300_P"]
set_property PACKAGE_PIN K23         [get_ports "SYSCLK_300_N"]
set_property IOSTANDARD  DIFF_SSTL12 [get_ports "SYSCLK_300_N"]
create_clock -period 3.333 -name sysclk_300 [get_ports "SYSCLK_300_P"]

#-------------------------------------------------------------------------------
# 2. PCIe: reloj de referencia de 100 MHz y reset
#-------------------------------------------------------------------------------
# El refclk de PCIe esta en el banco 225 (MGTREFCLK0_225).
set_property PACKAGE_PIN V7 [get_ports "PCIE_CLK_QO_P"]
set_property PACKAGE_PIN V6 [get_ports "PCIE_CLK_QO_N"]
create_clock -period 10.000 -name pcie_refclk [get_ports "PCIE_CLK_QO_P"]

# PERST# de PCIe (activo bajo). pullup: la senal viene del conector.
set_property PACKAGE_PIN T19      [get_ports "PCIE_PERST_LS"]
set_property IOSTANDARD  LVCMOS18 [get_ports "PCIE_PERST_LS"]
set_property PULLUP true          [get_ports "PCIE_PERST_LS"]
set_false_path -from [get_ports "PCIE_PERST_LS"]

# Los carriles PCIe (banco 224, x8) los coloca la propia IP XDMA: no hace
# falta restringirlos a mano si usas el Block Design.

#-------------------------------------------------------------------------------
# 3. Reset de usuario (opcional, boton CPU_RESET)
#-------------------------------------------------------------------------------
set_property PACKAGE_PIN B9       [get_ports "CPU_RESET"]
set_property IOSTANDARD  LVCMOS33 [get_ports "CPU_RESET"]
set_false_path -from [get_ports "CPU_RESET"]

#-------------------------------------------------------------------------------
# 4. Cruces de dominio de reloj (CDC)
#-------------------------------------------------------------------------------
# Los niveles cuasi-estaticos (enable, use_fixed, msb_first, inv, umbrales,
# delays) cruzan host -> tx por doble flip-flop. Son constantes durante la
# operacion, asi que el analisis de tiempos entre esos dominios no aplica.
# NOTA: ajusta los nombres de los relojes si tu jerarquia difiere; usa
#   report_clocks
# para ver los nombres reales que ha creado Vivado tras la sintesis.
set_max_delay -datapath_only -from [get_clocks -include_generated_clocks pcie_refclk] \
                             -to   [get_clocks -include_generated_clocks sysclk_300] 5.000
set_max_delay -datapath_only -from [get_clocks -include_generated_clocks sysclk_300] \
                             -to   [get_clocks -include_generated_clocks pcie_refclk] 5.000

#-------------------------------------------------------------------------------
# 5. FASE 2 (comentado): referencia y carriles para los GTY
#-------------------------------------------------------------------------------
# Cuando anhadas el GTY Transceiver Wizard, descomenta lo que uses.
#
# -- Referencia de usuario programable (Si570) en el banco 226. Es la que
#    debes programar a 156,25 MHz por I2C para los quads de datos.
# set_property PACKAGE_PIN M7 [get_ports "USER_MGT_SI570_CLOCK_C_P"]
# set_property PACKAGE_PIN M6 [get_ports "USER_MGT_SI570_CLOCK_C_N"]
# create_clock -period 6.400 -name mgt_refclk_156 [get_ports "USER_MGT_SI570_CLOCK_C_P"]
#
# -- Salida del limpiador de jitter Si5328 (banco 226 MGTREFCLK0): esta es la
#    entrada de reloj RECUPERADO Y LIMPIO. Es el camino de EnableRecClk.
# set_property PACKAGE_PIN P7 [get_ports "SFP_SI5328_OUT_C_P"]
# set_property PACKAGE_PIN P6 [get_ports "SFP_SI5328_OUT_C_N"]
#
# -- SFP0..3: banco 226 (quad completo, 4 carriles).
#    TX: N5/N4(0) L5/L4(1) J5/J4(2) G5/G4(3)
#    RX: M2/M1(0) K2/K1(1) H2/H1(2) F2/F1(3)
#    Los pines los coloca el wizard; deshabilitar TX_DISABLE si se usa optica:
# set_property -dict {PACKAGE_PIN AB14 IOSTANDARD LVCMOS33} [get_ports "SFP0_TX_DISABLE_B"]
# set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS33} [get_ports "SFP1_TX_DISABLE_B"]
# set_property -dict {PACKAGE_PIN AA15 IOSTANDARD LVCMOS33} [get_ports "SFP2_TX_DISABLE_B"]
# set_property -dict {PACKAGE_PIN Y15  IOSTANDARD LVCMOS33} [get_ports "SFP3_TX_DISABLE_B"]
#
# -- FMC HPC0 DP0..DP3: banco 227 (quad completo, 4 carriles) -> tarjeta X4SMA
#    TX: F7/F6(0) E5/E4(1) D7/D6(2) B7/B6(3)
#    RX: D2/D1(0) C4/C3(1) B2/B1(2) A4/A3(3)
#    Reloj de referencia del FMC (si la X4SMA lo suministra):
# set_property PACKAGE_PIN K7 [get_ports "FMC_HPC0_GBTCLK0_M2C_C_P"]
# set_property PACKAGE_PIN K6 [get_ports "FMC_HPC0_GBTCLK0_M2C_C_N"]
