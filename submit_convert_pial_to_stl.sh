#!/bin/bash
#SBATCH --job-name=fs_stl_sub-334
#SBATCH --partition=cpu-g2
#SBATCH --account=fang
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --output=logs/convert_%x_%A.out
#SBATCH --error=logs/convert_%x_%A.err

set -euo pipefail

# Override these paths through environment variables when needed.
CONTAINER_SIF="${CONTAINER_SIF:-/gscratch/fang/images/freesurfer.sif}"
LICENSE_FILE="${LICENSE_FILE:-/mmfs1/home/xxqian/files/fs_license.txt}"
DERIVS_DIR="${DERIVS_DIR:-/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/freesurfer/sub-144_ses-T12/surf}"
OUTPUT_DIR="${OUTPUT_DIR:-/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/for3D/stl_mesh}"

if [[ ! -d "$DERIVS_DIR" ]]; then
    echo "ERROR: Surface directory does not exist: $DERIVS_DIR" >&2
    echo "Set DERIVS_DIR to the subject's existing FreeSurfer surf directory." >&2
    exit 1
fi
DERIVS_DIR="$(cd -- "$DERIVS_DIR" && pwd)"
TARGET_SUBJ="$(basename -- "$(dirname -- "$DERIVS_DIR")")"
echo "Targeting Subject: $TARGET_SUBJ"

for required_file in "$CONTAINER_SIF" "$LICENSE_FILE" "$DERIVS_DIR/rh.pial" "$DERIVS_DIR/lh.pial"; do
    if [[ ! -r "$required_file" ]]; then
        echo "ERROR: Required file is missing or unreadable: $required_file" >&2
        exit 1
    fi
done

module load apptainer 2>/dev/null || true
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"

apptainer_command=(apptainer exec)
for slurm_path in /var/run/slurm /var/spool/slurmd; do
    if [[ ! -e "$slurm_path" ]]; then
        echo "Skipping missing Slurm system bind: $slurm_path"
        apptainer_command+=(--no-mount "$slurm_path")
    fi
done

# Positional arguments preserve paths containing spaces inside the container.
"${apptainer_command[@]}" \
    -B "${LICENSE_FILE}:/opt/freesurfer/license.txt:ro" \
    -B "${DERIVS_DIR}:${DERIVS_DIR}:ro" \
    -B "${OUTPUT_DIR}:${OUTPUT_DIR}" \
    --env FS_LICENSE=/opt/freesurfer/license.txt \
    "$CONTAINER_SIF" \
    bash -euc '
        echo "Converting right hemisphere pial surface..."
        mris_convert "$1/rh.pial" "$2/rh.stl"
        echo "Converting left hemisphere pial surface..."
        mris_convert "$1/lh.pial" "$2/lh.stl"
    ' bash "$DERIVS_DIR" "$OUTPUT_DIR"

echo "Successfully generated STL files in: $OUTPUT_DIR"
