# XDC generado automaticamente por ARREGLA_TODO.tcl
# Pines verificados contra el XDC maestro de la KCU116 (Rev 1.0)

# --- reloj de sistema de 300 MHz (banco 66, DIFF_SSTL12 no LVDS) ---
set_property -dict {PACKAGE_PIN K22 IOSTANDARD DIFF_SSTL12} \
    [get_ports sysclk_300_clk_p]
set_property -dict {PACKAGE_PIN K23 IOSTANDARD DIFF_SSTL12} \
    [get_ports sysclk_300_clk_n]
create_clock -period 3.333 -name sysclk_300 [get_ports sysclk_300_clk_p]

# --- reloj de referencia PCIe de 100 MHz (banco 225, pin de GT:
#     los pines MGTREFCLK NO llevan IOSTANDARD) ---
set_property PACKAGE_PIN V7 [get_ports pcie_refclk_clk_p]
set_property PACKAGE_PIN V6 [get_ports pcie_refclk_clk_n]
create_clock -period 10.000 -name pcie_refclk [get_ports pcie_refclk_clk_p]

# --- PERST# de PCIe ---
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS18} [get_ports pcie_perstn]
set_property PULLUP true [get_ports pcie_perstn]
set_false_path -from [get_ports pcie_perstn]
