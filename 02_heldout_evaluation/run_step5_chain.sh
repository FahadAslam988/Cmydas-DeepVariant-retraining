#!/usr/bin/env bash
D="/home/work/Desktop/Fahad/03_Corrected_Work/rerun/09_simulation_truthset/RUN_DeepVariant_retraining/STEP5_heldout_test_evaluation"
bash "$D/scripts/s15_call_new_retrained_model.sh" || { echo "s15 FAILED"; exit 1; }
bash "$D/scripts/s16_benchmark_heldout_all_callers.sh" || { echo "s16 FAILED"; exit 1; }
echo "STEP5_ALL_DONE"
