################################################################################
# 01_create_ab.tcl — FASE 1: crea el proyecto del transmisor (nodo A o B)
################################################################################
# QUE HACE: crea el proyecto, anhade TODAS las fuentes VHDL-2008, crea el XDC,
#           instancia la IP XDMA y el MMCM, y conecta todo por TCL.
#           Al terminar, el proyecto esta listo para "Run Synthesis".
#
# USO (desde la carpeta vivado/, con Vivado en el PATH):
#     vivado -mode batch -source 01_create_ab.tcl -tclargs nodo_a
#     vivado -mode batch -source 01_create_ab.tcl -tclargs nodo_b
# o desde la consola TCL de Vivado ya abierto:
#     cd <ruta>/qkd_abc/vivado ; set argv nodo_a ; source 01_create_ab.tcl
################################################################################

# ---- 0. Nombre del nodo y version ------------------------------------------
if {[llength $argv] > 0} { set nodo [lindex $argv 0] } else { set nodo nodo_a }
# la version identifica el bitstream al leer el indice 0 (AA MM DD VV)
if {$nodo eq "nodo_b"} { set version 32'h1A081012 } else { set version 32'h1A081002 }
puts "### Creando proyecto $nodo (version $version)"

# ---- 1. Proyecto y placa ----------------------------------------------------
# KCU116 = XCKU5P-FFVB676-2-E. Si tu revision de placa difiere, ajusta
# board_part (mira Tools > Settings > Project Settings > General > Board).
create_project $nodo ./$nodo -part xcku5p-ffvb676-2-e -force
catch { set_property board_part xilinx.com:kcu116:part0:1.5 [current_project] }

# ---- 2. Fuentes VHDL (rutas relativas a vivado/) ----------------------------
set src [list \
  ../common/hdl/qkd_pkg.vhd \
  ../common/hdl/reg_file.vhd \
  ../common/hdl/word_bit_delay.vhd \
  ../common/hdl/cdc_pulse.vhd \
  ../common/hdl/prbs_gen.vhd \
  ../common/hdl/clk_counter.vhd \
  ../common/hdl/stats_snapshot.vhd \
  ../common/hdl/axil_bridge.vhd \
  ../node_ab/hdl/waveform_lut.vhd \
  ../node_ab/hdl/state_chooser.vhd \
  ../node_ab/hdl/tx_datapath.vhd \
  ../node_ab/hdl/ab_top.vhd \
  ../node_ab/hdl/ab_synth_top.vhd ]
add_files -norecurse $src
# IMPORTANTISIMO: todo el codigo es VHDL-2008 (usa tipos sin restringir)
set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top ab_synth_top [current_fileset]

# ---- 3. Testbenches en el fileset de simulacion -----------------------------
set tbs [glob -nocomplain ../sim/tb_*.vhd]
if {[llength $tbs] > 0} {
  add_files -fileset sim_1 -norecurse $tbs
  set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1]]
  set_property top tb_ab_top_smoke [get_filesets sim_1]
}

# ---- 4. IP XDMA (el puente PCIe) -------------------------------------------
# Configuracion minima: 1 carril Gen3 x8 segun la KCU116, AXI-Lite habilitado
# para registros (BAR de usuario). Los valores por defecto del resto sirven.
create_ip -name xdma -vendor xilinx.com -library ip -version 4.1 \
          -module_name xdma_0
set_property -dict [list \
  CONFIG.mode_selection {Basic} \
  CONFIG.pl_link_cap_max_link_width {X8} \
  CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
  CONFIG.axi_data_width {256_bit} \
  CONFIG.axilite_master_en {true} \
  CONFIG.axilite_master_size {64} \
  CONFIG.axilite_master_scale {Kilobytes} \
  CONFIG.xdma_axilite_slave {false} \
] [get_ips xdma_0]
generate_target all [get_ips xdma_0]

# ---- 5. MMCM para el dominio de transmision (FASE 1) ------------------------
# En la fase 1 no hay GTY: clk_tx sale de un MMCM a 312,5 MHz alimentado por
# el reloj de placa. En la fase 2 se sustituye por TXUSRCLK2 del GTY.
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_tx
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {300.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {312.500} \
  CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
  CONFIG.USE_RESET {false} \
] [get_ips clk_wiz_tx]
generate_target all [get_ips clk_wiz_tx]

# ---- 6. Restricciones (XDC) -------------------------------------------------
set xdc_file ./$nodo/constraints.xdc
set fh [open $xdc_file w]
puts $fh {
# ------------------------------------------------------------------------
# constraints.xdc — FASE 1 (bring-up del bridge PCIe)
# ------------------------------------------------------------------------
# Reloj de sistema diferencial de 300 MHz de la KCU116 (SYSCLK).
# VERIFICA estos pines contra el esquematico/XDC maestro de TU placa:
# el master XDC de la KCU116 esta en el Board Store de Xilinx.
set_property -dict {PACKAGE_PIN AK17 IOSTANDARD LVDS} [get_ports sysclk_p]
set_property -dict {PACKAGE_PIN AK16 IOSTANDARD LVDS} [get_ports sysclk_n]
create_clock -period 3.333 -name sysclk [get_ports sysclk_p]

# Reloj de referencia de PCIe (100 MHz) y reset
create_clock -period 10.000 -name pcie_refclk [get_ports pcie_refclk_p]

# Cruces de dominio: los niveles cuasi-estaticos (enable, use_fixed,
# msb_first, inv, umbrales, delays) van por doble FF; declararlos como
# falsos caminos evita que el analisis de tiempos falle sin motivo.
set_false_path -from [get_clocks -of_objects [get_pins */axi_aclk]] \
               -to   [get_clocks -of_objects [get_pins */clk_tx]]
}
close $fh
add_files -fileset constrs_1 -norecurse $xdc_file

puts ""
puts "########################################################################"
puts "### Proyecto $nodo creado."
puts "### SIGUIENTE PASO: abre el proyecto y conecta el XDMA en un Block"
puts "### Design, o usa 02_build_bd_ab.tcl que lo hace automaticamente."
puts "########################################################################"
