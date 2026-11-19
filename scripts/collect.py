"""Copy only approved project outputs into the release."""
from pathlib import Path
import re
import shutil
import sys
import zipfile

project, source, destination = sys.argv[1:]
root = Path(source)
files = sorted(root.glob("*.zip"))
if not files or (project == "shiftly-landing" and {p.name for p in files} != {"app-dist.zip", "deploy.zip"}):
    raise SystemExit("Incomplete release outputs")
for path in files:
    if path.is_symlink() or not path.is_file() or not re.fullmatch(r"[A-Za-z0-9._-]+\.zip", path.name):
        raise SystemExit("Invalid release output")
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Invalid zip content")
    shutil.copyfile(path, Path(destination) / path.name)
