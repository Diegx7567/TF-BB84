################################################################################
# FIX_y_continuar.tcl — arregla el proyecto YA CREADO y sigue desde el paso 2
################################################################################
# USA ESTO si ya tienes ./nodo_a creado y solo fallo el Block Design.
# Requiere que ab_synth_top.vhd sea la version nueva (con rst_i).
#
# USO:  cd <ruta>/qkd_abc/vivado
#       set argv nodo_a
#       source FIX_y_continuar.tcl
################################################################################
if {[llength $argv] > 0} { set nodo [lindex $argv 0] } else { set nodo nodo_a }
if {[current_project -quiet] eq ""} { open_project ./$nodo/$nodo.xpr }

# 1) comprobar que el VHDL en disco es el nuevo
set _f [get_files ab_synth_top.vhd]
set _fh [open $_f r]; set _txt [read $_fh]; close $_fh
if {[string first "rst_i" $_txt] < 0} {
  error ">>> ab_synth_top.vhd sigue siendo la version ANTIGUA. Sobrescribelo\
 con el del ZIP (esta en node_ab/hdl/, NO en vivado/) y repite."
}
puts "### ab_synth_top.vhd correcto"

# 2) marcarlo como VHDL-93 (requisito del Block Design)
set_property file_type {VHDL} [get_files ab_synth_top.vhd]
update_compile_order -fileset sources_1
puts "### ab_synth_top.vhd marcado como VHDL-93"

# 3) borrar el Block Design a medias que quedo del intento fallido
if {[llength [get_files -quiet bd_ab.bd]] > 0} {
  puts "### eliminando Block Design anterior"
  catch { close_bd_design [get_bd_designs -quiet bd_ab] }
  export_ip_user_files -of_objects [get_files bd_ab.bd] -no_script -reset -force -quiet
  remove_files [get_files bd_ab.bd]
  file delete -force ./$nodo/${nodo}.srcs/sources_1/bd/bd_ab
}

# 4) rehacer el Block Design y compilar
source 02_build_bd_ab.tcl

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  error ">>> Sintesis fallida: open_run synth_1 y revisa los mensajes"
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error ">>> Implementacion fallida: open_run impl_1"
}
open_run impl_1
report_timing_summary -file ./$nodo/timing_summary.rpt
puts "\n=========== RELOJES (mandame esta lista) ==========="
report_clocks
puts "==================================================="
puts "\n>>> Bitstream: ./$nodo/$nodo.runs/impl_1/bd_ab_wrapper.bit"
