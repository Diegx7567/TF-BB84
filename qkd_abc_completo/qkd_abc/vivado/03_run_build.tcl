################################################################################
# 03_run_build.tcl — lanza sintesis, implementacion y bitstream
################################################################################
# USO: vivado -mode batch -source 03_run_build.tcl -tclargs nodo_a
################################################################################
if {[llength $argv] > 0} { set nodo [lindex $argv 0] } else { set nodo nodo_a }
open_project ./$nodo/$nodo.xpr

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  error "La sintesis fallo: revisa el log con  open_run synth_1"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error "La implementacion fallo: revisa los informes de tiempos"
}

# informe util: donde estan los caminos criticos
open_run impl_1
report_timing_summary -file ./$nodo/timing_summary.rpt
report_utilization    -file ./$nodo/utilization.rpt
puts "### Bitstream generado. Informes en ./$nodo/"
