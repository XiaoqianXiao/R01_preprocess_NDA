#!/usr/bin/env bash
set -euo pipefail

# Download Flywheel DICOM sessions by session timestamp and optional subject ID.
#
# Usage:
#   export FW_KEY='...'
#   START_DATE=2026-06-22 LIST_ONLY=1 ./download_bids_subjects_on_hyak_byTime.sh
#   START_DATE=2026-06-22 LIST_ONLY=0 ./download_bids_subjects_on_hyak_byTime.sh
#   LIST_ONLY=1 ./download_bids_subjects_on_hyak_byTime.sh --subID 105
#   START_DATE=2024-10-07 LIST_ONLY=0 ./download_bids_subjects_on_hyak_byTime.sh --subID 105
#   SUBID=105 LIST_ONLY=0 ./download_bids_subjects_on_hyak_byTime.sh
#   EXTRACT_AFTER=1 KEEP_TARS=1 LIST_ONLY=0 ./download_bids_subjects_on_hyak_byTime.sh
#
# If the Apptainer image does not already include the Flywheel Python SDK,
# this script installs an isolated copy under /DATA_DIR/.flywheel-sdk-python.
# Set INSTALL_SDK=0 to fail instead of installing.
# Set RUN_FW_LOGIN=1 only if fw download reports an authentication error.
#
# Notes:
#   - fw sync --include only filters file types, not dates.
#   - This script first queries sessions by date, writes a CSV manifest, then
#     downloads each matching session file-by-file using the Flywheel Python SDK.
#   - Set DOWNLOAD_MODE=tar only if you specifically want to use fw download.
#   - Subject IDs must match the Flywheel subject label exactly.
#   - Omit the subject ID to include all subjects; START_DATE still applies.
#   - TARGET_SUBJECT remains supported; --subID overrides environment settings.
#   - Missing Slurm directories are excluded from Apptainer system binds so
#     downloads can run on login nodes without those directories.

usage() {
    cat <<'USAGE'
Usage: download_bids_subjects_on_hyak_byTime.sh [--subID SUBJECT_ID]

  --subID, --sub-id SUBJECT_ID  Select an exact Flywheel subject label.
  -h, --help                  Show this help.

Environment:
  SUBID / TARGET_SUBJECT      Optional subject label (SUBID takes precedence).
  START_DATE                  Earliest session date (default: 2024-10-07).
  LIST_ONLY                   1: write manifest only (default); 0: download.
  FW_KEY                      Flywheel API key (required).

Without a subject selection, all subjects are queried. The date filter applies
to both subject-specific and project-wide queries.
USAGE
}

TARGET_SUBJECT="${SUBID-${TARGET_SUBJECT:-}}"
while (( $# > 0 )); do
    case "$1" in
        --subID|--sub-id)
            if (( $# < 2 )) || [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: $1 requires a subject ID." >&2
                exit 1
            fi
            TARGET_SUBJECT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

IMAGE="${IMAGE:-/gscratch/fang/images/flywheel.sif}"
#BIND_SRC="${BIND_SRC:-/gscratch/fang/IFOCUS/sourcedata/MRI}"
BIND_SRC="${BIND_SRC:-/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/dicom}"
BIND_DEST="${BIND_DEST:-/DATA_DIR}"
PROJECT_PATH="${PROJECT_PATH:-fang-lab/IFOCUS}"
START_DATE="${START_DATE:-2024-10-07}"
LIST_ONLY="${LIST_ONLY:-1}"
JOBS="${JOBS:-1}"
MANIFEST_NAME="sessions_${TARGET_SUBJECT:-all}_since_${START_DATE}.csv"
MANIFEST="${MANIFEST:-${BIND_DEST}/${MANIFEST_NAME}}"
INSTALL_SDK="${INSTALL_SDK:-1}"
EXTRACT_AFTER="${EXTRACT_AFTER:-1}"
KEEP_TARS="${KEEP_TARS:-1}"
RUN_FW_LOGIN="${RUN_FW_LOGIN:-0}"
DOWNLOAD_MODE="${DOWNLOAD_MODE:-files}"

if [[ -z "${FW_KEY:-}" ]]; then
    echo "Error: FW_KEY is not set. Run: export FW_KEY='your_flywheel_api_key'" >&2
    exit 1
fi

if [[ "${LIST_ONLY}" != "0" && "${LIST_ONLY}" != "1" ]]; then
    echo "Error: LIST_ONLY must be 0 or 1." >&2
    exit 1
fi

if [[ "${INSTALL_SDK}" != "0" && "${INSTALL_SDK}" != "1" ]]; then
    echo "Error: INSTALL_SDK must be 0 or 1." >&2
    exit 1
fi

if [[ "${EXTRACT_AFTER}" != "0" && "${EXTRACT_AFTER}" != "1" ]]; then
    echo "Error: EXTRACT_AFTER must be 0 or 1." >&2
    exit 1
fi

if [[ "${KEEP_TARS}" != "0" && "${KEEP_TARS}" != "1" ]]; then
    echo "Error: KEEP_TARS must be 0 or 1." >&2
    exit 1
fi

if [[ "${RUN_FW_LOGIN}" != "0" && "${RUN_FW_LOGIN}" != "1" ]]; then
    echo "Error: RUN_FW_LOGIN must be 0 or 1." >&2
    exit 1
fi

if [[ "${DOWNLOAD_MODE}" != "files" && "${DOWNLOAD_MODE}" != "tar" ]]; then
    echo "Error: DOWNLOAD_MODE must be files or tar." >&2
    exit 1
fi

# Hyak may configure Slurm system binds that only exist on compute nodes.
# This downloader does not need Slurm; disable missing binds individually.
apptainer_command=(apptainer exec)
for slurm_path in /var/run/slurm /var/spool/slurmd; do
    if [[ ! -e "${slurm_path}" ]]; then
        echo "Skipping missing Slurm system bind: ${slurm_path}"
        apptainer_command+=(--no-mount "${slurm_path}")
    fi
done

"${apptainer_command[@]}" \
    --env FW_KEY="${FW_KEY}" \
    --env FW_HOST="${FW_HOST:-}" \
    -B "${BIND_SRC}:${BIND_DEST}" \
    "${IMAGE}" \
    bash -s -- "${START_DATE}" "${LIST_ONLY}" "${MANIFEST}" "${PROJECT_PATH}" "${BIND_DEST}" "${JOBS}" "${INSTALL_SDK}" "${EXTRACT_AFTER}" "${KEEP_TARS}" "${RUN_FW_LOGIN}" "${DOWNLOAD_MODE}" "${TARGET_SUBJECT}" <<'CONTAINER_SCRIPT'
set -euo pipefail

START_DATE="$1"
LIST_ONLY="$2"
MANIFEST="$3"
PROJECT_PATH="$4"
BIND_DEST="$5"
JOBS="$6"
INSTALL_SDK="$7"
EXTRACT_AFTER="$8"
KEEP_TARS="$9"
RUN_FW_LOGIN="${10}"
DOWNLOAD_MODE="${11}"
TARGET_SUBJECT="${12}"

FLYWHEEL_SDK_TARGET="${FLYWHEEL_SDK_TARGET:-${BIND_DEST}/.flywheel-sdk-python}"
export PYTHONNOUSERSITE=1
export PYTHONPATH="${FLYWHEEL_SDK_TARGET}${PYTHONPATH:+:${PYTHONPATH}}"

normalize_flywheel_key() {
    FW_KEY="$(printf '%s' "${FW_KEY}" | tr -d '[:space:]')"
    FW_KEY="${FW_KEY#https://}"
    FW_KEY="${FW_KEY#http://}"

    if [[ "${FW_KEY}" != *:* ]]; then
        if [[ -z "${FW_HOST:-}" ]]; then
            cat >&2 <<MSG
Error: FW_KEY is not in Flywheel SDK format.

Set either:
  export FW_KEY="uw-chn.flywheel.io:YOUR_API_KEY"

or, if you only copied the token portion:
  export FW_HOST="uw-chn.flywheel.io"
  export FW_KEY="YOUR_API_KEY"
MSG
            exit 1
        fi

        FW_HOST="$(printf '%s' "${FW_HOST}" | tr -d '[:space:]')"
        FW_HOST="${FW_HOST#https://}"
        FW_HOST="${FW_HOST#http://}"
        FW_HOST="${FW_HOST%%/*}"
        FW_KEY="${FW_HOST}:${FW_KEY}"
    fi

    export FW_KEY
}

normalize_flywheel_key

check_flywheel_sdk() {
    python3 - <<'PY'
import sys

try:
    import flywheel
except Exception as exc:
    print(f"Flywheel Python SDK import failed: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not hasattr(flywheel, "Client"):
    print(
        "Imported a flywheel module without flywheel.Client. "
        "This is usually the wrong package or an old SDK.",
        file=sys.stderr,
    )
    print(f"flywheel module path: {getattr(flywheel, '__file__', '<unknown>')}", file=sys.stderr)
    print(f"flywheel version: {getattr(flywheel, '__version__', '<unknown>')}", file=sys.stderr)
    raise SystemExit(1)
PY
}

if ! check_flywheel_sdk; then
    if [[ "${INSTALL_SDK}" == "1" ]]; then
        echo "Flywheel Python SDK is missing or incompatible; installing/upgrading flywheel-sdk into ${FLYWHEEL_SDK_TARGET}."
        mkdir -p "${FLYWHEEL_SDK_TARGET}"
        python3 -m pip install --target "${FLYWHEEL_SDK_TARGET}" --upgrade --ignore-installed flywheel-sdk
        check_flywheel_sdk
    else
        cat >&2 <<MSG
Error: The Flywheel Python SDK is not installed or does not expose flywheel.Client in this Apptainer image.

The fw CLI can download data, but it cannot filter sessions by timestamp.
This script needs the Python SDK only for the date query step.

Rerun with:
  INSTALL_SDK=1 START_DATE=${START_DATE} LIST_ONLY=${LIST_ONLY} bash download_bids_subjects_on_hyak_byTime.sh

The SDK would be installed under:
  ${FLYWHEEL_SDK_TARGET}
MSG
        exit 1
    fi
fi

python3 - "$START_DATE" "$MANIFEST" "$PROJECT_PATH" "$TARGET_SUBJECT" <<'PY'
import csv
from datetime import date, datetime
import os
import sys

import flywheel

if not hasattr(flywheel, "Client"):
    raise RuntimeError(
        "Imported flywheel module does not expose Client. "
        f"module={getattr(flywheel, '__file__', '<unknown>')} "
        f"version={getattr(flywheel, '__version__', '<unknown>')}"
    )

start_date, manifest, project_path, target_subject = sys.argv[1:5]
start_day = date.fromisoformat(start_date)

fw = flywheel.Client(os.environ["FW_KEY"])
project = fw.lookup(project_path)


def timestamp_date(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    text = str(value)
    if len(text) >= 10:
        return date.fromisoformat(text[:10])
    return None

rows = []
# Fetch target subject directly if supplied, otherwise iterate whole project
if target_subject:
    subject_path = f"{project_path}/{target_subject}"
    try:
        subject_obj = fw.lookup(subject_path)
        subject_sessions = list(subject_obj.sessions.iter_find())
    except Exception as exc:
        raise SystemExit(f"Error: Could not lookup subject path '{subject_path}': {exc}")

    for session in subject_sessions:
        session_day = timestamp_date(getattr(session, "timestamp", None))
        if session_day is None or session_day < start_day:
            continue

        full_session = fw.get(session.id)
        timestamp = getattr(full_session, "timestamp", "") or ""
        rows.append(
            {
                "subject_label": target_subject,
                "session_label": getattr(full_session, "label", ""),
                "session_id": full_session.id,
                "timestamp": str(timestamp),
                "download_path": (
                    f"{project_path}/"
                    f"{target_subject}/"
                    f"{getattr(full_session, 'label', '')}"
                ),
            }
        )
else:
    for session in project.sessions.iter_find():
        session_day = timestamp_date(getattr(session, "timestamp", None))
        if session_day is None or session_day < start_day:
            continue

        full_session = fw.get(session.id)
        subject_id = full_session.parents.subject
        subject = fw.get(subject_id) if subject_id else None
        subj_label = getattr(subject, "label", "") if subject else ""
        timestamp = getattr(full_session, "timestamp", "") or ""

        rows.append(
            {
                "subject_label": subj_label,
                "session_label": getattr(full_session, "label", ""),
                "session_id": full_session.id,
                "timestamp": str(timestamp),
                "download_path": (
                    f"{project_path}/"
                    f"{subj_label}/"
                    f"{getattr(full_session, 'label', '')}"
                ),
            }
        )

rows.sort(key=lambda row: (row["timestamp"], row["subject_label"], row["session_label"]))
os.makedirs(os.path.dirname(manifest), exist_ok=True)

with open(manifest, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "subject_label",
            "session_label",
            "session_id",
            "timestamp",
            "download_path",
        ],
    )
    writer.writeheader()
    writer.writerows(rows)

print(f"Wrote {len(rows)} sessions to {manifest}")
PY

echo "Manifest:"
echo "  ${MANIFEST}"

if [[ "${LIST_ONLY}" == "1" ]]; then
    echo "LIST_ONLY=1, so no data were downloaded."
    echo "Review the manifest, then rerun with LIST_ONLY=0 to download."
    exit 0
fi

if [[ "${DOWNLOAD_MODE}" == "files" ]]; then
    download_one_file() {
        acquisition_id="$1"
        file_name="$2"
        out_path="$3"
        expected_size="$4"
        rel_path="$5"

        python3 - "$acquisition_id" "$file_name" "$out_path" "$expected_size" "$rel_path" <<'PY'
import os
import sys

import flywheel

if not hasattr(flywheel, "Client"):
    raise RuntimeError(
        "Imported flywheel module does not expose Client. "
        f"module={getattr(flywheel, '__file__', '<unknown>')} "
        f"version={getattr(flywheel, '__version__', '<unknown>')}"
    )

acquisition_id, file_name, out_path, expected_size, rel_path = sys.argv[1:6]
expected_size = int(expected_size) if expected_size else None

if (
    expected_size is not None
    and os.path.exists(out_path)
    and os.path.getsize(out_path) == expected_size
):
    print(f"exists: {rel_path}")
    raise SystemExit(0)

if os.path.exists(out_path):
    os.remove(out_path)

os.makedirs(os.path.dirname(out_path), exist_ok=True)
print(f"downloading: {rel_path}", flush=True)

fw = flywheel.Client(os.environ["FW_KEY"])
acquisition = fw.get(acquisition_id)
acquisition.download_file(file_name, out_path)

if expected_size is not None and os.path.getsize(out_path) != expected_size:
    raise RuntimeError(
        f"Downloaded size mismatch for {out_path}: "
        f"expected {expected_size}, got {os.path.getsize(out_path)}"
    )
PY
    }

    export -f download_one_file
    export FW_KEY

    python3 - "$MANIFEST" "$BIND_DEST" <<'PY' | xargs -0 -n 5 -P "${JOBS}" bash -c 'download_one_file "$1" "$2" "$3" "$4" "$5"' bash
import csv
import os
import re
import sys

import flywheel

if not hasattr(flywheel, "Client"):
    raise RuntimeError(
        "Imported flywheel module does not expose Client. "
        f"module={getattr(flywheel, '__file__', '<unknown>')} "
        f"version={getattr(flywheel, '__version__', '<unknown>')}"
    )

manifest, bind_dest = sys.argv[1:3]
fw = flywheel.Client(os.environ["FW_KEY"])


def safe_name(value):
    value = (value or "").strip() or "unknown"
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value)


def file_size(file_obj):
    value = getattr(file_obj, "size", None)
    try:
        return int(value) if value is not None else None
    except (TypeError, ValueError):
        return None


with open(manifest, newline="") as f:
    rows = list(csv.DictReader(f))

for row in rows:
    subject = safe_name(row["subject_label"])
    session_label = safe_name(row["session_label"])
    session = fw.get(row["session_id"])
    session_dir = os.path.join(bind_dest, subject, session_label)
    os.makedirs(session_dir, exist_ok=True)

    acquisitions = list(session.acquisitions.iter_find())
    for acq_ref in acquisitions:
        acquisition = fw.get(acq_ref.id)
        acq_label = safe_name(getattr(acquisition, "label", "acquisition"))
        acq_dir = os.path.join(session_dir, acq_label)

        for acq_file in acquisition.files:
            if getattr(acq_file, "type", None) != "dicom":
                continue

            file_name = os.path.basename(acq_file.name)
            out_path = os.path.join(acq_dir, file_name)
            expected_size = file_size(acq_file)
            rel_path = f"{subject}/{session_label}/{acq_label}/{file_name}"
            values = [
                acquisition.id,
                acq_file.name,
                out_path,
                "" if expected_size is None else str(expected_size),
                rel_path,
            ]
            for value in values:
                sys.stdout.buffer.write(value.encode())
                sys.stdout.buffer.write(b"\0")
PY
    echo "download successfully"
    exit 0
fi

if [[ "${RUN_FW_LOGIN}" == "1" ]]; then
    fw login "${FW_KEY}"
else
    echo "Skipping fw login; using existing Flywheel CLI auth or FW_KEY environment."
fi

download_and_extract() {
    download_path="$1"
    tar_path="$2"
    extract_dir="$3"

    tar_is_valid() {
        [[ -s "${tar_path}" ]] && tar -tf "${tar_path}" >/dev/null 2>&1
    }

    if tar_is_valid; then
        echo "Found existing valid tar, skipping download: ${tar_path}"
    else
        if [[ -e "${tar_path}" ]]; then
            echo "Removing incomplete or invalid tar: ${tar_path}"
            rm -f "${tar_path}"
        fi
        echo "Downloading ${download_path} -> ${tar_path}"
        fw download --yes "${download_path}" -o "${tar_path}" --include dicom

        if ! tar_is_valid; then
            echo "Error: Downloaded tar is missing or invalid: ${tar_path}" >&2
            return 1
        fi
    fi

    if [[ "${EXTRACT_AFTER}" == "1" ]]; then
        mkdir -p "${extract_dir}"
        echo "Extracting ${tar_path} -> ${extract_dir}"
        tar -xf "${tar_path}" -C "${extract_dir}"

        nested_dir="${extract_dir}/scitran/${download_path}"
        if [[ -d "${nested_dir}" ]]; then
            echo "Flattening ${nested_dir} -> ${extract_dir}"
            shopt -s dotglob nullglob
            nested_items=("${nested_dir}"/*)
            if (( ${#nested_items[@]} > 0 )); then
                mv "${nested_items[@]}" "${extract_dir}/"
            fi
            shopt -u dotglob nullglob
            rm -rf "${extract_dir}/scitran"
        fi
    fi

    if [[ "${KEEP_TARS}" == "0" ]]; then
        rm -f "${tar_path}"
    fi
}

export EXTRACT_AFTER KEEP_TARS
export -f download_and_extract

python3 - "$MANIFEST" "$BIND_DEST" <<'PY' | xargs -0 -n 3 -P "${JOBS}" bash -c 'download_and_extract "$1" "$2" "$3"' bash
import csv
import os
import re
import sys

manifest, bind_dest = sys.argv[1:3]


def safe_name(value):
    value = value.strip() or "unknown"
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value)


with open(manifest, newline="") as f:
    for row in csv.DictReader(f):
        path = row["download_path"]
        if path:
            subject = safe_name(row["subject_label"])
            session = safe_name(row["session_label"])
            tar_path = os.path.join(bind_dest, f"{subject}_{session}.tar")
            extract_dir = os.path.join(bind_dest, subject, session)
            sys.stdout.buffer.write(path.encode())
            sys.stdout.buffer.write(b"\0")
            sys.stdout.buffer.write(tar_path.encode())
            sys.stdout.buffer.write(b"\0")
            sys.stdout.buffer.write(extract_dir.encode())
            sys.stdout.buffer.write(b"\0")
PY
echo "download successfully"
CONTAINER_SCRIPT
