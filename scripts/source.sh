set -euo pipefail
umask 077
dir="$RUNNER_TEMP/private-build"
mkdir -p "$dir"/{source,output}
cd "$dir/source"
# Export only an approved snapshot for projects whose history is restricted.
if [[ "$PROJECT" == got-that ]]; then
  repo="ZonEaseTech/$PROJECT"
  main=$(gh api "repos/$repo/commits/main" --jq .sha)
  sha=${EXPECTED_SHA:-$main}
  if [[ -n "${PR_NUMBER:-}" ]]; then
    # contents:read cannot call the pulls API; refs show the PR head and that it is still a branch tip here.
    auth=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)
    refs=$(git -c "http.extraHeader=Authorization: Basic $auth" ls-remote "https://github.com/$repo.git" "refs/pull/$PR_NUMBER/head" 'refs/heads/*' 2>/dev/null)
    awk -v sha="$sha" -v pr="refs/pull/$PR_NUMBER/head" '$1 == sha && $2 == pr { p=1 } $1 == sha && $2 ~ /^refs\/heads\// { h=1 } END { exit !(p && h) }' <<< "$refs" || { echo 'Reviewed commit changed'; exit 1; }
  else
    [[ "$sha" == "$main" ]]
  fi
  # A trusted lower bound prevents exporting an older tree, including an old PR.
  floor=$(cat "$GITHUB_WORKSPACE/scripts/got-that-minimum-sha")
  gh api "repos/$repo/compare/$floor...$sha" --jq .status | grep -Eq '^(identical|ahead)$'
  gh api "repos/$repo/tarball/$sha" | tar -xz --strip-components=1
  printf '%s\n' "$sha" > "$dir/sha"
  exit 0
fi
git init -q
git remote add origin "https://github.com/ZonEaseTech/$REPO.git"
auth=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)
ref="refs/heads/$BRANCH"
fetch_args=()
if [[ -n "${SUBDIR:-}" ]]; then
  # Large monorepo: history without file contents, then only the build directory's files.
  fetch_args=(--filter=blob:none)
  git sparse-checkout set "$SUBDIR"
fi
if [[ -n "${PR_NUMBER:-}" ]]; then
  [[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ && "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || exit 1
  ref="refs/pull/$PR_NUMBER/head"
fi
if ! git -c "http.extraHeader=Authorization: Basic $auth" fetch --quiet --no-tags "${fetch_args[@]}" origin "$ref" 2>/dev/null; then
  echo 'Approved source could not be read'; exit 1
fi
sha=${EXPECTED_SHA:-$(git rev-parse FETCH_HEAD)}
if [[ -n "${PR_NUMBER:-}" ]]; then
  [[ "$(git rev-parse FETCH_HEAD)" == "$sha" ]] || { echo 'Reviewed commit changed'; exit 1; }
  # Only accept a commit also present at a branch tip of this private project.
  git -c "http.extraHeader=Authorization: Basic $auth" ls-remote --heads origin 2>/dev/null |
    awk -v sha="$sha" '$1 == sha { found=1 } END { exit !found }' || { echo 'Reviewed branch changed'; exit 1; }
else
  git merge-base --is-ancestor "$sha" FETCH_HEAD 2>/dev/null || { echo "Commit is outside $BRANCH"; exit 1; }
fi
git -c "http.extraHeader=Authorization: Basic $auth" checkout -q --detach "$sha" 2>/dev/null
git remote remove origin
printf '%s\n' "$sha" > "$dir/sha"
