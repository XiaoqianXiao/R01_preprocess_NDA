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

# Path to your Python script
PYTHON_SCRIPT="/gscratch/scrubbed/fanglab/xiaoqian/repo/R01_preprocess/generate_QCsheets.py"

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
    "$CONTAINER_SIF" \
    python "$PYTHON_SCRIPT"

echo "Processing Complete. Check sum.json and CSV files in the derivatives folder."
