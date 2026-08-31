#!/usr/bin/env bash
# Suite completa de regresion del gateware QKD A/B/C (GHDL, VHDL-2008).
# USO: GHDL=ghdl ./run_all_tests.sh   (o exporta GHDL a tu binario)
set -u
GHDL=${GHDL:-ghdl}
cd "$(dirname "$0")/sim" && rm -f *.cf

SRC_COMMON="../common/hdl/qkd_pkg.vhd ../common/hdl/reg_file.vhd \
../common/hdl/word_bit_delay.vhd ../common/hdl/seq_bram.vhd \
../common/hdl/cdc_pulse.vhd ../common/hdl/prbs_gen.vhd \
../common/hdl/clk_counter.vhd ../common/hdl/stats_snapshot.vhd"
SRC_C="../node_c/hdl/edge_filter.vhd ../node_c/hdl/binner.vhd \
../node_c/hdl/histogram.vhd ../node_c/hdl/squash_lut.vhd \
../node_c/hdl/coincidence_matrix.vhd ../node_c/hdl/c_top.vhd"
SRC_AB="../node_ab/hdl/waveform_lut.vhd ../node_ab/hdl/state_chooser.vhd \
../node_ab/hdl/tx_datapath.vhd ../node_ab/hdl/ab_top.vhd"

$GHDL -a --std=08 -frelaxed $SRC_COMMON $SRC_C $SRC_AB tb_*.vhd || exit 1

PASS=0; FAIL=0
for tb in tb_word_bit_delay tb_reg_file tb_seq_bram tb_prbs_gen tb_cdc_pulse \
          tb_clk_counter tb_stats_snapshot tb_binner tb_edge_filter \
          tb_histogram tb_squash_lut tb_coincidence_matrix tb_waveform \
          tb_state_chooser tb_tx_datapath tb_ab_top_smoke tb_c_top_smoke; do
  [ "$tb" = tb_waveform ] && continue   # (la LUT se verifica via tb_tx_datapath)
  $GHDL -e --std=08 -frelaxed $tb >/dev/null 2>&1 || { echo "  $tb: NO ELABORA"; FAIL=$((FAIL+1)); continue; }
  out=$($GHDL -r --std=08 $tb --stop-time=200ms 2>&1 | grep -oE "TEST (PASSED|FAILED)" | head -1)
  printf "  %-26s %s\n" "$tb" "${out:-SIN RESULTADO}"
  [ "$out" = "TEST PASSED" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
done
echo "== $PASS pasados, $FAIL fallados =="
[ $FAIL -eq 0 ]
