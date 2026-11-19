set -euo pipefail
umask 077
dir="$RUNNER_TEMP/private-build"
sha=$(cat "$dir/sha")
repo="ZonEaseTech/$PROJECT"
tag="build-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
label="Build $GITHUB_RUN_ID.$GITHUB_RUN_ATTEMPT"
if [[ -n "${PR_NUMBER:-}" ]]; then
  tag="pr-check-$PR_NUMBER-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
  label="PR $PR_NUMBER check $GITHUB_RUN_ID.$GITHUB_RUN_ATTEMPT"
fi
dest=$(mktemp -d)
cp "$dir/build.log" "$dest/build.log"
if [[ "$BUILD_STATUS" == success ]]; then
  collect_dest="$dest"
  if [[ -n "${PR_NUMBER:-}" ]]; then collect_dest=$(mktemp -d); fi
  if ! python3 scripts/collect.py "$PROJECT" "$dir/output" "$collect_dest" >>"$dest/build.log" 2>&1; then
    if [[ -z "${PR_NUMBER:-}" ]]; then exit 1; fi
    BUILD_STATUS=failure
  fi
fi
cd "$dest"
printf '%s\n' "commit=$sha" "result=$BUILD_STATUS" "run=https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" > build-info.txt
if [[ -n "${PR_NUMBER:-}" ]]; then printf 'pr=%s\n' "$PR_NUMBER" >> build-info.txt; fi
sha256sum -- * > "$dir/SHA256SUMS"
cp "$dir/SHA256SUMS" .
# Stage as a private draft. Consumers can check the result and all digests.
release=$(gh api --method POST "repos/$repo/releases" -f tag_name="$tag" -f target_commitish="$sha" \
  -f name="Transferring build $GITHUB_RUN_ID.$GITHUB_RUN_ATTEMPT" -F draft=true \
  -f body="Commit $sha. $BUILD_STATUS. Run $GITHUB_RUN_ID, attempt $GITHUB_RUN_ATTEMPT." --jq '.id')
cleanup() { gh api -X DELETE "repos/$repo/releases/$release" >/dev/null 2>&1 || true; }
trap cleanup ERR
upload() {
  local file=$1
  gh api --hostname github.com --method POST -H 'Content-Type: application/octet-stream' \
    "https://uploads.github.com/repos/$repo/releases/$release/assets?name=$file" --input "$file" --silent
}
for file in *; do
  if [[ "$file" != build-info.txt ]]; then upload "$file"; fi
done
upload build-info.txt
verify=$(mktemp -d)
gh api --paginate "repos/$repo/releases/$release/assets?per_page=100" --jq '.[]|[.id,.name]|@tsv' > "$dir/assets"
while IFS=$'\t' read -r id name; do
  curl --fail --silent --show-error --location --retry 3 \
    -H "Authorization: Bearer $GH_TOKEN" -H 'Accept: application/octet-stream' \
    "https://api.github.com/repos/$repo/releases/assets/$id" -o "$verify/$name"
done < "$dir/assets"
cmp SHA256SUMS "$verify/SHA256SUMS"
(cd "$verify" && sha256sum --check --status SHA256SUMS)
gh api -X PATCH "repos/$repo/releases/$release" -f tag_name="$tag" -f target_commitish="$sha" -F draft=true -f name="$label ($BUILD_STATUS)" --silent
gh api "repos/$repo/releases/$release" | jq -e --arg tag "$tag" --arg sha "$sha" '(.draft == true) and (.tag_name == $tag) and (.target_commitish == $sha)' >/dev/null
trap - ERR
echo 'Verified delivery to the private repository.'

[[ -z "${PR_NUMBER:-}" || "$BUILD_STATUS" == success ]]
