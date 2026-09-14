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

# --- Configuration ---
TARGET_SUBJ="_"
CONTAINER_SIF="/gscratch/fang/images/freesurfer.sif"
LICENSE_FILE="/mmfs1/home/xxqian/files/fs_license.txt"
DERIVS_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/freesurfer/sub-144_ses-baseline/surf"

module load apptainer 2>/dev/null || true

echo "Targeting Subject: ${TARGET_SUBJ}"


SURF_DIR=$DERIVS_DIR
OUTPUT_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/for3D/stl_mesh"
# Ensure output directory exists for the meshes
mkdir -p "${OUTPUT_DIR}"

# Execute Conversion via Apptainer
apptainer exec \
  -B "${LICENSE_FILE}:/opt/freesurfer/license.txt" \
  -B "${DERIVS_DIR}" \
  -B "/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/derivatives/for3D" \
  --env FS_LICENSE=/opt/freesurfer/license.txt \
  "${CONTAINER_SIF}" \
  bash -c "
    echo 'Converting right hemisphere pial surface...'
    mris_convert ${DERIVS_DIR}/rh.pial ${OUTPUT_DIR}/rh.stl

    echo 'Converting left hemisphere pial surface...'
    mris_convert ${DERIVS_DIR}/lh.pial ${OUTPUT_DIR}/lh.stl
  "
  
if [ $? -eq 0 ]; then
    echo "Successfully generated STL files in: ${OUTPUT_DIR}"
else
    echo "Error encountered during conversion for ${DERIVS_DIR}"
fi

echo "--------------------------------------------------"
echo "Conversion task complete."