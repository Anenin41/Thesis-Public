#!/usr/bin/env bash
#
# Author:   Konstantinos Garas
# E-mail:   kgaras041@gmail.com
# Created:  Mon 10 Nov 2025 @ 12:50:46 +0100
# Modified: Mon 10 Nov 2025 @ 19:12:20 +0100

# CopyCat.sh:
# Copy a filtered subset of a fixed source tree into a fixed destination folder
# and optionally commit+push into a GitHub repository.
#
# Expected Path:	~/Documents/Git/thesis/utils/CopyCat.sh
# Source Dir:		~/Documents/Git/thesis
# Dest Dir:		~/Documents/Git/thesis-public
# Ignore File:		~/Documents/Git/thesis/.copyignore

# This bash script contains SHELL EXIT CODES, here is a short list of them:
# - Exit code 0:	Success
# - Exit code 1:	General errors, misc errors (e.g. divide by 0)
# - Exit code 2:	Misuse of shell builtins (e.g. empty function)

# Locate script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Fixed destination path in a raw string
FIXED_DEST_RAW="~/Documents/Git/thesis-public"

# Expand ~ to $HOME 
expand_path() {
  local p="$1"
  [[ $p == ~* ]] && p="${p/#\~/$HOME}"
  printf '%s' "$p"
}

# Fixed source, destination, rsync filter paths and git branch
FIXED_SRC="$PROJECT_ROOT"
FIXED_DEST="$(expand_path "$FIXED_DEST_RAW")"
IGNORE_FILE="$PROJECT_ROOT/.copyignore"
BRANCH="main"

usage() {
  cat <<USAGE
Usage: CopyCat.sh [--dry-run | --apply] [-m "commit message"] [-v] [-h]

Fixed paths:
  SRC : $FIXED_SRC
  DEST: $FIXED_DEST

Project ignore file (always used if present):
  $IGNORE_FILE   (gitignore-style)

Options:
  -n, --dry-run           Preview possible changes (default)
  -a, --apply             Perform the copy and commit + push if there are changes
  -m, --message MSG       Commit message to use when applying changes
  -v, --verbose           Verbose rsync output
  -h, --help              Show this help

Notes:
- Uses .copyignore syntax like .sambaignore (e.g., - *.log, - data/, + keep.log).
- Will push to 'origin' on branch '$BRANCH' if 'origin' is configured.
- Includes ALL folders (no special 'data/' handling).
USAGE
}

# Default configurations
ACTION="dry-run"
COMMIT_MSG=""
VERBOSE=false

# Parse arguments
while [[  $# -gt 0 ]]; do
	case "$1" in
		-n|--dry-run)	ACTION="dry-run"; shift ;;
		-a|--apply)	ACTION="apply"; shift ;;
		-m|--message)	COMMIT_MSG="${2:-}"; shift 2 ;;
		-v|--verbose)	VERBOSE=true; shift ;;
		-h|--help)	usage; exit 0 ;;
		*) echo "Unknown option $1" >&2; usage; exit 1 ;;
	esac
done

# Validate source and destination folders
[[ -d "$FIXED_SRC" ]] || { 
	echo "Error: source '$FIXED_SRC' not found." >&2; exit 1; 
}
mkdir -p "$FIXED_DEST"

# Resolve absolute paths (expand ~ to $HOME, etc...)
if command -v realpath >/dev/null 2>&1; then
  SRC_ABS=$(realpath "$FIXED_SRC")
  DEST_ABS=$(realpath "$FIXED_DEST")
else
  SRC_ABS=$(
  python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$FIXED_SRC")
  DEST_ABS=$(
  python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$FIXED_DEST")
fi

# Build rsync options
RSYNC_OPTS=(
	-a 			# archive mode (keep perms, times, symlinks, etc)
	--itemize-changes 	# show what changed
	--delete-after 		# clean up removed files after backup
	--exclude ".git/" 	# Never copy the privater repo's .git
)

# Verbose control
$VERBOSE && RSYNC_OPTS+=(-v)
[[ "$ACTION" == "dry-run" ]] && RSYNC_OPTS+=(-n)

# Apply the fixed ignore file if present (IT SHOULD BE ALWAYS PRESENT)
if [[ -f "$IGNORE_FILE" ]]; then
	if grep -Eq '^\s*[-+]' "$IGNORE_FILE"; then
		RSYNC_OPTS+=(--filter=": $IGNORE_FILE")
  		echo "Using rsync filter: $IGNORE_FILE"
	else
		echo ".gitignore syntax not supported for .copyignore"
	fi
else
	echo "Note: project ignore file not found at '$IGNORE_FILE'."
fi

# Execute rsync
echo "CopyCat"
echo "    rsync ($ACTION)"
echo "    SRC : $SRC_ABS"
echo "    DEST: $DEST_ABS"

set +e
RSYNC_OUTPUT=$(rsync "${RSYNC_OPTS[@]}" "$SRC_ABS"/ "$DEST_ABS"/ 2>&1)
RSYNC_STATUS=$?
set -e

# If rsync failed, exit and return the RSYNC_STATUS (error code)
if [[ $RSYNC_STATUS -ne 0 ]]; then
  echo "$RSYNC_OUTPUT"
  echo "Error: rsync failed." >&2
  exit $RSYNC_STATUS
fi

echo "rsync report:"
echo "$RSYNC_OUTPUT" | sed '/^$/d' || true

# Stop if dry run
if [[ "$ACTION" == "dry-run" ]]; then
  echo "Dry run complete. No changes; no git ops."

  exit 0
fi

# Apply mode: commit + push
pushd "$DEST_ABS" >/dev/null

# Ensure on 'main'
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD || echo "")
[[ "$CURRENT_BRANCH" == "$BRANCH" ]] || git checkout -B "$BRANCH"

echo "Staging & committing..."
git add -A
if git diff --cached --quiet; then
  echo "No staged changes."
else
  [[ -z "$COMMIT_MSG" ]] && COMMIT_MSG="Auto-sync: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  git commit -m "$COMMIT_MSG"
fi

# Push if remote 'origin' exists
if git remote get-url origin >/dev/null 2>&1; then
  echo "Pushing to origin/$BRANCH..."
  if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    git push origin "$BRANCH"
  else
    git push -u origin "$BRANCH"
  fi
else
  echo "    No 'origin' remote set; skipping push."
fi

popd >/dev/null
echo "Done."
