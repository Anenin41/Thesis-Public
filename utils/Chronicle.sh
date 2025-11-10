#!/usr/bin/env bash
#
# Author:   Konstantinos Garas
# E-mail:   kgaras041@gmail.com
# Created:  Wed 29 Oct 2025 @ 13:53:50 +0100
# Modified: Mon 10 Nov 2025 @ 13:10:02 +0100

# Description:
#   Safe incremental backup of the Git repo (excluding the .git file) to the
#   Alexandria samba share.

# Mount the Alexandria Samba share
librarian mount

set -Eeuo pipefail

print_usage() {
  local code="${1:-1}"
  if [[ "$code" -eq 0 ]]; then
    cat <<'USAGE'
Usage: Chronicle.sh [-s SRC] [-d DEST] [-x EXCLUDE_FILE] [-l LOGFILE] [-n] [-h]

Examples:
  # Backup using defaults (DEST required)
  Chronicle.sh -d /mnt/samba/thesis_backups

  # Specify source, destination and run as dry-run
  Chronicle.sh -s ~/Documents/Git/thesis -d /mnt/samba/thesis_backups -n

Options:
  -s SRC        Source directory to backup (default: auto-detected or FIXED_SRC)
  -d DEST       Destination base directory (required)
  -x FILE       Exclude patterns file (rsync --exclude-from)
  -l FILE       Path to logfile
  -n            Dry-run (no changes)
  -h            Show this help and exit 0

Description:
  Safe incremental backup of the Git repo (excluding .git) to the Alexandria samba share.
USAGE
    exit 0
  else
    sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "$code"
  fi
}

# Pure-shell path resolver
resolve_path() {
  # Expand leading ~ if present (tilde expansion only works unquoted)
  case "$1" in
    "~"|"~/"*) eval "printf '%s\n' $1"; return ;;
  esac
  if command -v realpath >/dev/null 2>&1; then
    # -m keeps non-existing paths sane
    realpath -m -- "$1"
  elif command -v readlink >/dev/null 2>&1; then
    # GNU readlink -f resolves symlinks; on Linux this is available
    readlink -f -- "$1"
  else
    # Fallback: approximate absolute path
    local d b
    d=$(dirname -- "$1") || return 0
    b=$(basename -- "$1") || return 0
    (cd "$d" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$b") || printf '%s\n' "$1"
  fi
}

# Fixed SRC & Base
FIXED_SRC="$HOME/Documents/Git/thesis"
FIXED_DEST_BASE="$HOME/alexandria/"

# Defaults
if command -v git >/dev/null 2>&1 && git -C "$FIXED_SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SRC_DIR="$(git -C "$FIXED_SRC" rev-parse --show-toplevel)"
else
  SRC_DIR="$FIXED_SRC"
fi
DEST_BASE="$FIXED_DEST_BASE"
EXCLUDE_FILE=""
LOGFILE=""
DRY_RUN=0

while getopts ":s:d:x:l:nh" opt; do
  case "$opt" in
    s) SRC_DIR="${OPTARG}" ;;
    d) DEST_BASE="${OPTARG}" ;;
    x) EXCLUDE_FILE="${OPTARG}" ;;
    l) LOGFILE="${OPTARG}" ;;
    n) DRY_RUN=1 ;;
    h) print_usage 0 ;;
    *) print_usage ;;
  esac
done

if [[ -z "${DEST_BASE}" ]]; then
  echo "ERROR: Destination (-d) is required (e.g., /mnt/samba/thesis_backups)" >&2
  print_usage
fi

SRC_DIR="$(resolve_path "$SRC_DIR")"
DEST_BASE="$(resolve_path "$DEST_BASE")"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: Source directory not found: $SRC_DIR" >&2
  exit 2
fi

REPO_NAME="$(basename "$SRC_DIR")"
DEST_DIR="${DEST_BASE%/}/${REPO_NAME}"

# Prevent overlapping runs (cron-safe)
LOCK_FD=9
LOCK_FILE="/tmp/thesis_backup_${REPO_NAME}.lock"
exec {LOCK_FD}> "$LOCK_FILE"
if ! flock -n "$LOCK_FD"; then
  echo "Another backup for ${REPO_NAME} is already running. Exiting."
  exit 0
fi

log() {
  local msg="[$(date '+%d-%m-%Y %H:%M:%S')] $*"
  echo "$msg"
  if [[ -n "$LOGFILE" ]]; then
    mkdir -p "$(dirname "$LOGFILE")" || true
    echo "$msg" >> "$LOGFILE"
  fi
}

# Destination checks
if [[ ! -d "$DEST_BASE" ]]; then
  log "Destination base does not exist, creating: $DEST_BASE"
  mkdir -p "$DEST_BASE"
fi

MARKER="${DEST_BASE}/.__backup_write_test__"
if ! ( : > "$MARKER" ) 2>/dev/null; then
  log "ERROR: Destination not writable: $DEST_BASE (is the Samba share mounted?)"
  exit 3
else
  rm -f "$MARKER" || true
fi

mkdir -p "$DEST_DIR"

# rsync options
RSYNC_OPTS=(
  -avh
  --delete-after
  --delay-updates
  --partial
  --partial-dir=.rsync-partial
  --no-whole-file
  --itemize-changes
  --human-readable
  --safe-links
  --exclude ".git/"
  --filter=": /.sambaignore"
  --no-perms
  --no-owner
  --no-group
  --omit-dir-times
  --modify-window=2
  --chmod=Du=rwx,Dgo=,Fu=rw,Fgo=
)

if [[ -n "$EXCLUDE_FILE" ]]; then
  if [[ -f "$EXCLUDE_FILE" ]]; then
    RSYNC_OPTS+=( --exclude-from="$EXCLUDE_FILE" )
  else
    log "WARN: Exclude file not found: $EXCLUDE_FILE (ignoring)"
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  RSYNC_OPTS+=( --dry-run )
  log "Running in DRY-RUN mode (no changes will be made)."
fi

log "Starting backup"
log "Source:      $SRC_DIR"
log "Destination: $DEST_DIR"

# Run rsync without aborting on non-zero
set +e
rsync "${RSYNC_OPTS[@]}" "$SRC_DIR"/ "$DEST_DIR"/
RSYNC_RC=$?
set -e

decode_rsync_rc() {
  case "$1" in
    0)  echo "Success";;
    23) echo "Partial transfer (some files/attrs couldn’t be handled).";;
    24) echo "Partial transfer (files vanished while syncing).";;
    20) echo "Received signal (aborted).";;
    30) echo "Timeout.";;

    5)  echo "Client/server I/O error.";;

    *)  echo "Unhandled rsync code $1. See 'man rsync' EXIT VALUES.";;

  esac
}

EXIT_CODE=0
if [[ $RSYNC_RC -eq 0 ]]; then
  log "Backup completed successfully."
elif [[ $RSYNC_RC -eq 23 || $RSYNC_RC -eq 24 ]]; then
  # Treat the common “partial but OK” cases as success for backups to SMB/GVFS.
  log "Backup finished with warnings: $(decode_rsync_rc "$RSYNC_RC")"
else
  log "ERROR: rsync failed: $(decode_rsync_rc "$RSYNC_RC")"
  EXIT_CODE=$RSYNC_RC
fi

# Detect if the script was 'sourced' (so we can 'return' instead of 'exit')
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  SOURCED=1
else
  SOURCED=0
fi

# If run interactively (has a TTY), pause so the window doesn't vanish
if [[ -t 1 && -z "${CI:-}" ]]; then
  if [[ ${EXIT_CODE:-0} -eq 0 ]]; then
    read -n1 -s -r -p "Backup finished. Press any key to close..." ; echo
  else
    read -n1 -s -r -p "Backup FAILED (code ${EXIT_CODE:-1}). Press any key to close..." ; echo
  fi
fi

# Return if sourced; otherwise exit
if [[ $SOURCED -eq 1 ]]; then
  return "${EXIT_CODE:-0}"
else
  exit "${EXIT_CODE:-0}"
fi

