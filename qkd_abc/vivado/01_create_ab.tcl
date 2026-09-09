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

# ---- 0b. COMPROBACION: ¿estan los ficheros actualizados? --------------------
# Este script y ab_synth_top.vhd van EMPAREJADOS. Si copiaste solo uno, el
# Block Design fallara mas adelante con un error confuso. Mejor avisar aqui.
set _f ../node_ab/hdl/ab_synth_top.vhd
if {![file exists $_f]} { error ">>> No encuentro $_f" }
set _fh [open $_f r]; set _txt [read $_fh]; close $_fh
if {[string first "rst_i" $_txt] < 0} {
  puts ""
  puts "########################################################################"
  puts "### ERROR: ab_synth_top.vhd es la version ANTIGUA."
  puts "###"
  puts "### Tienes que sobrescribir TRES ficheros:"
  puts "###   qkd_abc/node_ab/hdl/ab_synth_top.vhd   <-- OJO: no va en vivado/"
  puts "###   qkd_abc/vivado/01_create_ab.tcl"
  puts "###   qkd_abc/vivado/02_build_bd_ab.tcl"
  puts "###"
  puts "### Lo mas seguro: descomprime el ZIP completo encima de la carpeta."
  puts "########################################################################"
  error "ficheros desactualizados"
}
puts "### ab_synth_top.vhd: version correcta (VHDL-93 compatible)"

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
# IMPORTANTISIMO: el nucleo del diseno es VHDL-2008
set_property file_type {VHDL 2008} [get_files *.vhd]

# EXCEPCION: ab_synth_top.vhd se compila como VHDL-93.
# Motivo: Vivado NO admite un fichero VHDL-2008 como TOP de un modulo
# referenciado dentro de un Block Design ("This type is not allowed as the
# top file in the reference"). La restriccion afecta solo al fichero raiz;
# sus hijos (ab_top y los demas) siguen siendo VHDL-2008 sin problema.
# El envoltorio esta escrito para ser 93-legal (verificado con GHDL --std=93).
set_property file_type {VHDL} [get_files ab_synth_top.vhd]
puts "### ab_synth_top.vhd marcado como VHDL-93 (requisito del Block Design)"

set_property top ab_synth_top [current_fileset]

# ---- 3. Testbenches en el fileset de simulacion -----------------------------
set tbs [glob -nocomplain ../sim/tb_*.vhd]
if {[llength $tbs] > 0} {
  add_files -fileset sim_1 -norecurse $tbs
  set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1]]
  set_property top tb_ab_top_smoke [get_filesets sim_1]
}

# ---- 4/5. Las IP (XDMA y MMCM) se crean en el Block Design ------------------
# NO se instancian aqui: 02_build_bd_ab.tcl las crea DENTRO del Block Design.
# Crearlas en los dos sitios duplicaria la sintesis y puede dar conflictos de
# nombre. Aqui solo dejamos el proyecto y las fuentes RTL.

# ---- 6. Restricciones (XDC) -------------------------------------------------
# Usa el XDC verificado contra KCU116_Rev1_0_XDC_04062017.xdc (XDC maestro).
# Todos los PACKAGE_PIN estan contrastados con el fichero de la placa.
add_files -fileset constrs_1 -norecurse ./kcu116_fase1.xdc

puts ""
puts "########################################################################"
puts "### Proyecto $nodo creado."
puts "### SIGUIENTE PASO: abre el proyecto y conecta el XDMA en un Block"
puts "### Design, o usa 02_build_bd_ab.tcl que lo hace automaticamente."
puts "########################################################################"
