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
GOT_THAT = {"web.zip": r"(main\.dart\.js|flutter_bootstrap\.js|index\.html)",
            "android.zip": r"gotthat-[0-9.]+(-test)?\.apk|gotthat-[0-9.]+-play\.aab",
            "ios.zip": r"gotthat-[0-9.]+-[0-9]+-(test|prod)\.ipa"}
if project == "got-that" and {p.name for p in root.iterdir()} not in ({n} for n in GOT_THAT):
    raise SystemExit("Incomplete GotThat build")
if project == "ttpos-cli" and {p.name for p in root.iterdir()} != {"ttpos-cli.zip"}:
    raise SystemExit("Incomplete CLI build")
# TTPOS Lite delivers a verification receipt only; installable packages keep their signed release process.
LITE_RECEIPT = [".source-commit", "checks.txt", "version.json"]
if project == "ttpos-lite" and {p.name for p in root.iterdir()} != {"ttpos-lite-checks.zip"}:
    raise SystemExit("Incomplete TTPOS Lite checks")
CLI_PLATFORMS = ("linux-x64", "linux-arm64", "darwin-x64", "darwin-arm64")
CLI_REQUIRED = [".source-commit", "VERSION", "npm/cli/package.json", "bundle/README.md", "bundle/install.sh", "bundle/CHANGELOG.md"]
CLI_REQUIRED += [f"npm/cli-{p}/{f}" for p in CLI_PLATFORMS for f in ("package.json", "bin/ttpos")]
for path in files:
    if path.is_symlink() or not path.is_file() or not re.fullmatch(r"[A-Za-z0-9._-]+\.zip", path.name):
        raise SystemExit("Invalid release output")
    with zipfile.ZipFile(path) as archive:
        if project == "got-that":
            names = archive.namelist()
            wanted = [n for n in names if re.fullmatch(GOT_THAT[path.name], n)]
            if not archive.getinfo(".source-commit").file_size or not wanted or any(not archive.getinfo(n).file_size for n in wanted):
                raise SystemExit("Incomplete GotThat archive")
            if path.name == "web.zip" and len(wanted) != 3:
                raise SystemExit("Incomplete web archive")
            if path.name != "web.zip" and (len(wanted) != 1 or set(names) - set(wanted) - {".source-commit", ".testflight-build"}):
                raise SystemExit("Unexpected app archive entry")
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
        if project == "ttpos-lite":
            names = archive.namelist()
            if sorted(names) != LITE_RECEIPT or any(not archive.getinfo(n).file_size for n in names):
                raise SystemExit("Unexpected TTPOS Lite checks archive")
        if archive.testzip() is not None:
            raise SystemExit("Invalid zip content")
    shutil.copyfile(path, Path(destination) / path.name)
