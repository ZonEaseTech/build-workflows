set -euo pipefail
umask 077
dir="$RUNNER_TEMP/private-build"
mkdir -p "$dir"/{source,output}
cd "$dir/source"
git init -q
git remote add origin "https://github.com/ZonEaseTech/$PROJECT.git"
auth=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)
ref=refs/heads/main
if [[ -n "${PR_NUMBER:-}" ]]; then
  [[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ && "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || exit 1
  ref="refs/pull/$PR_NUMBER/head"
fi
if ! git -c "http.extraHeader=Authorization: Basic $auth" fetch --quiet --no-tags origin "$ref" 2>/dev/null; then
  echo 'Approved source could not be read'; exit 1
fi
sha=${EXPECTED_SHA:-$(git rev-parse FETCH_HEAD)}
if [[ -n "${PR_NUMBER:-}" ]]; then
  [[ "$(git rev-parse FETCH_HEAD)" == "$sha" ]] || { echo 'Reviewed commit changed'; exit 1; }
  # Only accept a commit also present at a branch tip of this private project.
  git -c "http.extraHeader=Authorization: Basic $auth" ls-remote --heads origin 2>/dev/null |
    awk -v sha="$sha" '$1 == sha { found=1 } END { exit !found }' || { echo 'Reviewed branch changed'; exit 1; }
else
  git merge-base --is-ancestor "$sha" FETCH_HEAD 2>/dev/null || { echo 'Commit is outside main'; exit 1; }
fi
git checkout -q --detach "$sha" 2>/dev/null
git remote remove origin
printf '%s\n' "$sha" > "$dir/sha"
