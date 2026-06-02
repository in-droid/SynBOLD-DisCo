#!/usr/bin/env bash
set -euo pipefail

COHORT_ROOT="${1:-/shared/workspace/lpv/synthetic_field_maps_ivan/data/unprocessed_synthbold_format/hcya}"
SUBJ_LIST="${2:-}"
PIPELINE="${3:-./src/pipeline.sh}"

PIPELINE_FLAGS_BASE=( --total_readout_time 0.058 )

OUT_ROOT="${OUT_ROOT:-/shared/workspace/lpv/synthetic_field_maps_ivan/results/Synth-Bold-Disco-unprocessed/hcya}"
mkdir -p "$OUT_ROOT"

run_one() {
    local SID="$1"
    local SDIR="$COHORT_ROOT/$SID"

    if [[ ! -d "$SDIR" ]]; then
        echo "[SKIP] Missing dir: $SDIR"
        return 0
    fi

    local T1="$SDIR/T1w_acpc_dc.nii.gz"
    if [[ ! -f "$T1" ]]; then
        echo "[SKIP] $SID missing T1: $T1"
        return 0
    fi

    declare -a SBREFS=(
        "rfMRI_REST1_AP_SBRef.nii.gz"
        "rfMRI_REST1_PA_SBRef.nii.gz"
        "rfMRI_REST2_AP_SBRef.nii.gz"
        "rfMRI_REST2_PA_SBRef.nii.gz"
        "rfMRI_REST1_LR_SBRef.nii.gz"
        "rfMRI_REST1_RL_SBRef.nii.gz"
        "rfMRI_REST2_LR_SBRef.nii.gz"
        "rfMRI_REST2_RL_SBRef.nii.gz"
    )

    for fname in "${SBREFS[@]}"; do
        local IN_BOLD="$SDIR/$fname"
        if [[ ! -f "$IN_BOLD" ]]; then
            echo "[SKIP] $SID missing $fname"
            continue
        fi

        local pe_dir=""
        case "$fname" in
            *_AP_SBRef.nii.gz) pe_dir="AP" ;;
            *_PA_SBRef.nii.gz) pe_dir="PA" ;;
            *_LR_SBRef.nii.gz) pe_dir="LR" ;;
            *_RL_SBRef.nii.gz) pe_dir="RL" ;;
            *)
                echo "[SKIP] Could not determine PE direction from filename: $fname"
                continue
                ;;
        esac

        echo "=== $SID / $fname ==="
        echo "Determined PE direction: $pe_dir"

        local RUN_OUT="$OUT_ROOT/$SID/${fname%.nii.gz}"
        mkdir -p "$RUN_OUT"

        rm -rf /OUTPUTS
        ln -s "$RUN_OUT" /OUTPUTS

        rm -rf /INPUTS
        mkdir -p /INPUTS
        cp "$T1" /INPUTS/T1.nii.gz
        cp "$IN_BOLD" /INPUTS/BOLD_d.nii.gz

        local PIPELINE_FLAGS=( "${PIPELINE_FLAGS_BASE[@]}" --pe_dir "$pe_dir" )
        bash "$PIPELINE" "${PIPELINE_FLAGS[@]}"

        if [[ ! -f "$RUN_OUT/BOLD_u.nii.gz" ]]; then
            echo "[WARN] Missing $RUN_OUT/BOLD_u.nii.gz for $SID / $fname"
            continue
        fi

        local OUT_NAME="${fname%.nii.gz}_dc_prediction.nii.gz"
        local FINAL_OUT="$OUT_ROOT/$SID/$OUT_NAME"
        local LOG_DIR="$OUT_ROOT/$SID/logs"
        local LOG_NAME="${fname%.nii.gz}.log"

        mkdir -p "$LOG_DIR"

        if cp "$RUN_OUT/BOLD_u.nii.gz" "$FINAL_OUT"; then
            if [[ -f "$RUN_OUT/output.log" ]]; then
                mv "$RUN_OUT/output.log" "$LOG_DIR/$LOG_NAME"
            fi

            rm -rf "$RUN_OUT"
            echo "✅ Wrote and cleaned: $FINAL_OUT"
        else
            echo "❌ Copy failed - not deleting intermediates"
        fi
    done
}

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