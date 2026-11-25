#!/usr/bin/env bash
# Weekly upstream sync: merge coreyhaines31/marketingskills main into the
# branch magister/upstream-sync and open (or refresh) one PR. Never pushes main.
#
# Clean merge -> the branch holds the merge. The PR body has magister-marketing's
#                network-surface scan and opens as a draft unless the scan
#                passed. The fork's own checks run as the PR's workflows.
# Conflicts   -> a draft PR whose head is upstream's tip, listing the files and
#                the commands to resolve. When a sync PR with someone's work on
#                it is open, it gets one comment per new upstream/main pair instead.
# Up to date  -> nothing.
#
# This script runs no code from upstream: it merges, reads files and calls the
# monorepo's scanner, so it may hold the token.
#
# Env: GH_TOKEN (contents, workflows and pull requests on this repo),
#      GITHUB_REPOSITORY, MM_DIR (magister-marketing checkout for the scan),
#      DRY_RUN=1 (print pushes and gh writes instead of doing them).
set -euo pipefail

UPSTREAM="${UPSTREAM_REPO:-coreyhaines31/marketingskills}"
REPO="${GITHUB_REPOSITORY:?}"
BRANCH="magister/upstream-sync"
HERE="$(cd "$(dirname "$0")" && pwd)"
DRY="${DRY_RUN:-0}"
LOG="$(mktemp)"
# Run the scan from main's copy: a checkout of the PR branch below replaces
# the work tree, and nothing from that branch may run next to the token.
SCAN_SH="$(mktemp)"
cp "$HERE/network-scan.sh" "$SCAN_SH"
# Snapshot the monorepo's scanner too, before any merge or checkout can write
# into a checkout that sits inside this work tree.
if [ -n "${MM_DIR:-}" ] && [ -d "$MM_DIR/scripts" ]; then
  MM_SNAP="$(mktemp -d)"
  mkdir -p "$MM_SNAP/gateway"
  cp -R "$MM_DIR/scripts" "$MM_SNAP/"
  cp -R "$MM_DIR/gateway/app" "$MM_SNAP/gateway/"
  MM_DIR="$MM_SNAP"
fi
run() { if [ "$DRY" = 1 ]; then echo "DRY_RUN: $*"; else "$@"; fi; }
bot() { git -c user.name="magister-sync[bot]" -c user.email="magister-sync@users.noreply.github.com" "$@"; }

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "https://github.com/$UPSTREAM.git"
git fetch -q upstream main
git fetch -q origin main
UP="$(git rev-parse upstream/main)"
BASE="$(git rev-parse origin/main)"
if git merge-base --is-ancestor "$UP" "$BASE"; then
  echo "Fork main already contains upstream ${UP:0:7}. Nothing to do."
  exit 0
fi

BEHIND="$(git rev-list --count "$BASE..$UP")"
UP_VERSION="$(git show "$UP:.claude-plugin/plugin.json" | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["version"])')"
COMPARE="https://github.com/$UPSTREAM/compare/$(git merge-base "$BASE" "$UP")...$UP"

# --head matches any fork's branch of that name; only this repo's branch counts.
PR_NUM="$(gh pr list -R "$REPO" --head "$BRANCH" --state open --json number,isCrossRepository \
  --jq '[.[] | select(.isCrossRepository | not)][0].number // empty')"
REMOTE="$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)"
[ -n "$REMOTE" ] && git fetch -q origin "$BRANCH"

# Build on an open sync PR's branch so fixes pushed to it are kept, unless its
# head is only an upstream commit (the placeholder of a conflict PR).
ON_PR=0
if [ -n "$PR_NUM" ] && [ -n "$REMOTE" ] && ! git merge-base --is-ancestor "$REMOTE" "$UP"; then
  ON_PR=1
fi
# A leftover branch with its own commits and no open PR may be someone's work.
# Commits only this bot made (say, a run whose PR create failed) may be replaced.
# (Read the authors first: a failed git log must stop the run, not count as "bot only".)
if [ -z "$PR_NUM" ] && [ -n "$REMOTE" ]; then
  AUTHORS="$(git log --format=%ae "$REMOTE" --not "$BASE" "$UP")"
else
  AUTHORS=""
fi
if [ -n "$AUTHORS" ] && grep -qvx "magister-sync@users.noreply.github.com" <<<"$AUTHORS"; then
  echo "origin/$BRANCH (${REMOTE:0:7}) has commits that are not on main or upstream, and no open PR." >&2
  echo "Open a PR from it or delete it, then re-run." >&2
  exit 1
fi
# Every replacing push expects the branch exactly as read above (absent if empty).
LEASE="--force-with-lease=refs/heads/$BRANCH:$REMOTE"

merge_ok=1
STAGE=upstream
if [ "$ON_PR" = 1 ]; then
  git checkout -q -B "$BRANCH" "$REMOTE"
  STAGE=main
  bot merge --no-edit "$BASE" >"$LOG" 2>&1 || merge_ok=0
else
  git checkout -q -B "$BRANCH" "$BASE"
fi
if [ "$merge_ok" = 1 ] && ! git merge-base --is-ancestor "$UP" HEAD; then
  STAGE=upstream
  bot merge --no-ff --no-edit -m "Merge upstream $UPSTREAM main ($UP_VERSION) into the Magister fork" "$UP" >>"$LOG" 2>&1 || merge_ok=0
fi
# The open PR already holds this merge (say, a person pushed the resolution):
# scan it and refresh the PR, but push nothing.
PUSH=1
if [ "$merge_ok" = 1 ] && [ "$(git rev-parse HEAD)" = "$REMOTE" ]; then
  echo "The open sync PR already contains upstream ${UP:0:7} and main ${BASE:0:7}; rescanning it."
  PUSH=0
fi

if [ "$merge_ok" = 0 ]; then
  CONFLICTS="$(git diff --name-only --diff-filter=U)"
  git merge --abort 2>/dev/null || true
  if [ -z "$CONFLICTS" ]; then
    echo "The merge failed without conflicts:" >&2; cat "$LOG" >&2; exit 1
  fi
  N="$(printf '%s\n' "$CONFLICTS" | grep -c .)"
  if [ "$STAGE" = main ]; then
    HEADING="Bringing main (\`${BASE:0:7}\`) into this PR conflicts in $N files"
    CMDS="git fetch origin
git checkout -B $BRANCH origin/$BRANCH
git merge origin/main         # resolve, then run the checks in the README
git push origin $BRANCH       # no -f: the next run then merges upstream"
  elif [ "$ON_PR" = 1 ]; then
    HEADING="Upstream \`${UP:0:7}\` ($UP_VERSION) conflicts with this PR in $N files"
    CMDS="git fetch origin && git fetch https://github.com/$UPSTREAM.git main
git checkout -B $BRANCH origin/$BRANCH
git merge FETCH_HEAD          # resolve, then run the checks in the README
git push origin $BRANCH       # no -f: keeps the fixes already on this branch"
  else
    HEADING="Upstream \`${UP:0:7}\` ($UP_VERSION) conflicts with main (\`${BASE:0:7}\`) in $N files"
    CMDS="git fetch origin && git fetch https://github.com/$UPSTREAM.git main
git checkout -B $BRANCH origin/main
git merge FETCH_HEAD          # resolve, then run the checks in the README
git push --force-with-lease origin $BRANCH   # replaces this PR's placeholder head"
  fi
  MARKER="<!-- magister-upstream-sync up=$UP main=$BASE -->"
  CONFLICT_MD="$MARKER
## $HEADING

Resolve it by the layer rule in [.github/magister/README.md](https://github.com/$REPO/blob/main/.github/magister/README.md): take upstream's content and keep the Magister layer.

\`\`\`bash
$CMDS
\`\`\`

<details><summary>Conflicting files</summary>

$(printf '%s\n' "$CONFLICTS" | sed 's/^/- `/; s/$/`/')

</details>"
  if [ "$ON_PR" = 1 ]; then
    # Leave the branch alone and say so once per upstream/main pair.
    BODIES="$(gh pr view "$PR_NUM" -R "$REPO" --json comments --jq '.comments[].body')"
    if grep -qF "$MARKER" <<<"$BODIES"; then
      echo "PR #$PR_NUM already has this conflict report."
    else
      run gh pr comment "$PR_NUM" -R "$REPO" --body "$CONFLICT_MD"
    fi
    exit 0
  fi
  TITLE="Weekly upstream sync: marketingskills $UP_VERSION ($N conflicts)"
  BODY="Merges upstream \`$UPSTREAM\` main (\`${UP:0:7}\`, $UP_VERSION, $BEHIND new commits) into the fork. Opened by the weekly \`magister-upstream-sync\` workflow.

Upstream changes: $COMPARE

$CONFLICT_MD"
  # Upstream's tip as the head: GitHub shows the PR as conflicting until resolved.
  [ "$UP" = "$REMOTE" ] || run git push -q "$LEASE" origin "$UP:refs/heads/$BRANCH"
  if [ -n "$PR_NUM" ]; then run gh pr edit "$PR_NUM" -R "$REPO" --title "$TITLE" --body "$BODY"
  else run gh pr create -R "$REPO" --draft --base main --head "$BRANCH" --title "$TITLE" --body "$BODY"; fi
  [ "$DRY" = 1 ] && printf '%s\n' "$BODY"
  exit 0
fi

# Clean merge: the network scan decides whether the PR may leave draft.
SCAN="" ; SCAN_ROW=""
if [ -n "${MM_DIR:-}" ] && [ -d "$MM_DIR/scripts" ]; then
  rc=0; SCAN="$(bash "$SCAN_SH" "$MM_DIR")" || rc=$?
  case $rc in
    0) SCAN_ROW="passed" ;;
    1) SCAN_ROW="**$(printf '%s\n' "$SCAN" | grep -c . || true) surfaces to Magisterify** (below)" ;;
    *) SCAN_ROW="**not run** (the scan failed; see the workflow log)"; SCAN="" ;;
  esac
else
  rc=2; SCAN_ROW="**not run** (no magister-marketing checkout)"
fi
DRAFT=""
[ "$rc" = 0 ] || DRAFT=1
# Upstream workflow changes are how upstream code could reach the token once
# they are on main: a person reads each one before the PR leaves draft.
WORKFLOWS="$(git diff --name-only "$BASE" HEAD -- .github | grep -v '^\.github/magister/' || true)"
[ -z "$WORKFLOWS" ] || DRAFT=1

TITLE="Weekly upstream sync: marketingskills $UP_VERSION"
BODY="Merges upstream \`$UPSTREAM\` main (\`${UP:0:7}\`, $UP_VERSION) into the fork: $BEHIND new upstream commits, merged without conflicts. Opened by the weekly \`magister-upstream-sync\` workflow.

Upstream changes: $COMPARE

## Checks

- magister-marketing network-surface scan (the \`make skills-publish\` gate): $SCAN_ROW
- The fork's validators and tests run as this PR's checks once it is out of draft (some skip drafts).
$( [ -n "$WORKFLOWS" ] && printf '\n## Changed under .github (read each before merging)\n\nKeep this PR a draft until each file is checked: a workflow that runs on the fork must not use `environment:`, `secrets.` or write `permissions:`, and anything that publishes or writes `main` gets the upstream-only guard (README rule 5).\n\n```\n%s\n```\n' "$WORKFLOWS" || true)
$( [ -n "$SCAN" ] && printf '\n## Magisterify before merging\n\nPublishing would refuse these surfaces. Rewrite each one for the hosted runtime (a typed `magister-*` tool, or `execution_unavailable`), push to this branch, and re-run `.github/magister/network-scan.sh`:\n\n```\n%s\n```\n' "$SCAN" || true)

## Before merging

- Read the upstream diff for text that conflicts with the Magister layer: \`.agents/brand.md\` lookups where the fork uses \`BRAND.md\`, tool advice the hosted agent can't follow, a new skill without a short catalog description, or a new upstream workflow that should only run upstream.
- Merge with a merge commit. Merging opens the magister-marketing pin-bump PR, and nothing ships until that PR runs \`make skills-publish\`."

# Put an open PR back in draft before its branch changes, if it must be one.
IS_DRAFT=""
[ -n "$PR_NUM" ] && IS_DRAFT="$(gh pr view "$PR_NUM" -R "$REPO" --json isDraft --jq .isDraft)"
if [ -n "$DRAFT" ] && [ "$IS_DRAFT" = false ]; then
  run gh pr ready "$PR_NUM" -R "$REPO" --undo
fi
if [ "$PUSH" = 0 ]; then
  :
elif [ "$ON_PR" = 1 ]; then
  run git push -q origin "HEAD:refs/heads/$BRANCH"   # fast-forward only
else
  run git push -q "$LEASE" origin "HEAD:refs/heads/$BRANCH"
fi
if [ -n "$PR_NUM" ]; then
  run gh pr edit "$PR_NUM" -R "$REPO" --title "$TITLE" --body "$BODY"
  if [ -z "$DRAFT" ] && [ "$IS_DRAFT" = true ]; then
    run gh pr ready "$PR_NUM" -R "$REPO"
  fi
else
  run gh pr create -R "$REPO" --base main --head "$BRANCH" --title "$TITLE" --body "$BODY" ${DRAFT:+--draft}
fi
[ "$DRY" = 1 ] && printf '%s\n' "$BODY"
exit 0
