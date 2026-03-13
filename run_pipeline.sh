#!/usr/bin/env bash
set -euo pipefail

# Cohort root contains subject dirs like HCA9816395_V2_MR/
COHORT_ROOT="${1:-/shared/workspace/lpv/synthetic_field_maps_ivan/data/unprocessed_synthbold_format/hca}"

# Optional: file with subject IDs (one per line). If not provided, run all subject dirs under COHORT_ROOT.
SUBJ_LIST="${2:-}"

# Path to your pipeline script inside the container
PIPELINE="${3:-./src/pipeline.sh}"

# ✅ Frozen flags for HCA/HCP SBRef use-case
PIPELINE_FLAGS=( --total_readout_time 0.058 )
# (We intentionally do NOT set: --skull_stripped, --motion_corrected, --no_smoothing, --no_topup)

# Where to store permanent outputs
OUT_ROOT="${OUT_ROOT:-/shared/workspace/lpv/synthetic_field_maps_ivan/results/Synth-Bold-Disco-unprocessed/hca/}"
mkdir -p "$OUT_ROOT"

run_one () {
    local SID="$1"
    local SDIR="$COHORT_ROOT/$SID"

    if [[ ! -d "$SDIR" ]]; then
        echo "[SKIP] Missing dir: $SDIR"
        return 0
    fi

    local T1="$SDIR/T1w_acpc_dc.nii.gz"
    # inside run_one(), after T1 is defined and checked

    declare -a SBREFS=(
    "rfMRI_REST1_AP_SBRef.nii.gz"
    "rfMRI_REST1_PA_SBRef.nii.gz"
    "rfMRI_REST2_AP_SBRef.nii.gz"
    "rfMRI_REST2_PA_SBRef.nii.gz"
    )

    for fname in "${SBREFS[@]}"; do
        local IN_BOLD="$SDIR/$fname"
        if [[ ! -f "$IN_BOLD" ]]; then
            echo "[SKIP] $SID missing $fname"
            continue
        fi

    # per-run output folder so the 4 runs don't overwrite each other
        local RUN_OUT="$OUT_ROOT/$SID/${fname%.nii.gz}"
        mkdir -p "$RUN_OUT"
        rm -rf /OUTPUTS
        ln -s "$RUN_OUT" /OUTPUTS

        # stage inputs for pipeline.sh
        rm -rf /INPUTS
        mkdir -p /INPUTS
        cp "$T1"      /INPUTS/T1.nii.gz
        cp "$IN_BOLD" /INPUTS/BOLD_d.nii.gz

        echo "=== $SID / $fname ==="
        pe_dir="AP"
        if [[ "$fname" == *"_PA_"* ]] || [[ "$fname" == *"_PA"* ]]; then
            pe_dir="PA"
        fi
        echo "Determined PE direction: $pe_dir"

        PIPELINE_FLAGS=( "${PIPELINE_FLAGS_BASE[@]}" --pe_dir "$pe_dir" )
        bash "$PIPELINE" "${PIPELINE_FLAGS[@]}"
        bash "$PIPELINE" "${PIPELINE_FLAGS[@]}"

        # pipeline output you want is BOLD_u.nii.gz
        if [[ ! -f "$RUN_OUT/BOLD_u.nii.gz" ]]; then
            echo "[WARN] Missing $RUN_OUT/BOLD_u.nii.gz for $SID / $fname"
            continue
        fi

        # write back next to the original input, with your desired name
        local OUT_NAME="${fname%.nii.gz}_dc_prediction.nii.gz"
        # write back next to the original input, with your desired name
        FINAL_OUT="$OUT_ROOT/$SID/$OUT_NAME"
        LOG_DIR="$OUT_ROOT/$SID/logs"
        LOG_NAME="${fname%.nii.gz}.log"

        mkdir -p "$LOG_DIR"

        if cp "$RUN_OUT/BOLD_u.nii.gz" "$FINAL_OUT"; then
            # Preserve log
            if [[ -f "$RUN_OUT/output.log" ]]; then
                mv "$RUN_OUT/output.log" "$LOG_DIR/$LOG_NAME"
            fi

            # Remove all other intermediates
            rm -rf "$RUN_OUT"

            echo "✅ Wrote and cleaned: $FINAL_OUT"
        else
            echo "❌ Copy failed — not deleting intermediates"
        fi

    done


}

# If a subject list is given, use it; otherwise run everything under COHORT_ROOT
if [[ -n "$SUBJ_LIST" ]]; then
  while IFS= read -r SID; do
    [[ -n "$SID" ]] || continue
    [[ "$SID" =~ ^# ]] && continue
    run_one "$SID"
  done < "$SUBJ_LIST"
else
  for SDIR in "$COHORT_ROOT"/*; do
    [[ -d "$SDIR" ]] || continue
    run_one "$(basename "$SDIR")"
  done
fi
