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
if project == "got-that" and {p.name for p in root.iterdir()} != {"web.zip"}:
    raise SystemExit("Incomplete web build")
if project == "ttpos-cli" and {p.name for p in root.iterdir()} != {"ttpos-cli.zip"}:
    raise SystemExit("Incomplete CLI build")
CLI_PLATFORMS = ("linux-x64", "linux-arm64", "darwin-x64", "darwin-arm64")
CLI_REQUIRED = [".source-commit", "VERSION", "npm/cli/package.json", "bundle/README.md", "bundle/install.sh", "bundle/CHANGELOG.md"]
CLI_REQUIRED += [f"npm/cli-{p}/{f}" for p in CLI_PLATFORMS for f in ("package.json", "bin/ttpos")]
for path in files:
    if path.is_symlink() or not path.is_file() or not re.fullmatch(r"[A-Za-z0-9._-]+\.zip", path.name):
        raise SystemExit("Invalid release output")
    with zipfile.ZipFile(path) as archive:
        if project == "got-that":
            for name in ("main.dart.js", "flutter_bootstrap.js", "index.html", ".source-commit"):
                if not archive.getinfo(name).file_size:
                    raise SystemExit("Incomplete web archive")
        if project == "ttpos-cli":
            names = archive.namelist()
            for name in CLI_REQUIRED:
                if not archive.getinfo(name).file_size:
                    raise SystemExit("Incomplete CLI archive")
            # Only compiled packages and public documents; never source code.
            for name in names:
                if name.startswith("/") or ".." in name.split("/") or not (
                    name in (".source-commit", "VERSION") or name.startswith(("npm/", "bundle/"))):
                    raise SystemExit("Unexpected CLI archive entry")
                if name.endswith(".go") or name.endswith((".env", ".pem", ".key")):
                    raise SystemExit("Unexpected CLI archive entry")
        if archive.testzip() is not None:
            raise SystemExit("Invalid zip content")
    shutil.copyfile(path, Path(destination) / path.name)
