set -euo pipefail
dir="$RUNNER_TEMP/private-build"
umask 077
if [[ "$PROBE" == true ]]; then
  echo "private diagnostic probe $GITHUB_RUN_ID" > "$dir/build.log"
  exit 1
fi
# Only these two scratch directories are mounted. The guest has no GitHub credentials.
image=node:22-bookworm
# Skills uses Python 3.12+ syntax and tests Chromium navigation.
if [[ "$PROJECT" == skills ]]; then image=node:22-trixie; fi
SOURCE_COMMIT=$(cat "$dir/sha")
export SOURCE_COMMIT
docker run --rm --init --cap-drop NET_RAW \
  -v "$dir/source:/src" -v "$dir/output:/out" -w "/src${SUBDIR:+/$SUBDIR}" \
  -e PROJECT -e SOURCE_COMMIT -e GITHUB_ACTIONS=true -e GITHUB_WORKSPACE=/src -e CI=true -e HOME=/root -e RUNNER_TEMP=/tmp \
  "$image" bash -euc '
    apt-get update -qq
    apt-get install -y -qq zip unzip jq rsync
    git config --global --add safe.directory /src
    corepack enable
    corepack prepare pnpm@10 --activate
    if [[ "$PROJECT" == skills ]]; then
      apt-get install -y -qq python3
      npx --yes playwright install-deps chromium
    fi
    if [[ "$PROJECT" =~ ^(outreach|zonease-account|zonease-studio|ttpos-bot)$ ]]; then apt-get install -y -qq python3; fi
    if [[ "$PROJECT" == got-that ]]; then apt-get install -y -qq curl git xz-utils python3 libglu1-mesa; fi
    # TTPOS Lite checks compile the Android shell (Gradle, JDK 17) and run Python source checks.
    if [[ "$PROJECT" == ttpos-lite ]]; then apt-get install -y -qq openjdk-17-jdk-headless python3; fi
    bash scripts/ci-build.sh /out || { rc=$?; for log in /tmp/dev.log /tmp/model.log; do if test -f "$log"; then tail -80 "$log"; fi; done; exit "$rc"; }
  ' >"$dir/build.log" 2>&1
