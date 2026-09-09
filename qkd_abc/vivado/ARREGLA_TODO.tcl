################################################################################
#  ARREGLA_TODO.tcl  —  UNICO fichero que necesitas copiar
################################################################################
#  Este script NO depende de los demas .tcl ni de que hayas actualizado el
#  VHDL: parchea el fichero ab_synth_top.vhd EL MISMO si hace falta, monta el
#  Block Design entero aqui dentro y compila hasta el bitstream.
#
#  COPIA SOLO ESTE FICHERO en qkd_abc/vivado/  y ejecuta:
#      cd C:/Users/diego/Documents/TF-BB84/qkd_abc/vivado
#      set argv nodo_a
#      source ARREGLA_TODO.tcl
################################################################################

puts ""
puts "################################################################"
puts "###  ARREGLA_TODO.tcl  v4  (si ves esto, el fichero es correcto)"
puts "################################################################"

if {[llength $argv] > 0} { set nodo [lindex $argv 0] } else { set nodo nodo_a }

################################################################################
# PASO A — parchear ab_synth_top.vhd para que sea VHDL-93 legal
################################################################################
# Vivado no admite un fichero VHDL-2008 como TOP de un modulo referenciado en
# un Block Design. El envoltorio solo tenia una construccion de 2008: una
# expresion ("not axi_aresetn") como actual en un port map. La pasamos a una
# senal. Los MODULOS HIJOS siguen siendo VHDL-2008: la limitacion es solo del
# fichero raiz de la referencia.
set vhd ../node_ab/hdl/ab_synth_top.vhd
if {![file exists $vhd]} { error ">>> no encuentro $vhd (¿ruta correcta?)" }

set fh [open $vhd r]; set txt [read $fh]; close $fh

if {[string first "rst_i" $txt] >= 0} {
  puts "### A) ab_synth_top.vhd ya estaba parcheado"
} else {
  puts "### A) parcheando ab_synth_top.vhd -> VHDL-93 legal"
  # copia de seguridad
  set bh [open ${vhd}.bak w]; puts -nonewline $bh $txt; close $bh
  # 1) literal hexadecimal sin guiones bajos
  set txt [string map {{x"1A_08_10_02"} {x"1A081002"}} $txt]
  # 2) la expresion del port map pasa a una senal declarada
  set txt [string map [list \
    "  signal sym_cnt_i : unsigned(7 downto 0);\nbegin" \
    "  signal sym_cnt_i : unsigned(7 downto 0);\n  -- VHDL-93: en un port map el actual debe ser una SENAL, no una\n  -- expresion. Por eso la inversion del reset va aparte.\n  signal rst_i : std_logic;\nbegin\n  rst_i <= not axi_aresetn;                       -- reset activo alto" \
  ] $txt]
  set txt [string map [list \
    "clk_host => axi_aclk, rst => not axi_aresetn," \
    "clk_host => axi_aclk, rst => rst_i," \
  ] $txt]
  set fh [open $vhd w]; puts -nonewline $fh $txt; close $fh
  # comprobacion
  set fh [open $vhd r]; set txt2 [read $fh]; close $fh
  if {[string first "rst_i" $txt2] < 0} {
    error ">>> el parche no se aplico: revisa $vhd a mano"
  }
  puts "###    parcheado correctamente (copia previa en ${vhd}.bak)"
}

################################################################################
# PASO B — crear el proyecto desde cero
################################################################################
catch { close_project }
if {[file exists ./$nodo]} {
  puts "### B) borrando proyecto anterior ./$nodo"
  file delete -force ./$nodo
}
puts "### B) creando proyecto $nodo"
create_project $nodo ./$nodo -part xcku5p-ffvb676-2-e -force
catch { set_property board_part xilinx.com:kcu116:part0:1.5 [current_project] }

add_files -norecurse [list \
  ../common/hdl/qkd_pkg.vhd        ../common/hdl/reg_file.vhd \
  ../common/hdl/word_bit_delay.vhd ../common/hdl/cdc_pulse.vhd \
  ../common/hdl/prbs_gen.vhd       ../common/hdl/clk_counter.vhd \
  ../common/hdl/stats_snapshot.vhd ../common/hdl/axil_bridge.vhd \
  ../node_ab/hdl/waveform_lut.vhd  ../node_ab/hdl/state_chooser.vhd \
  ../node_ab/hdl/tx_datapath.vhd   ../node_ab/hdl/ab_top.vhd \
  ../node_ab/hdl/ab_synth_top.vhd ]

# el nucleo es VHDL-2008...
set_property file_type {VHDL 2008} [get_files *.vhd]
# ...pero el envoltorio del Block Design DEBE ser VHDL-93
set_property file_type {VHDL} [get_files ab_synth_top.vhd]
puts "### B) ab_synth_top.vhd marcado como VHDL-93"
set_property top ab_synth_top [current_fileset]
update_compile_order -fileset sources_1

# testbenches (para poder simular dentro de Vivado)
set tbs [glob -nocomplain ../sim/tb_*.vhd]
if {[llength $tbs] > 0} {
  add_files -fileset sim_1 -norecurse $tbs
  set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1]]
  catch { set_property top tb_ab_top_smoke [get_filesets sim_1] }
}

# NOTA: el XDC se genera mas abajo (paso C-bis), cuando ya existe el wrapper
# y conocemos los nombres EXACTOS de sus puertos.

################################################################################
# PASO C — Block Design: XDMA + MMCM + nuestro modulo
################################################################################
puts "### C) montando el Block Design"
proc bd_cfg {cell name value} {
  if {[catch { set_property CONFIG.$name $value [get_bd_cells $cell] }]} {
    puts "###    aviso: $cell CONFIG.$name no aplicable en esta version"
  }
}

create_bd_design "bd_ab"
current_bd_design [get_bd_designs bd_ab]

# XDMA (sin fijar version: coge la del catalogo, 4.2 en Vivado 2025.1)
create_bd_cell -type ip -vlnv [lindex [get_ipdefs -filter {NAME == xdma}] end] bd_xdma
puts "###    XDMA: [get_property VLNV [get_bd_cells bd_xdma]]"
bd_cfg bd_xdma mode_selection             {Basic}
bd_cfg bd_xdma pl_link_cap_max_link_width {X8}
bd_cfg bd_xdma pl_link_cap_max_link_speed {8.0_GT/s}
bd_cfg bd_xdma axilite_master_en          {true}
bd_cfg bd_xdma axilite_master_size        {64}
bd_cfg bd_xdma axilite_master_scale       {Kilobytes}

# MMCM: 300 MHz de placa -> 312,5 MHz (dominio de transmision, fase 1)
create_bd_cell -type ip -vlnv [lindex [get_ipdefs -filter {NAME == clk_wiz}] end] bd_clk_tx
bd_cfg bd_clk_tx PRIM_IN_FREQ               {300.000}
bd_cfg bd_clk_tx CLKOUT1_REQUESTED_OUT_FREQ {312.500}
bd_cfg bd_clk_tx PRIM_SOURCE                {Differential_clock_capable_pin}
bd_cfg bd_clk_tx USE_RESET                  {false}

# nuestro modulo RTL (aqui es donde fallaba antes)
if {[catch { create_bd_cell -type module -reference ab_synth_top bd_ab_top } msg]} {
  puts "###"
  puts "### FALLO al insertar ab_synth_top: $msg"
  puts "### Comprueba:  get_property FILE_TYPE \[get_files ab_synth_top.vhd\]"
  puts "### Deberia decir 'VHDL' (no 'VHDL 2008')."
  error "abortado"
}
puts "###    ab_synth_top insertado en el Block Design"

# ---- buffer del reloj de referencia PCIe ------------------------------------
# El XDMA NO acepta el reloj de refencia directo de los pines: necesita un
# IBUFDS_GTE4, que en el flujo de Block Design se instancia con util_ds_buf.
# De el salen DOS relojes que van a dos pines distintos del XDMA:
#   IBUF_OUT      -> sys_clk_gt  (reloj para el transceptor)
#   IBUF_DS_ODIV2 -> sys_clk     (el mismo dividido por 2, para la logica)
# Sin esto, validate_bd_design falla con "clock pins are not connected".
create_bd_cell -type ip -vlnv [lindex [get_ipdefs -filter {NAME == util_ds_buf}] end] bd_refbuf
bd_cfg bd_refbuf C_BUF_TYPE {IBUFDSGTE}
puts "###    util_ds_buf: [get_property VLNV [get_bd_cells bd_refbuf]]"

# ---- puertos externos con NOMBRES FIJOS -------------------------------------
# Se crean explicitamente (en vez de make_..._external) para que los nombres
# sean deterministas y el XDC pueda referirse a ellos con seguridad.
# Un puerto de reloj diferencial "X" genera en el wrapper los pines X_clk_p
# y X_clk_n; por eso el XDC usa esos sufijos.
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_refclk
connect_bd_intf_net [get_bd_intf_ports pcie_refclk] [get_bd_intf_pins bd_refbuf/CLK_IN_D]
connect_bd_net [get_bd_pins bd_refbuf/IBUF_OUT]      [get_bd_pins bd_xdma/sys_clk_gt]
connect_bd_net [get_bd_pins bd_refbuf/IBUF_DS_ODIV2] [get_bd_pins bd_xdma/sys_clk]
puts "###    reloj de referencia PCIe conectado (sys_clk + sys_clk_gt)"

# carriles PCIe hacia el conector
if {[catch {
  create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie_7x_mgt_rtl:1.0 pcie_mgt
  connect_bd_intf_net [get_bd_intf_ports pcie_mgt] [get_bd_intf_pins bd_xdma/pcie_mgt]
}]} {
  catch { make_bd_intf_pins_external [get_bd_intf_pins bd_xdma/pcie_mgt] }
}

# reset de PCIe (PERST#, activo bajo)
create_bd_port -dir I -type rst pcie_perstn
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports pcie_perstn]
catch { connect_bd_net [get_bd_ports pcie_perstn] [get_bd_pins bd_xdma/sys_rst_n] }

# reloj de placa de 300 MHz que alimenta el MMCM del dominio de transmision
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sysclk_300
set_property CONFIG.FREQ_HZ 300000000 [get_bd_intf_ports sysclk_300]
connect_bd_intf_net [get_bd_intf_ports sysclk_300] [get_bd_intf_pins bd_clk_tx/CLK_IN1_D]

# conexiones
set m [get_bd_intf_pins -quiet bd_xdma/M_AXI_LITE]
if {$m eq ""} { set m [get_bd_intf_pins -quiet bd_xdma/M_AXI_LITE_0] }
set sl [get_bd_intf_pins -quiet bd_ab_top/s_axi]
if {$m ne "" && $sl ne ""} {
  connect_bd_intf_net $m $sl
  puts "###    AXI-Lite conectado"
} else {
  puts "###    AVISO: conecta a mano M_AXI_LITE -> bd_ab_top/s_axi en el BD"
}
catch { connect_bd_net [get_bd_pins bd_xdma/axi_aclk]    [get_bd_pins bd_ab_top/axi_aclk] }
catch { connect_bd_net [get_bd_pins bd_xdma/axi_aresetn] [get_bd_pins bd_ab_top/axi_aresetn] }
catch { connect_bd_net [get_bd_pins bd_clk_tx/clk_out1]  [get_bd_pins bd_ab_top/clk_tx] }

assign_bd_address
regenerate_bd_layout
validate_bd_design
save_bd_design
add_files -norecurse [make_wrapper -files [get_files bd_ab.bd] -top -force]
set_property top bd_ab_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "### C) Block Design listo (top = bd_ab_wrapper)"

################################################################################
# PASO C-bis — XDC generado a partir de los puertos REALES del wrapper
################################################################################
# Los pines estan verificados contra KCU116_Rev1_0_XDC_04062017.xdc.
# Los NOMBRES de puerto los pone el Block Design: un puerto de reloj
# diferencial "X" se convierte en X_clk_p / X_clk_n en el wrapper.
set xdc ./$nodo/kcu116_generado.xdc
set fh [open $xdc w]
puts $fh "# XDC generado automaticamente por ARREGLA_TODO.tcl"
puts $fh "# Pines verificados contra el XDC maestro de la KCU116 (Rev 1.0)"
puts $fh ""
puts $fh "# --- reloj de sistema de 300 MHz (banco 66, DIFF_SSTL12 no LVDS) ---"
puts $fh "set_property -dict {PACKAGE_PIN K22 IOSTANDARD DIFF_SSTL12} \\"
puts $fh "    \[get_ports sysclk_300_clk_p\]"
puts $fh "set_property -dict {PACKAGE_PIN K23 IOSTANDARD DIFF_SSTL12} \\"
puts $fh "    \[get_ports sysclk_300_clk_n\]"
puts $fh "create_clock -period 3.333 -name sysclk_300 \[get_ports sysclk_300_clk_p\]"
puts $fh ""
puts $fh "# --- reloj de referencia PCIe de 100 MHz (banco 225, pin de GT:"
puts $fh "#     los pines MGTREFCLK NO llevan IOSTANDARD) ---"
puts $fh "set_property PACKAGE_PIN V7 \[get_ports pcie_refclk_clk_p\]"
puts $fh "set_property PACKAGE_PIN V6 \[get_ports pcie_refclk_clk_n\]"
puts $fh "create_clock -period 10.000 -name pcie_refclk \[get_ports pcie_refclk_clk_p\]"
puts $fh ""
puts $fh "# --- PERST# de PCIe ---"
puts $fh "set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS18} \[get_ports pcie_perstn\]"
puts $fh "set_property PULLUP true \[get_ports pcie_perstn\]"
puts $fh "set_false_path -from \[get_ports pcie_perstn\]"
close $fh
add_files -fileset constrs_1 -norecurse $xdc
puts "### C-bis) XDC generado en $xdc"

# Volcado de los puertos reales del wrapper: si algun nombre no coincide con
# el XDC, se vera aqui y la sintesis avisara de puertos sin restringir.
puts ""
puts "=============== PUERTOS DEL WRAPPER (comprobacion) ==============="
foreach p [lsort [get_bd_ports]]      { puts "   port : [get_property NAME $p]" }
foreach p [lsort [get_bd_intf_ports]] { puts "   intf : [get_property NAME $p]" }
puts "=================================================================="

################################################################################
# PASO D — sintesis, implementacion y bitstream
################################################################################
puts "### D) sintesis (esto tarda; paciencia)"
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  error ">>> SINTESIS FALLIDA. Ejecuta: open_run synth_1  y revisa los mensajes"
}
puts "### D) sintesis OK"

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error ">>> IMPLEMENTACION FALLIDA. Revisa: open_run impl_1"
}
open_run impl_1
report_timing_summary -file ./$nodo/timing_summary.rpt
report_utilization    -file ./$nodo/utilization.rpt

puts ""
puts "=============== RELOJES (copiame esta lista) ==============="
report_clocks
puts "==========================================================="
puts ""
puts ">>> LISTO: ./$nodo/$nodo.runs/impl_1/bd_ab_wrapper.bit"
