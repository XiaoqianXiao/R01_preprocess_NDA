#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash submit_mriqc.sh [--csv MANIFEST.csv] [--dry-run]
       bash submit_mriqc.sh MANIFEST.csv [--dry-run]

Without a CSV, submit all BIDS subjects as a Slurm array.
With a downloader CSV, submit one job per unique subject_label/session_label.
CSV filenames are resolved under:
  /gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/dicom
Absolute CSV paths are also accepted.
Labels may include sub-/ses- prefixes. All selected BIDS directories must exist.
--dry-run prints submission commands without submitting jobs.
DATA_DIR may override the default BIDS NIfTI directory. CSV mode needs python3.
USAGE
}

DATA_DIR="${DATA_DIR:-/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii}"
export DATA_DIR
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CSV=""
DRY_RUN=0
while (( $# > 0 )); do
  case "$1" in
    --csv)
      if (( $# < 2 )) || [[ -z "$2" || "$2" == -* || -n "$CSV" ]]; then
        echo "Error: --csv requires one manifest path and may only be used once." >&2
        exit 1
      fi
      CSV="$2"
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    *)
      if [[ -n "$CSV" || -z "$1" ]]; then
        echo "Error: Specify only one CSV manifest." >&2
        exit 1
      fi
      CSV="$1"
      shift
      ;;
  esac
done

submit() {
  if (( DRY_RUN )); then
    printf '%q ' sbatch "$@"
    printf '\n'
  else
    sbatch "$@"
  fi
}

if [[ -n "$CSV" ]]; then
  if [[ "$CSV" != /* ]]; then
    CSV="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/dicom/${CSV}"
  fi
  echo "Using CSV manifest: $CSV"
  # Parse and validate the entire CSV before submitting any jobs. Command
  # substitution propagates parser failures, unlike process substitution.
  PAIRS="$(python3 - "$CSV" "$DATA_DIR" <<'PY'
import csv
from pathlib import Path
import re
import sys

manifest, data_dir = sys.argv[1:]
pairs = set()
try:
    with open(manifest, newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream, strict=True)
        required = {"subject_label", "session_label"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("CSV must contain subject_label and session_label columns")
        for row in reader:
            labels = []
            for column, prefix in (("subject_label", "sub-"), ("session_label", "ses-")):
                label = (row.get(column) or "").strip()
                if label.startswith(prefix):
                    label = label[len(prefix):]
                if not re.fullmatch(r"[A-Za-z0-9]+", label):
                    raise ValueError(f"CSV line {reader.line_num}: invalid {column}: {row.get(column)!r}")
                labels.append(label)
            subject, session = labels
            directory = Path(data_dir) / f"sub-{subject}" / f"ses-{session}"
            if not directory.is_dir():
                raise ValueError(f"BIDS session directory not found: {directory}")
            pairs.add((subject, session))
    if not pairs:
        raise ValueError("CSV contains no sessions")
except (OSError, ValueError, csv.Error) as exc:
    sys.exit(f"Error: {exc}")

for subject, session in sorted(pairs):
    print(f"{subject}\t{session}")
PY
)"
  while IFS=$'\t' read -r SUBJECT SESSION; do
    echo "Submitting sub-${SUBJECT}/ses-${SESSION}"
    submit --export="ALL,DATA_DIR,SINGLE_SUB=${SUBJECT},SINGLE_SES=${SESSION}" "${SCRIPT_DIR}/mriqc_job.sh"
  done <<< "$PAIRS"
else
  SUBJECTS=()
  while IFS= read -r SUBJECT; do
    SUBJECTS+=("$SUBJECT")
  done < <(find "$DATA_DIR" -mindepth 1 -maxdepth 1 -type d -name 'sub-*' -exec basename {} \; | sort)
  N=$((${#SUBJECTS[@]} - 1))
  if (( N < 0 )); then
    echo "Error: No subjects found in $DATA_DIR" >&2
    exit 1
  fi
  echo "Submitting jobs for $((N + 1)) subjects: ${SUBJECTS[*]}"
  submit --array="0-$N" --export="ALL,DATA_DIR,SINGLE_SUB=,SINGLE_SES=" "${SCRIPT_DIR}/mriqc_job.sh"
fi
