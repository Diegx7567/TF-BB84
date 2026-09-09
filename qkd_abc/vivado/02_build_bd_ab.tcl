################################################################################
# 02_build_bd_ab.tcl — Block Design: XDMA + MMCM + nuestro ab_synth_top
################################################################################
# QUE HACE: crea el Block Design, instancia XDMA y clk_wiz (SIN fijar version,
#           para que funcione en cualquier Vivado), mete nuestro modulo RTL,
#           cablea el AXI-Lite y genera el wrapper HDL.
# ROBUSTEZ: los nombres de pines/CONFIG cambian entre versiones de IP, asi que
#           todo lo que puede variar va dentro de catch y se informa por consola.
################################################################################

if {[current_project -quiet] eq ""} {
  if {[llength $argv] > 0} { set nodo [lindex $argv 0] } else { set nodo nodo_a }
  open_project ./$nodo/$nodo.xpr
}

# helper: aplica un CONFIG y avisa si no existe en esta version de la IP
proc bd_cfg {cell name value} {
  if {[catch { set_property CONFIG.$name $value [get_bd_cells $cell] } msg]} {
    puts "###   aviso: $cell CONFIG.$name no aplicable"
  } else {
    puts "###   $cell CONFIG.$name = $value"
  }
}

create_bd_design "bd_ab"
current_bd_design [get_bd_designs bd_ab]

# ---- 1. XDMA (sin version fijada) ------------------------------------------
create_bd_cell -type ip -vlnv [lindex [get_ipdefs -filter {NAME == xdma}] end] bd_xdma
puts "### XDMA: [get_property VLNV [get_bd_cells bd_xdma]]"
bd_cfg bd_xdma mode_selection             {Basic}
bd_cfg bd_xdma pl_link_cap_max_link_width {X8}
bd_cfg bd_xdma pl_link_cap_max_link_speed {8.0_GT/s}
bd_cfg bd_xdma axilite_master_en          {true}
bd_cfg bd_xdma axilite_master_size        {64}
bd_cfg bd_xdma axilite_master_scale       {Kilobytes}

# ---- 2. MMCM para clk_tx (fase 1: 300 MHz -> 312,5 MHz) ---------------------
create_bd_cell -type ip -vlnv [lindex [get_ipdefs -filter {NAME == clk_wiz}] end] bd_clk_tx
puts "### CLK_WIZ: [get_property VLNV [get_bd_cells bd_clk_tx]]"
bd_cfg bd_clk_tx PRIM_IN_FREQ               {300.000}
bd_cfg bd_clk_tx CLKOUT1_REQUESTED_OUT_FREQ {312.500}
bd_cfg bd_clk_tx PRIM_SOURCE                {Differential_clock_capable_pin}
bd_cfg bd_clk_tx USE_RESET                  {false}

# ---- 3. Nuestro modulo RTL como bloque --------------------------------------
# Vivado infiere la interfaz AXI-Lite esclava por el prefijo s_axi_*.
# REQUISITO: ab_synth_top.vhd debe estar marcado como VHDL-93 (lo hace
# 01_create_ab.tcl). Vivado rechaza un top VHDL-2008 como modulo referenciado.
if {[catch { create_bd_cell -type module -reference ab_synth_top bd_ab_top } msg]} {
  puts "###"
  puts "### ERROR al insertar ab_synth_top en el Block Design:"
  puts "###   $msg"
  puts "###"
  puts "### Causa mas probable: el fichero sigue marcado como VHDL 2008."
  puts "### Solucion (ejecutala y vuelve a lanzar 02_build_bd_ab.tcl):"
  puts "###   set_property file_type {VHDL} \[get_files ab_synth_top.vhd\]"
  puts "###   update_compile_order -fileset sources_1"
  puts "###"
  error "abortado: ver mensaje anterior"
}

# ---- 4. Puertos externos ----------------------------------------------------
# PCIe: los nombres de los pines del XDMA varian algo entre versiones, por eso
# se buscan por patron en vez de codificarlos.
foreach pat {pcie_mgt pcie_refclk} {
  set p [get_bd_intf_pins -quiet bd_xdma/$pat]
  if {$p ne ""} { make_bd_intf_pins_external $p ; puts "### externo: $pat" } \
  else { puts "### AVISO: no encuentro la interfaz $pat en el XDMA" }
}
foreach pat {sys_rst_n} {
  set p [get_bd_pins -quiet bd_xdma/$pat]
  if {$p ne ""} { make_bd_pins_external $p ; puts "### externo: $pat" }
}
# entrada diferencial de 300 MHz al MMCM
set ck [get_bd_intf_pins -quiet bd_clk_tx/CLK_IN1_D]
if {$ck ne ""} { make_bd_intf_pins_external $ck }

# ---- 5. Conexiones ----------------------------------------------------------
# AXI-Lite maestro del XDMA -> esclavo de nuestro top
set m [get_bd_intf_pins -quiet bd_xdma/M_AXI_LITE]
if {$m eq ""} { set m [get_bd_intf_pins -quiet bd_xdma/M_AXI_LITE_0] }
set sl [get_bd_intf_pins -quiet bd_ab_top/s_axi]
if {$m ne "" && $sl ne ""} {
  connect_bd_intf_net $m $sl
  puts "### AXI-Lite conectado"
} else {
  puts "### AVISO: conecta a mano M_AXI_LITE  ->  bd_ab_top/s_axi en el BD"
}
# relojes y reset
catch { connect_bd_net [get_bd_pins bd_xdma/axi_aclk]    [get_bd_pins bd_ab_top/axi_aclk] }
catch { connect_bd_net [get_bd_pins bd_xdma/axi_aresetn] [get_bd_pins bd_ab_top/axi_aresetn] }
catch { connect_bd_net [get_bd_pins bd_clk_tx/clk_out1]  [get_bd_pins bd_ab_top/clk_tx] }

# ---- 6. Direcciones ---------------------------------------------------------
assign_bd_address
catch { set_property offset 0x00000000 [get_bd_addr_segs -of_objects [get_bd_intf_pins bd_ab_top/s_axi]] }

# ---- 7. Validar y generar wrapper -------------------------------------------
regenerate_bd_layout
validate_bd_design
save_bd_design
set bdf [get_files bd_ab.bd]
add_files -norecurse [make_wrapper -files $bdf -top -force]
set_property top bd_ab_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "########################################################################"
puts "### Block Design listo y wrapper generado (top = bd_ab_wrapper)"
puts "########################################################################"
