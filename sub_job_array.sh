#!/bin/bash
#SBATCH --job-name=In2O3
#SBATCH --array=0-1287%20
#SBATCH --partition=htc
#SBATCH --qos=public
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=128
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
#SBATCH --time=03:50:00
#SBATCH --output=logs/disp_%A_%a.out
#SBATCH --error=logs/disp_%A_%a.err

set -uo pipefail

# ---------------------------- environment ----------------------------------
VASP_EXE="$HOME/vasp/bin/vasp_std"

set +u
source "$HOME/intel/oneapi/setvars.sh" --force >/dev/null 2>&1 || true
set -u

# Enable -e only after the environment is up.
set -e

export MKL_ENABLE_INSTRUCTIONS=AVX2
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OMP_STACKSIZE=512m
ulimit -s unlimited || echo "NOTE: could not raise stack limit; continuing." >&2

# ---------------------------- job setup ------------------------------------
CALC_ROOT="${SLURM_SUBMIT_DIR}/3ph"
DISP=$(printf "%04d" "${SLURM_ARRAY_TASK_ID:-0}")
WORKDIR="${CALC_ROOT}/${DISP}"

if [[ ! -d "${WORKDIR}" ]]; then
    echo "ERROR: ${WORKDIR} does not exist." >&2
    exit 1
fi

cd "${WORKDIR}"

for f in INCAR KPOINTS POSCAR POTCAR; do
    if [[ ! -s "${f}" ]]; then
        echo "ERROR: missing or empty ${f} in ${WORKDIR}" >&2
        exit 1
    fi
done

# Skip work that is already finished (idempotent resubmission).
if [[ -f OUTCAR ]] && grep -q "General timing and accounting" OUTCAR; then
    echo "Displacement ${DISP} already completed - nothing to do."
    exit 0
fi

# Archive any partial output from a previous attempt rather than overwriting.
# WAVECAR/CHGCAR are included: VASP defaults to ISTART=1 when a WAVECAR exists,
# so a truncated one from a killed run would be silently read back in.
if [[ -f OUTCAR || -f WAVECAR ]]; then
    STAMP=$(date +%Y%m%d_%H%M%S)
    mkdir -p "failed_${STAMP}"
    mv -f OUTCAR OSZICAR vasprun.xml CONTCAR WAVECAR CHG CHGCAR \
          "failed_${STAMP}/" 2>/dev/null || true
    echo "Archived incomplete previous run to failed_${STAMP}/"
fi

RC=0
mpirun -np "${SLURM_NTASKS}" "${VASP_EXE}" || RC=$?

echo "--------------------------------------------------------------"
echo " Finished : $(date)"
echo " Exit code: ${RC}"

if grep -q "General timing and accounting" OUTCAR 2>/dev/null; then
    echo " Status   : OUTCAR reports a clean finish."
    # `|| true`: under pipefail a pattern miss would otherwise abort the script
    # here, skipping both the cleanup and the exit code below.
    grep -E "free +energy +TOTEN|reached required accuracy" OUTCAR | tail -n 2 || true
    # Only trim bulky files on success -- a failed run needs WAVECAR to restart.
    rm -f CHG CHGCAR WAVECAR
else
    echo " Status   : WARNING - OUTCAR has no clean termination line." >&2
    echo "            Leaving WAVECAR/CHG* in place for restart or diagnosis." >&2
    RC=1
fi
echo "--------------------------------------------------------------"

exit ${RC}
