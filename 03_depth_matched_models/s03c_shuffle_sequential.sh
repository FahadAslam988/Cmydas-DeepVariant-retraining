#!/usr/bin/env bash
# ============================================================================
# STEP 3c - Shuffle the depths SEQUENTIALLY (one at a time), smallest first.
# Usage: bash s03c_shuffle_sequential.sh            # does 10x, 15x, 30x
#        bash s03c_shuffle_sequential.sh 30         # or an explicit list
# ----------------------------------------------------------------------------
# WHY THIS EXISTS
#   The 2026-07-26 12:42 attempt launched 10x + 15x + 30x IN PARALLEL.
#   shuffle_tfrecords_beam.py uses Beam DirectRunner in "running_mode: in_memory",
#   which holds the whole dataset in RAM. Three concurrent jobs climbed
#   461G -> 623G used (2G free) and all three were killed at 13:21. No output.
#   Size was never the problem: the proven 70x run (RUN_DeepVariant_retraining,
#   Jul 16 22:51 -> Jul 17 00:27) shuffled a LARGER 6.7G input with these exact
#   settings and succeeded. 10x/15x/30x are 1.5G/2.0G/3.3G - all smaller.
#   Evidence: failed_attempt_2026-07-26_archive/
#
# SAFETY RAILS
#   - strictly sequential; next depth starts only after RAM is actually released
#   - verifies REAL output files (s03b writes its DONE marker even if python
#     crashed, so the marker alone cannot be trusted)
#   - stops the chain on first failure so one bad depth cannot cascade
#   - resumable: a depth with real output is skipped on re-run
# ============================================================================
set -uo pipefail

NEW="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_coverage_augmented_retraining_mixed_10-15-30-70x"
S03B="$NEW/scripts/s03b_shuffle_one_depth.sh"
LOG="$NEW/run.log"
CHAIN="$NEW/s03c_chain.out"
MEMLOG="$NEW/s03c_mem.log"
MIN_FREE_GB=400        # refuse to start a depth unless this much RAM is available
WAIT_MAX=1800          # max seconds to wait for RAM before giving up

DEPTHS=("$@"); [ ${#DEPTHS[@]} -eq 0 ] && DEPTHS=(10 15 30)   # smallest first

log(){ echo "[$(date '+%F %T')] [s03c] $*" | tee -a "$CHAIN" >> "$LOG"; }

avail_gb(){ free -g | awk '/^Mem:/{print $7}'; }

# A depth is really done only if BOTH configs exist AND shards were written.
depth_done(){
  local d="$1" o="$NEW/shuffled_perdepth/${d}x"
  [ -s "$o/training/training_set.dataset_config.pbtxt" ]     || return 1
  [ -s "$o/validation/validation_set.dataset_config.pbtxt" ] || return 1
  [ "$(ls "$o/training"/*.shuffled-*.gz   2>/dev/null | wc -l)" -gt 0 ] || return 1
  [ "$(ls "$o/validation"/*.shuffled-*.gz 2>/dev/null | wc -l)" -gt 0 ] || return 1
  return 0
}

wait_for_ram(){
  local waited=0
  while [ "$(avail_gb)" -lt "$MIN_FREE_GB" ]; do
    [ "$waited" -ge "$WAIT_MAX" ] && { log "TIMEOUT waiting for RAM (only $(avail_gb)G available)"; return 1; }
    log "waiting for RAM ... $(avail_gb)G available, need ${MIN_FREE_GB}G"
    sleep 30; waited=$((waited+30))
  done
  return 0
}

# background memory trace, so a future OOM is diagnosable
( while true; do
    echo "$(date '+%F %T')  avail=$(avail_gb)G  used=$(free -g | awk '/^Mem:/{print $3}')G  jobs=$(pgrep -fc shuffle_tfrecords_beam.py || echo 0)" >> "$MEMLOG"
    sleep 60
  done ) &
MEMPID=$!
trap 'kill $MEMPID 2>/dev/null' EXIT

log "===== SEQUENTIAL SHUFFLE CHAIN START: depths ${DEPTHS[*]} (ONE AT A TIME) ====="
log "RAM available at start: $(avail_gb)G"

for d in "${DEPTHS[@]}"; do
  if depth_done "$d"; then log "${d}x already has real output, SKIP"; continue; fi

  wait_for_ram || { log "ABORT before ${d}x - not enough free RAM"; exit 1; }

  rm -rf "$NEW/shuffled_perdepth/${d}x"/*/beam-temp-* 2>/dev/null
  mkdir -p "$NEW/shuffled_perdepth/${d}x/training" "$NEW/shuffled_perdepth/${d}x/validation"

  log ">>> starting ${d}x   (RAM available $(avail_gb)G)"
  t0=$(date +%s)
  bash "$S03B" "$d" >> "$NEW/s03b_${d}x.out" 2>&1
  rc=$?
  t1=$(date +%s)
  log "<<< ${d}x finished rc=$rc in $(( (t1-t0)/60 )) min   (RAM available $(avail_gb)G)"

  if ! depth_done "$d"; then
    log "FAIL: ${d}x produced no usable output. CHAIN STOPPED (no cascade)."
    log "      check: tail -50 $NEW/s03b_${d}x.out"
    rm -f "$NEW/SHUFFLE_${d}x_DONE.marker"
    exit 1
  fi

  ntr=$(ls "$NEW/shuffled_perdepth/${d}x/training"/*.shuffled-*.gz   | wc -l)
  nva=$(ls "$NEW/shuffled_perdepth/${d}x/validation"/*.shuffled-*.gz | wc -l)
  nex=$(grep -m1 '^num_examples:' "$NEW/shuffled_perdepth/${d}x/training/training_set.dataset_config.pbtxt" | awk '{print $2}')
  nvx=$(grep -m1 '^num_examples:' "$NEW/shuffled_perdepth/${d}x/validation/validation_set.dataset_config.pbtxt" | awk '{print $2}')
  log "OK ${d}x -> ${ntr} train shard(s) / ${nva} val shard(s); train_examples=${nex} val_examples=${nvx}; size $(du -sh "$NEW/shuffled_perdepth/${d}x" | cut -f1)"
  echo "# STEP3c_shuffle_${d}x_DONE $(date '+%F %T')  train_examples=${nex} val_examples=${nvx} (${ntr} train / ${nva} val shards)" >> "$NEW/params.txt"

  sleep 20   # let the OS reclaim before the next depth
done

log "===== SEQUENTIAL SHUFFLE CHAIN DONE ====="
echo "OK $(date '+%F %T')" > "$NEW/STEP3C_ALL_SHUFFLES_DONE.marker"
