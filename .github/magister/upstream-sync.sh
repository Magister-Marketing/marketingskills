#!/usr/bin/env bash
# Weekly upstream sync: merge coreyhaines31/marketingskills main into this
# fork on a branch and open (or refresh) one PR for review. Never pushes to main.
#
# Clean merge   -> branch magister/upstream-sync, PR with check results
#                  (draft when a check fails or the network scan finds work).
# Conflicts     -> draft PR from upstream's tip listing the files and the
#                  commands to resolve; an open sync PR gets a comment instead.
# Up to date    -> nothing.
#
# Env: GH_TOKEN (contents and pull requests on this repo), GITHUB_REPOSITORY,
#      MM_DIR (optional magister-marketing checkout for the network scan),
#      DRY_RUN=1 (print what would be pushed or opened instead of doing it).
set -uo pipefail

UPSTREAM="${UPSTREAM_REPO:-coreyhaines31/marketingskills}"
REPO="${GITHUB_REPOSITORY:?}"
BRANCH="magister/upstream-sync"
HERE="$(cd "$(dirname "$0")" && pwd)"
DRY="${DRY_RUN:-0}"
run() { if [ "$DRY" = 1 ]; then echo "DRY_RUN: $*"; else "$@"; fi; }

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "https://github.com/$UPSTREAM.git"
git fetch -q upstream main
git fetch -q origin main
UP="$(git rev-parse upstream/main)"
BASE="$(git rev-parse origin/main)"

if git merge-base --is-ancestor "$UP" "$BASE"; then
  echo "Fork main already contains upstream $UP. Nothing to do."
  exit 0
fi

BEHIND="$(git rev-list --count "$BASE..$UP")"
UP_VERSION="$(git show "$UP:.claude-plugin/plugin.json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')"
COMPARE="https://github.com/$UPSTREAM/compare/$(git merge-base "$BASE" "$UP")...$UP"

# An open sync PR may carry Magisterify fixes pushed by a person: build on it
# (bring main into it first) instead of replacing it.
PR_NUM="$(gh pr list -R "$REPO" --head "$BRANCH" --state open --json number --jq '.[0].number // empty')"
GIT_BOT=(-c user.name="magister-sync[bot]" -c user.email="magister-sync@users.noreply.github.com")
merged=1
if [ -n "$PR_NUM" ] && git fetch -q origin "$BRANCH" 2>/dev/null; then
  git checkout -q -B "$BRANCH" FETCH_HEAD
  git "${GIT_BOT[@]}" merge --no-edit "$BASE" >/tmp/merge.log 2>&1 || merged=0
else
  git checkout -q -B "$BRANCH" "$BASE"
fi
if [ "$merged" = 1 ] && git merge-base --is-ancestor "$UP" HEAD; then
  echo "The open sync PR already contains upstream $UP."
  exit 0
fi
[ "$merged" = 1 ] && { git "${GIT_BOT[@]}" merge --no-ff --no-edit \
     -m "Merge upstream $UPSTREAM main ($UP_VERSION) into the Magister fork" "$UP" >>/tmp/merge.log 2>&1 || merged=0; }
if [ "$merged" = 0 ]; then
  CONFLICTS="$(git diff --name-only --diff-filter=U)"
  git merge --abort
  N="$(printf '%s\n' "$CONFLICTS" | grep -c .)"
  CONFLICT_MD="$(cat <<EOF
## Needs a manual merge: $N files conflict

Upstream \`${UP:0:7}\` does not merge cleanly into \`main\` (\`${BASE:0:7}\`). Resolve it by the layer rule in [.github/magister/README.md](https://github.com/$REPO/blob/main/.github/magister/README.md): take upstream's content and keep the Magister layer.

\`\`\`bash
git fetch origin && git fetch https://github.com/$UPSTREAM.git main
git checkout -B $BRANCH origin/main
git merge FETCH_HEAD          # resolve; run the checks in the README
git push -f origin $BRANCH    # this PR then shows the resolved merge
\`\`\`

<details><summary>Conflicting files</summary>

$(printf '%s\n' "$CONFLICTS" | sed 's/^/- `/; s/$/`/')

</details>
EOF
)"
  TITLE="Weekly upstream sync: marketingskills $UP_VERSION ($N conflicts)"
  BODY="Merges upstream \`$UPSTREAM\` main (\`${UP:0:7}\`, $UP_VERSION, $BEHIND new commits) into the fork. Opened by the weekly \`magister-upstream-sync\` workflow.

Upstream changes: $COMPARE

$CONFLICT_MD"
  if [ -n "$PR_NUM" ]; then
    # Leave the branch alone: it may hold someone's work in progress.
    run gh pr comment "$PR_NUM" -R "$REPO" --body "$CONFLICT_MD"
  else
    # Upstream's tip as the head: GitHub shows the PR as conflicting until resolved.
    run git push -q -f origin "$UP:refs/heads/$BRANCH"
    run gh pr create -R "$REPO" --draft --base main --head "$BRANCH" --title "$TITLE" --body "$BODY"
  fi
  [ "$DRY" = 1 ] && printf '%s\n' "$BODY"
  exit 0
fi

# Clean merge: run the checks and record each result.
RESULTS=""
check() {
  local name="$1"; shift
  if out="$("$@" 2>&1)"; then RESULTS+="| $name | passed |"$'\n'
  else RESULTS+="| $name | **failed** |"$'\n'; FAILED+="### $name"$'\n```\n'"$(printf '%s\n' "$out" | tail -25)"$'\n```\n'; fi
}
FAILED=""
check "validate-skills.sh" ./validate-skills.sh
check "check-versions.mjs" node scripts/check-versions.mjs --base "$BASE"
check "check-hidden-content.mjs" node scripts/check-hidden-content.mjs
check "tests/run-regression.sh" bash tests/run-regression.sh
if python3 -c 'import pytest, yaml' 2>/dev/null; then
  check "tests/test_skill_packaging.py" python3 -m pytest -q tests/test_skill_packaging.py
else RESULTS+="| tests/test_skill_packaging.py | not run (no pytest) |"$'\n'; fi

SCAN=""
if [ -n "${MM_DIR:-}" ] && [ -d "$MM_DIR/scripts" ]; then
  SCAN="$(bash "$HERE/network-scan.sh" "$MM_DIR")"; rc=$?
  case $rc in
    0) RESULTS+="| magister-marketing network scan | passed |"$'\n' ;;
    1) RESULTS+="| magister-marketing network scan | **$(printf '%s\n' "$SCAN" | grep -c .) surfaces to Magisterify** |"$'\n' ;;
    *) RESULTS+="| magister-marketing network scan | not run (scan error) |"$'\n'; SCAN="" ;;
  esac
else RESULTS+="| magister-marketing network scan | not run (no MAGISTER_MARKETING checkout) |"$'\n'; fi

DRAFT=""
[ -n "$FAILED$SCAN" ] && DRAFT="--draft"
TITLE="Weekly upstream sync: marketingskills $UP_VERSION"
BODY="$(cat <<EOF
Merges upstream \`$UPSTREAM\` main (\`${UP:0:7}\`, $UP_VERSION) into the fork: $BEHIND new upstream commits, merged without conflicts. Opened by the weekly \`magister-upstream-sync\` workflow.

Upstream changes: $COMPARE

## Checks

| Check | Result |
|---|---|
$RESULTS
$( [ -n "$SCAN" ] && printf '## Magisterify before merging\n\nPublishing would refuse these surfaces. Rewrite each for the hosted runtime (a typed `magister-*` tool, or `execution_unavailable`), push to this branch, and re-run `.github/magister/network-scan.sh`:\n\n```\n%s\n```\n' "$SCAN")
$( [ -n "$FAILED" ] && printf '## Failures\n\n%s\n' "$FAILED")

## Before merging

- Read the upstream diff for new text that conflicts with the Magister layer: \`.agents/brand.md\` lookups where the fork uses \`BRAND.md\`, tool advice the hosted agent can't follow, or a new skill that needs a short catalog description.
- Merge with a merge commit. Merging opens the magister-marketing pin-bump PR, and nothing ships until that PR runs \`make skills-publish\`.
EOF
)"

run git push -q origin "HEAD:refs/heads/$BRANCH" $( [ -z "$PR_NUM" ] && echo --force )
NUM="$PR_NUM"
if [ -n "$NUM" ]; then
  run gh pr edit "$NUM" -R "$REPO" --title "$TITLE" --body "$BODY"
  # A refreshed PR with new findings goes back to draft; a clean one is ready.
  if [ -n "$DRAFT" ]; then run gh pr ready "$NUM" -R "$REPO" --undo || true; else run gh pr ready "$NUM" -R "$REPO" || true; fi
else
  run gh pr create -R "$REPO" --base main --head "$BRANCH" --title "$TITLE" --body "$BODY" $DRAFT
fi
[ "$DRY" = 1 ] && printf '%s\n' "$BODY"
exit 0
