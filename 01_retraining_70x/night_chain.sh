#!/usr/bin/env bash
# ============================================================================
# OVERNIGHT CHAIN — wait for the shuffle (STEP3) to finish, then run GPU training
# (STEP4). Evaluation (STEP5) is done in the morning (needs checkpoint selection).
# Detached; logs to run.log + night_chain.log. Does NOT suspend (training must run).
# ============================================================================
R="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_retraining"
NLOG="$R/night_chain.log"; LOG="$R/run.log"
log(){ echo "[$(date '+%F %T')] [chain] $*" | tee -a "$NLOG" "$LOG" >/dev/null; }

log "night chain started; waiting for STEP3 shuffle to finish, then GPU training."
end=$((SECONDS+43200))   # 12h safety cap on the wait
while ! grep -q '^# STEP3_shuffle_DONE' "$R/params.txt" 2>/dev/null; do
  # if the shuffle process died without writing the marker, stop waiting and check outputs
  if ! pgrep -f 'shuffle_tfrecords' >/dev/null 2>&1; then
    sleep 20
    grep -q '^# STEP3_shuffle_DONE' "$R/params.txt" 2>/dev/null || { log "shuffle process gone; checking outputs anyway."; break; }
  fi
  [ $SECONDS -ge $end ] && { log "12h wait cap reached; proceeding to check outputs."; break; }
  sleep 60
done

if [ -s "$R/shuffled/training/training_set.dataset_config.pbtxt" ] && [ -s "$R/shuffled/validation/validation_set.dataset_config.pbtxt" ]; then
  log "shuffle outputs present -> starting GPU training (STEP 4)."
  bash "$R/scripts/s14_train.sh" >> "$LOG" 2>&1
  rc=$?
  if grep -q '^# STEP4_train_DONE' "$R/params.txt" 2>/dev/null; then
    log "GPU training COMPLETED overnight. Morning: run STEP 5 (call on test + hap.py)."
  else
    log "GPU training did NOT complete (rc=$rc). Check run.log; fix in the morning."
  fi
else
  log "ERROR: shuffle dataset configs missing -> cannot train. Fix in the morning."
fi
log "night chain finished."
