set -euo pipefail
umask 077
dir="$RUNNER_TEMP/private-build"
mkdir -p "$dir"/{source,output}
cd "$dir/source"
git init -q
git remote add origin "https://github.com/ZonEaseTech/$PROJECT.git"
auth=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)
if ! git -c "http.extraHeader=Authorization: Basic $auth" fetch --quiet --no-tags origin refs/heads/main 2>/dev/null; then
  echo 'Approved source could not be read'; exit 1
fi
sha=${EXPECTED_SHA:-$(git rev-parse FETCH_HEAD)}
git merge-base --is-ancestor "$sha" FETCH_HEAD 2>/dev/null || { echo 'Commit is outside main'; exit 1; }
git checkout -q --detach "$sha" 2>/dev/null
git remote remove origin
printf '%s\n' "$sha" > "$dir/sha"
