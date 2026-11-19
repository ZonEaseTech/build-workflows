set -euo pipefail
umask 077
dir="$RUNNER_TEMP/private-build"
sha=$(cat "$dir/sha")
repo="ZonEaseTech/$PROJECT"
tag="build-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
dest=$(mktemp -d)
cp "$dir/build.log" "$dest/build.log"
if [[ "$BUILD_STATUS" == success ]]; then
  python3 scripts/collect.py "$PROJECT" "$dir/output" "$dest"
fi
cd "$dest"
printf '%s\n' "commit=$sha" "result=$BUILD_STATUS" "run=https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" > build-info.txt
sha256sum -- * > "$dir/SHA256SUMS"
cp "$dir/SHA256SUMS" .
# Stage as a private draft. Consumers can check the result and all digests.
release=$(gh api --method POST "repos/$repo/releases" -f tag_name="$tag" -f target_commitish="$sha" \
  -f name="Build $GITHUB_RUN_ID.$GITHUB_RUN_ATTEMPT ($BUILD_STATUS)" -F draft=true \
  -f body="Commit $sha. $BUILD_STATUS. Run $GITHUB_RUN_ID, attempt $GITHUB_RUN_ATTEMPT." --jq '.id')
cleanup() { gh api -X DELETE "repos/$repo/releases/$release" >/dev/null 2>&1 || true; }
trap cleanup ERR
for file in *; do
  gh api --hostname github.com --method POST -H 'Content-Type: application/octet-stream' \
    "https://uploads.github.com/repos/$repo/releases/$release/assets?name=$file" --input "$file" --silent
done
verify=$(mktemp -d)
gh api --paginate "repos/$repo/releases/$release/assets?per_page=100" --jq '.[]|[.id,.name]|@tsv' > "$dir/assets"
while IFS=$'\t' read -r id name; do
  gh api -H 'Accept: application/octet-stream' "repos/$repo/releases/assets/$id" > "$verify/$name"
done < "$dir/assets"
cmp SHA256SUMS "$verify/SHA256SUMS"
(cd "$verify" && sha256sum --check --status SHA256SUMS)
trap - ERR
echo 'Verified delivery to the private repository.'
