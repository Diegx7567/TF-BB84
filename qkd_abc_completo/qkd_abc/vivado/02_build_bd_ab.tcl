################################################################################
# 02_build_bd_ab.tcl — FASE 1b: Block Design que une XDMA + MMCM + nuestro top
################################################################################
# QUE HACE: crea un Block Design con la IP XDMA y el MMCM, mete nuestro
#           ab_synth_top como modulo RTL, cablea el AXI-Lite y genera el
#           wrapper HDL. Al terminar puedes lanzar sintesis y bitstream.
# USO: con el proyecto ya creado y ABIERTO en Vivado:
#        cd <ruta>/qkd_abc/vivado ; source 02_build_bd_ab.tcl
#      o en batch:
#        vivado -mode batch -source 02_build_bd_ab.tcl -tclargs nodo_a
################################################################################

if {[llength $argv] > 0 && [current_project -quiet] eq ""} {
  open_project ./[lindex $argv 0]/[lindex $argv 0].xpr
}

create_bd_design "bd_ab"

# ---- 1. XDMA ----------------------------------------------------------------
set xdma [create_bd_cell -type ip -vlnv xilinx.com:ip:xdma bd_xdma]
set_property -dict [list \
  CONFIG.mode_selection {Basic} \
  CONFIG.pl_link_cap_max_link_width {X8} \
  CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
  CONFIG.axilite_master_en {true} \
  CONFIG.axilite_master_size {64} \
  CONFIG.axilite_master_scale {Kilobytes} \
] $xdma

# ---- 2. Puertos externos de PCIe y relojes ---------------------------------
make_bd_intf_pins_external  [get_bd_intf_pins bd_xdma/pcie_mgt]
make_bd_intf_pins_external  [get_bd_intf_pins bd_xdma/pcie_refclk]
make_bd_pins_external       [get_bd_pins bd_xdma/sys_rst_n]

# ---- 3. MMCM para clk_tx (312,5 MHz en fase 1) ------------------------------
set clkw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz bd_clk_tx]
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {300.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {312.500} \
  CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
  CONFIG.USE_RESET {false} \
] $clkw
make_bd_intf_pins_external [get_bd_intf_pins bd_clk_tx/CLK_IN1_D]

# ---- 4. Nuestro modulo como bloque RTL --------------------------------------
# (Vivado infiere los puertos AXI-Lite por el prefijo s_axi_*)
create_bd_cell -type module -reference ab_synth_top bd_ab_top

# ---- 5. Conexiones ----------------------------------------------------------
connect_bd_intf_net [get_bd_intf_pins bd_xdma/M_AXI_LITE] \
                    [get_bd_intf_pins bd_ab_top/s_axi]
connect_bd_net [get_bd_pins bd_xdma/axi_aclk]    [get_bd_pins bd_ab_top/axi_aclk]
connect_bd_net [get_bd_pins bd_xdma/axi_aresetn] [get_bd_pins bd_ab_top/axi_aresetn]
connect_bd_net [get_bd_pins bd_clk_tx/clk_out1]  [get_bd_pins bd_ab_top/clk_tx]

# ---- 6. Mapa de direcciones: el BAR de usuario en 0x0 -----------------------
assign_bd_address
# 16 KiB = 4096 indices de 32 bits: coincide con el decodificador del reg_file
catch { set_property range 64K [get_bd_addr_segs {bd_xdma/M_AXI_LITE/*}] }

# ---- 7. Validar, generar wrapper y dejarlo como top -------------------------
validate_bd_design
save_bd_design
make_wrapper -files [get_files bd_ab.bd] -top
add_files -norecurse [make_wrapper -files [get_files bd_ab.bd] -top -force]
set_property top bd_ab_wrapper [current_fileset]

puts ""
puts "########################################################################"
puts "### Block Design listo. Ahora:  launch_runs impl_1 -to_step write_bitstream"
puts "########################################################################"
