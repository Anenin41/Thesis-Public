#!/usr/bin/env bash

# Chronicle.sh
# Safe incremental backup of the Git repo (excluding the .git file) to the 
# Alexandria samba share. It performs as follows:
# - mounts the private samba share
# - resolves and validates paths
# - enforces a single run at a time (in case it is used as a chronjob)
# - supports dry run and logging
# - excludes the `.git/` folder and file patterns from a root ignore file
# - tunes rsync for network shares (partial, itemized changes, same permissions)
# - reads rsync exit codes and pauses on completion when run interactively

# This bash script contains SHELL EXIT CODES, here is a short list of them:
# - Exit code 0:	Success
# - Exit code 1:	General errors, misc errors (e.g. divide by 0)
# - Exit code 2:	Misuse of shell builtins (e.g. empty function)

# Mount the Alexandria Samba share
librarian mount

# Make the script strict: exit on errors/undefined variables; abort at pipe fails
set -Eeuo pipefail

# Print a help block (when -h is parsed as an argument)
print_usage() {
  local code="${1:-1}"
  if [[ "$code" -eq 0 ]]; then
    cat <<'USAGE'
Usage: Chronicle.sh [-s SRC] [-d DEST] [-x EXCLUDE_FILE] [-l LOGFILE] [-n] [-h]

Options:
  -s SRC        Source directory to backup (default: auto-detected or FIXED_SRC)
  -d DEST       Destination base directory (required)
  -x FILE       Exclude patterns file (rsync --exclude-from)
  -l FILE       Path to logfile
  -n            Dry-run (no changes)
  -h            Show this help and exit 0

Description:
  Safe incremental backup of the Git repo (excluding .git and file patterns in .sambaignore) to the Alexandria samba share.
USAGE
    exit 0
  else
    sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "$code"
  fi
}

# Expands ~ to $HOME, guarantees absolute paths
resolve_path() {
  # Expand leading ~ if present (tilde expansion only works unquoted)
  case "$1" in
    "~"|"~/"*) eval "printf '%s\n' $1"; return ;;
  esac
  if command -v realpath >/dev/null 2>&1; then
    # -m keeps non-existing paths sane
    realpath -m -- "$1"
  elif command -v readlink >/dev/null 2>&1; then
    # GNU readlink -f resolves symlinks
    readlink -f -- "$1"
  else
    # Fallback: approximate absolute path
    local d b
    d=$(dirname -- "$1") || return 0
    b=$(basename -- "$1") || return 0
    (cd "$d" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$b") || printf '%s\n' "$1"
  fi
}

# Fixed source and base directories
FIXED_SRC="$HOME/Documents/Git/thesis"
FIXED_DEST_BASE="$HOME/alexandria/"

# Defaults
# FIXED_SRC is a git repo, so SRC_DIR becomes its top-level via an if statement
if command -v git >/dev/null 2>&1 && git -C "$FIXED_SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SRC_DIR="$(git -C "$FIXED_SRC" rev-parse --show-toplevel)"
else
  SRC_DIR="$FIXED_SRC"
fi
DEST_BASE="$FIXED_DEST_BASE"
EXCLUDE_FILE=""
LOGFILE=""
DRY_RUN=0

# Command Line parsing
while getopts ":s:d:x:l:nh" opt; do
  case "$opt" in
    s) SRC_DIR="${OPTARG}" ;;		# manually override source dir
    d) DEST_BASE="${OPTARG}" ;;		# manually set destination base dir
    x) EXCLUDE_FILE="${OPTARG}" ;;	# manually exclude a file pattern
    l) LOGFILE="${OPTARG}" ;;		# keep logs into the target file
    n) DRY_RUN=1 ;;			# dry run (no changes implemented)
    h) print_usage 0 ;;			# prints the usage block above
    *) print_usage ;;
  esac
done

# Sanity check, verify that the destination directory (samba share) is mounted
if [[ -z "${DEST_BASE}" ]]; then
  echo "ERROR: Destination (-d) is required (e.g., /mnt/samba/thesis_backups)" >&2
  print_usage
fi

SRC_DIR="$(resolve_path "$SRC_DIR")"
DEST_BASE="$(resolve_path "$DEST_BASE")"

# Sanity check, verify the source directory otherwise exit with code 2
if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: Source directory not found: $SRC_DIR" >&2
  exit 2
fi

REPO_NAME="$(basename "$SRC_DIR")"
DEST_DIR="${DEST_BASE%/}/${REPO_NAME}"

# Prevent overlapping runs (cron-safe) via a temporary lock file
# If another backup is initiated, it exits with code 0
LOCK_FD=9
LOCK_FILE="/tmp/thesis_backup_${REPO_NAME}.lock"
exec {LOCK_FD}> "$LOCK_FILE"
if ! flock -n "$LOCK_FD"; then
  echo "Another backup for ${REPO_NAME} is already running. Exiting."
  exit 0
fi

# Logging actions helper according to the CORRECT date format, not the idiotic
# format the Americans use
log() {
  local msg="[$(date '+%d-%m-%Y %H:%M:%S')] $*"
  echo "$msg"
  if [[ -n "$LOGFILE" ]]; then
    mkdir -p "$(dirname "$LOGFILE")" || true
    echo "$msg" >> "$LOGFILE"
  fi
}

# Sanity check, ensures the destination folder exists
if [[ ! -d "$DEST_BASE" ]]; then
  log "Destination base does not exist, creating: $DEST_BASE"
  mkdir -p "$DEST_BASE"
fi

# ENSURE the destination directory is WRITABLE (because it is a samba share)
# If it is NOT, then exit with code 3
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
  -avh				                   # archive + verbose + human sizes
  --delete-after		             # delete files that are not in src AFTER backup
  --delay-updates		             # delays update until file transfer is complete
  --partial			                 # handle interrupted file transfers
  --partial-dir=.rsync-partial	 # same for whole directories
  --no-whole-file		             # enable delta-transfer alg. 
  --itemize-changes		           # detailed info while syncing data
  --human-readable		           # output easier to understand
  --safe-links			             # enhance security when handling symbolic links
  --exclude ".git/"		           # forcefully exclude .git/
  --filter=": /.sambaignore"	   # exclude file patterns (binaries, execs, etc)
  --no-perms			               # no permissions of transferred files
  --no-owner			               # prevent ownership of transferred files
  --no-group			               # prevent group ownership of transferred files
  --omit-dir-times		           # don't update modification times of dirs
  --modify-window=2		           # time window to determine file changes
  --chmod=Du=rwx,Dgo=,Fu=rw,Fgo= # set specific (non exec) perms to files in dest
)

# If -x FILE is provided, additionally exclude it from the backup process
if [[ -n "$EXCLUDE_FILE" ]]; then
  if [[ -f "$EXCLUDE_FILE" ]]; then
    RSYNC_OPTS+=( --exclude-from="$EXCLUDE_FILE" )
  else
    log "WARN: Exclude file not found: $EXCLUDE_FILE (ignoring)"
  fi
fi

# If -n is parsed, dry run the whole script
if [[ "$DRY_RUN" -eq 1 ]]; then
  RSYNC_OPTS+=( --dry-run )
  log "Running in DRY-RUN mode (no changes will be made)."
fi

# Log the time the backup started, the source dir and the target dir
log "Starting backup"
log "Source:      $SRC_DIR"
log "Destination: $DEST_DIR"

# Run rsync without aborting on non-zero
set +e
rsync "${RSYNC_OPTS[@]}" "$SRC_DIR"/ "$DEST_DIR"/
RSYNC_RC=$?
set -e

# Treat rsync exit codes as partial successes and provide adequate comments
decode_rsync_rc() {
  case "$1" in
    0)  echo "Success";;
    23) echo "Partial transfer (some files/attrs couldn't be handled).";;
    24) echo "Partial transfer (files vanished while syncing).";;
    20) echo "Received signal (aborted).";;
    30) echo "Timeout.";;

    5)  echo "Client/server I/O error.";;

    *)  echo "Unhandled rsync code $1. See 'man rsync' EXIT VALUES.";;

  esac
}

# Other non-zero rsync codes, log the errors and set the EXIT_CODE to the rsync
# code for manual debugging
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

# Detect if the script was 'sourced' so it can 'return' instead of 'exit'
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  SOURCED=1
else
  SOURCED=0
fi

# If run interactively, pause so the window doesn't vanish as it does when run
# inside a chronjob
if [[ -t 1 && -z "${CI:-}" ]]; then
  if [[ ${EXIT_CODE:-0} -eq 0 ]]; then
    read -n1 -s -r -p "Backup finished. Press any key to close..." ; echo
  else
    read -n1 -s -r -p "Backup FAILED (code ${EXIT_CODE:-1}). Press any key to close..." ; echo
  fi
fi

# Return if sourced, otherwise exit
if [[ $SOURCED -eq 1 ]]; then
  return "${EXIT_CODE:-0}"
else
  exit "${EXIT_CODE:-0}"
fi

