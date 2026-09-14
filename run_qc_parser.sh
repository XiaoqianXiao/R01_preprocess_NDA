#!/bin/bash
#SBATCH --job-name=mriqc_parse
#SBATCH --account=fang
#SBATCH --partition=cpu-g2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/qc_parse_%j.out

set -euo pipefail

# --- Configuration ---
# Path to your generated SIF file
CONTAINER_SIF="/gscratch/fang/images/python.sif"

# Locate the parser beside this launcher. Slurm runs a spooled copy of the
# launcher, so sbatch users should submit from the repository directory or
# provide PYTHON_SCRIPT explicitly.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${PYTHON_SCRIPT:-${SLURM_SUBMIT_DIR:-$SCRIPT_DIR}/generate_QCsheets.py}"
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo "ERROR: Parser not found: $PYTHON_SCRIPT" >&2
    echo "Set PYTHON_SCRIPT to the full path of generate_QCsheets.py." >&2
    exit 1
fi
PARSER_DIR="$(cd -- "$(dirname -- "$PYTHON_SCRIPT")" && pwd)"
PYTHON_SCRIPT="$PARSER_DIR/$(basename -- "$PYTHON_SCRIPT")"

# --- Execution ---
module load apptainer 2>/dev/null || true

echo "Starting MRIQC Parser..."
echo "Container: $CONTAINER_SIF"
echo "Script: $PYTHON_SCRIPT"

# We bind the /gscratch mount so the container can access the data
# Cluster defaults may include Slurm directories absent on the current host.
apptainer_command=(apptainer exec)
for slurm_path in /var/run/slurm /var/spool/slurmd; do
    if [[ ! -e "$slurm_path" ]]; then
        echo "Skipping missing Slurm system bind: $slurm_path"
        apptainer_command+=(--no-mount "$slurm_path")
    fi
done

"${apptainer_command[@]}" \
    --bind /gscratch/scrubbed/fanglab/xiaoqian:/gscratch/scrubbed/fanglab/xiaoqian \
    --bind "$PARSER_DIR:$PARSER_DIR:ro" \
    "$CONTAINER_SIF" \
    python "$PYTHON_SCRIPT"

echo "Processing Complete. Check sum.json and CSV files in the derivatives folder."
