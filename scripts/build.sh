set -euo pipefail
dir="$RUNNER_TEMP/private-build"
umask 077
if [[ "$PROBE" == true ]]; then
  echo "private diagnostic probe $GITHUB_RUN_ID" > "$dir/build.log"
  exit 1
fi
# Only these two scratch directories are mounted. The guest has no GitHub credentials.
docker run --rm --init --cap-drop NET_RAW \
  -v "$dir/source:/src" -v "$dir/output:/out" -w /src \
  -e GITHUB_ACTIONS=true -e GITHUB_WORKSPACE=/src -e CI=true -e HOME=/root -e RUNNER_TEMP=/tmp \
  node:22-bookworm bash -euc '
    apt-get update -qq
    apt-get install -y -qq zip unzip jq rsync
    git config --global --add safe.directory /src
    corepack enable
    corepack prepare pnpm@10 --activate
    bash scripts/ci-build.sh /out
  ' >"$dir/build.log" 2>&1
