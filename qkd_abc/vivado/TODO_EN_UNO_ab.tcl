################################################################################
# TODO_EN_UNO_ab.tcl — crea el proyecto, monta el Block Design y compila
################################################################################
# USO desde terminal (recomendado):
#   cd <ruta>/qkd_abc/vivado
#   vivado -mode batch -source TODO_EN_UNO_ab.tcl -tclargs nodo_a
#
# USO desde la consola TCL de Vivado ya abierto:
#   cd <ruta>/qkd_abc/vivado
#   set argv nodo_a
#   source TODO_EN_UNO_ab.tcl
#
# Tarda del orden de 20-40 min (la mayor parte, implementacion del XDMA).
# Al terminar tendras el .bit en:
#   <nodo>/<nodo>.runs/impl_1/bd_ab_wrapper.bit
################################################################################

if {[llength $argv] > 0} { set nodo [lindex $argv 0] } else { set nodo nodo_a }

# si quedo un proyecto a medias de un intento anterior, cierralo y borralo:
# create_project -force falla si el proyecto esta ABIERTO en esta sesion
catch { close_project }
if {[file exists ./$nodo]} {
  puts ">>> borrando proyecto anterior ./$nodo"
  file delete -force ./$nodo
}

puts "\n>>> PASO 1/3: creando proyecto $nodo"
source 01_create_ab.tcl

puts "\n>>> PASO 2/3: montando el Block Design"
source 02_build_bd_ab.tcl

puts "\n>>> PASO 3/3: sintesis + implementacion + bitstream"
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  error ">>> LA SINTESIS FALLO. Ejecuta: open_run synth_1  y revisa los mensajes."
}
puts ">>> Sintesis OK"

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error ">>> LA IMPLEMENTACION FALLO. Revisa timing con: open_run impl_1"
}
puts ">>> Bitstream generado"

# informes utiles y, muy importante, los NOMBRES REALES de los relojes
open_run impl_1
report_timing_summary -file ./$nodo/timing_summary.rpt
report_utilization    -file ./$nodo/utilization.rpt
puts "\n=========== RELOJES CREADOS (mandame esta lista) ==========="
report_clocks
puts "============================================================"
puts "\n>>> LISTO. Bitstream en ./$nodo/$nodo.runs/impl_1/bd_ab_wrapper.bit"
