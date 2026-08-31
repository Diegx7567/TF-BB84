################################################################################
# 00_run_sim.tcl — PASO 0: ejecuta un testbench en el simulador de Vivado
################################################################################
# USO (proyecto ya creado y abierto):
#     set argv tb_ab_top_smoke ; source 00_run_sim.tcl
# Testbenches disponibles: tb_ab_top_smoke, tb_tx_datapath, tb_axil_bridge,
#     tb_reg_file, tb_word_bit_delay, tb_c_top_smoke, ...
################################################################################
if {[llength $argv] > 0} { set tb [lindex $argv 0] } else { set tb tb_ab_top_smoke }
set_property top $tb [get_filesets sim_1]
launch_simulation
run 20 ms
puts "### Simulacion de $tb terminada. Busca 'TEST PASSED' en la consola TCL."
