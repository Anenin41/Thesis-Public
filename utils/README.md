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
**Dependency:** `Librarian.sh` 
This is a custom and safe data backup bash script. It connects to the a private samba share drive, and backups all files that pass the `.sambaignore` filter. Its implementation is crudely copied from `git` version controlling system.

## Usage
```
bash Chronicle.sh [-s SRC] [-d DEST] [-x EXCLUDE_FILE] [-l LOGFILE] [-n] [-h]
```

Here:
- `-s SRC` is the source directory to backup (default: Private Thesis Repository).
- `-d DEST` is the destination base directory (default: Private Samba Share Drive).
- `-x FILE` the pattern to exclude from the backup operation.
- `-l FILE` path to the logfile.
- `-n` dry-run implementation (no changes or actual backup).
- `-h` shows the help message.

# CopyCat.sh
This custom bash script copies files from a private repository into a public one. It avoids anything that contains personal information (names, emails, my student number, etc...) but copies everything else. The only reason for its implementation is to provide progress updates in a transparent way, because papers, code and everything relevant to the thesis are stored privately.

## Usage
```
bash CopyCat.sh [--dry-run | --apply] [-m "commit message"] [-v] [-h]
```

Here: 
- `-n`, `--dry-run` dry run implementation (no changes or actual copying).
- `-a`, `--apply` actual copy and commit + push operation.
- `-m "commit message"` the message to parse the `git commit -m <msg>` command with.
- `-v` verbose overview of the copying operation.
- `-h` shows the help message.

# Librarian.sh
This bash script automatically mounts or dismounts a private[^1] samba share drive. It also checks if the drive is mounted (or not mounted) before performing each operation, and returns back an appropriate message. This script is destined to be used **globally**.

## Usage
```bash
mv Librarian.sh librarian
chmod 755 librarian
sudo cp librarian /usr/local/bin/
```

[^1]: The samba share is only accessible by a private VPN network. This message SHOULD NEVER see the light of day, and it is only for my own eyes.