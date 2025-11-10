# Utility Scripts Folder
This folder contains scripts  that aim to assist me in the data management of the thesis folder. 
# ShapeShifter.py
This Python script reads the `~/Documents/Git/thesis/papers` folder. It collects the names of all papers stored in there, and it normalizes the names of each item in the folder, to follow a terminal and typing friendly naming convention. For example:

```
'Paper about subject'.pdf -> 1_Paper_about_subject.pdf
```

It assigns an index number according to the date each item landed in the folder (this will help with the references later on), and strips names of dash variants and white spaces. 
## Usage:
- `python3 ShapeShifter.py --dry-run`: previews a list of changes, without actually implementing anything. 
- `python3 ShapeShifter.py`: runs the renaming convention on the `papers/` folder.
- `python3 ShapeShifter.py --recursive`: runs the renaming convention on the `papers/` folder, as well as any subfolders inside this directory.
# Chronicle.sh
This is a custom and safe data backup bash script. It connects to the Alexandria samba share, and backups all files that pass the `.sambaignore` filter. Its implementation is crudely copied from `git` version controlling system.
## Usage
```
bash Chronicle.sh [-s SRC] [-d DEST] [-x EXCLUDE_FILE] [-l LOGFILE] [-n] [-h]
```

Here:
- `-s SRC` is the source directory to backup (default: `~/Documents/Git/thesis/`).
- `-d DEST` is the destination base directory (default: anenin's samba share under the `thesis/` folder.
- `-x FILE` the pattern to exclude from the backup operation.
- `-l FILE` path to the logfile.
- `-n` dry-run implementation (no changes or actual backup).
- `-h` shows the help message.
