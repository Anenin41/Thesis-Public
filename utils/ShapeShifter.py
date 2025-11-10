# ShapeSifter.py #
# Author: Konstantinos Garas
# E-mail: kgaras041@gmail.com // k.gkaras@student.rug.nl
# Created: Tue 28 Oct 2025 @ 23:55:06 +0100
# Modified: Wed 29 Oct 2025 @ 00:59:18 +0100

''' 
ShapeShifter Module 

What it does:
- Works on ONE fixed folder that you set once (see PAPERS_DIR below)
- Recursively finds files (PDFs by default) and:
    1. Replaces any whitespaces by underscores.
    2. If the filename already starts with a number, it preserves it but 
        normalizes the separator (e.g.  1 Paper.pdf  ->  1_Paper.pdf)
    3. If the filename does not start with a number, it assigns the NEXT index
        after the current highest one in the folder.
- Safely handles name collisions by appending a suffix (e.g. _1, _2, etc.)

Usage:
1) Edit the PAPERS_DIR variable to point to your target folder.
2) Dry-run (preview changes without renaming):
    python3 ShapeShifter.py --dry-run
3) Execute renaming:
    python3 ShapeShifter.py
4) Recursive mode (process subdirectories as well):
    python3 ShapeShifter.py --recursive    
'''

# Packages
import argparse
import platform
import re
from pathlib import Path
from typing import Optional, List, Tuple, Dict

# Config #
# Target folder
PAPERS_DIR = Path("~/Documents/Git/thesis/papers")

# Process only these extensions (case  insensitive)
EXTENSIONS = {'.pdf'}

# Build a compiled regular expression that matches whitespaces
SEP_RE = re.compile(r"[\s\-–—−]+")  # space/tab/newline/dash variants

# Captur an optional leading integer index and the remaining filename
INDEX_RE = re.compile(r"^(\d+)(?:[\s._-]+)?(.*)$")

def sanitize_component(s: str) -> str:
    """
    Sanitize a filename component by replacing whitespaces with underscores.
    """
    s = s.strip()
    s = SEP_RE.sub("_", s)
    s = re.sub(r"_+", "_", s)  # collapse multiple underscores
    return s

def split_index_and_rest(stem: str) -> Tuple[Optional[int], str]:
    """
    Split the leading index from the rest of the filename.
    Returns a tuple (index, rest_of_filename).
    If no index is found, returns (None, stem).
    """
    match = INDEX_RE.match(stem)
    if match:
        index = int(match.group(1))
        rest = match.group(2) or ""
        return index, rest
    return None, stem

def landing_time(p: Path) -> float:
    """
    When did it land timestamp.
    Linux/other: st_mtime
    """
    st = p.stat()
    sys = platform.system()
    return st.st_mtime

def unique_dest(dest: Path) -> Path:
    """
    Generate a unique destination path by appending suffixes if needed.
    """
    if not dest.exists():
        return dest
    stem, suf = dest.stem, dest.suffix
    i = 1
    while True:
        cand = dest.with_name(f"{stem}_{i}{suf}")
        if not cand.exists():
            return cand
        i += 1 

def collect_files(root: Path, recursive: bool) -> List[Path]:
    """
    Collect files with specified extensions from the root directory.
    If recursive is True, search subdirectories as well.
    """
    it = root.rglob("*") if recursive else root.glob("*")
    files = [p for p in it if p.is_file() and 
             (not EXTENSIONS or p.suffix.lower() in EXTENSIONS)]
    return files

def plan_indices(files: List[Path]) -> Tuple[List[Tuple[Path, int, str]], 
                                             Dict[Path, int]]:
    """
    Determine:
      - max existing leading index among files
      - which files need an index (don't start with a number), sorted by 
      landing time
      - mapping of unnumbered files -> assigned new indices starting at max+1
    
    Returns:
      numbered:   list of (Path, idx, rest)
      assignments: {Path -> assigned_idx}
    """
    max_idx = 0
    numbered = []    # (Path, idx, rest)
    unnumbered = []  # Path

    for p in files:
        idx, rest = split_index_and_rest(p.stem)
        if idx is not None:
            max_idx = max(max_idx, idx)
            numbered.append((p, idx, rest))
        else:
            unnumbered.append(p)

    unnumbered.sort(key=landing_time)

    assignments: Dict[Path, int] = {}
    nxt = max_idx + 1
    for p in unnumbered:
        assignments[p] = nxt
        nxt += 1

    return numbered, assignments

def build_new_filename(p: Path, keep_idx: Optional[int], 
                       assigned_idx: Optional[int]) -> str:
    """
    Build the new filename (stem + original suffix) according to rules:
      - keep_idx: preserve this index, normalize remainder
      - assigned_idx: assign this new index to an unnumbered file
    """
    if keep_idx is not None:
        _, rest = split_index_and_rest(p.stem)
        clean_rest = sanitize_component(rest) or "file"
        new_stem = f"{keep_idx}_{clean_rest}"
    elif assigned_idx is not None:
        clean_rest = sanitize_component(p.stem) or "file"
        new_stem = f"{assigned_idx}_{clean_rest}"
    else:
        new_stem = sanitize_component(p.stem)
    return f"{new_stem}{p.suffix}"

def main():
    ap = argparse.ArgumentParser(
        description=(
            "Normalize filenames and add sequential numbering  for unnumbered "   
            "files."
        )
    )
    ap.add_argument("--dry-run", action="store_true", 
                    help="Show changes without renaming.")
    ap.add_argument("--recursive", action="store_true", 
                    help="Recurse into subfolders (default: off).")
    args = ap.parse_args()

    root = PAPERS_DIR.expanduser().resolve()
    
    if not root.exists():
        ap.error(f"Path does not exist: {root}")

    files = collect_files(root, recursive=args.recursive)

    # Compute numbering plan
    numbered, assignments = plan_indices(files)

    # Pre-scan summary
    max_existing_idx = max((idx for _, idx, _ in numbered), default=0)
    print(f"Folder: {root}")
    print(f"Options: recursive={args.recursive}, dry-run={args.dry_run}")
    print(f"Scan: {len(files)} file(s) found "
          f"({len(numbered)} numbered, {len(assignments)} unnumbered). "
          f"Max existing index: {max_existing_idx}.")
    
    renamed_kept = 0
    renamed_assigned = 0

    # Normalize already-numbered files (keep their index, fix separator)
    for p, idx, _ in sorted(numbered, key=lambda t: t[0].name.lower()):
        new_name = build_new_filename(p, keep_idx=idx, assigned_idx=None)
        if new_name != p.name:
            dest = unique_dest(p.with_name(new_name))
            if args.dry_run:
                print(f"[DRY-RUN] keep {idx:>3} | {p.name}  ->  {dest.name}")
            else:
                p.rename(dest)
                print(f"[RENAMED] keep {idx:>3} | {p.name}  ->  {dest.name}")
            renamed_kept += 1

    # Assign new indices to unnumbered files in landing-time order
    for p in sorted(assignments.keys(), key=landing_time):
        idx = assignments[p]
        new_name = build_new_filename(p, keep_idx=None, assigned_idx=idx)
        if new_name != p.name:
            dest = unique_dest(p.with_name(new_name))
            if args.dry_run:
                print(f"[DRY-RUN] add  {idx:>3} | {p.name}  ->  {dest.name}")
            else:
                p.rename(dest)
                print(f"[RENAMED] add  {idx:>3} | {p.name}  ->  {dest.name}")
            renamed_assigned += 1

    total_files = renamed_kept + renamed_assigned
    total_all = total_files

    # Final Summary
    if total_all == 0:
        print("\nNo changes needed - Everything is normalized and indexed.")
    else:
        print("\nSummary:")
        print(f"  Files renamed (kept existing index): {renamed_kept}")
        print(f"  Files renamed (newly indexed)      : {renamed_assigned}")

if __name__ == "__main__":
    main()
