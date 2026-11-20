set -euo pipefail
dir="$RUNNER_TEMP/private-build"
umask 077
if [[ "$PROBE" == true ]]; then
  echo "private diagnostic probe $GITHUB_RUN_ID" > "$dir/build.log"
  exit 1
fi
# Code signing needs the host toolchain (Xcode keychain on macOS), so this runs
# outside a container. Only reviewed main snapshots reach this step.
export SOURCE_COMMIT=$(cat "$dir/sha")
cd "$dir/source"
bash scripts/ci-app.sh "$PLATFORM" "$TARGET" "$dir/output" >"$dir/build.log" 2>&1
