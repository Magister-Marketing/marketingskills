#!/usr/bin/env bash
# Weekly upstream sync: merge coreyhaines31/marketingskills main into the
# branch magister/upstream-sync and open (or refresh) one PR. Never pushes main.
#
# Clean merge -> the branch holds the merge, with the fork's own workflows
#                (upstream's are held back). The PR body has magister-marketing's
#                network-surface scan. If the scan passed and nothing under
#                .github changed, it merges itself once its checks pass;
#                otherwise it is a draft for a person.
# Conflicts   -> a draft PR whose head is upstream's tip (with the fork's
#                workflows), listing the files and
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
BOT_EMAIL="magister-sync@users.noreply.github.com"
bot() { git -c user.name="magister-sync[bot]" -c user.email="$BOT_EMAIL" "$@"; }
# Upstream's workflow files never come into the fork: they would run on the
# sync branch as soon as it is pushed. Make .github/workflows match $1's.
hold_back_workflows() {
  git rm -rq --cached --ignore-unmatch .github/workflows
  rm -rf .github/workflows
  if git cat-file -e "$1:.github/workflows" 2>/dev/null; then git checkout "$1" -- .github/workflows; fi
}

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

# Who worked on the branch beyond main and upstream? (A failed git log stops the run.)
AUTHORS=""
if [ -n "$REMOTE" ]; then AUTHORS="$(git log --format=%ae "$REMOTE" --not "$BASE" "$UP")"; fi
HUMAN=0
if [ -n "$AUTHORS" ] && grep -qvx "$BOT_EMAIL" <<<"$AUTHORS"; then HUMAN=1; fi
# Build on the branch only when a person pushed to it and its PR is open, so
# their work is kept. A bot-only branch (an earlier run's merge or conflict
# placeholder) is rebuilt from main. A person's branch with no open PR stops the run.
ON_PR=0
if [ "$HUMAN" = 1 ]; then
  if [ -z "$PR_NUM" ]; then
    echo "origin/$BRANCH (${REMOTE:0:7}) has a person's commits that are not on main or upstream, and no open PR." >&2
    echo "Open a PR from it or delete it, then re-run." >&2
    exit 1
  fi
  ON_PR=1
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
  MSG="Merge upstream $UPSTREAM main ($UP_VERSION) into the Magister fork"
  if ! bot merge --no-ff --no-edit -m "$MSG" "$UP" >>"$LOG" 2>&1; then
    # Held-back workflows conflict every time upstream edits them again. When
    # only .github/workflows conflicts, keep the fork's and finish the merge.
    U="$(git diff --name-only --diff-filter=U)"
    if [ -n "$U" ] && ! grep -qv '^\.github/workflows/' <<<"$U"; then
      hold_back_workflows HEAD
      bot commit -q --no-edit -m "$MSG"
    else
      merge_ok=0
    fi
  fi
  if [ "$merge_ok" = 1 ] && ! git diff --quiet HEAD^1 HEAD -- .github/workflows; then
    hold_back_workflows HEAD^1
    bot commit -q --amend --no-edit
  fi
fi
# Upstream's workflow changes since the last sync, held back (named in the PR only).
HELD="$(git diff --name-only "$(git merge-base "$BASE" "$UP")" "$UP" -- .github/workflows)"
# The open PR already holds this merge (say, a person pushed the resolution):
# scan it and refresh the PR, but push nothing.
PUSH=1
if [ "$merge_ok" = 1 ] && [ "$(git rev-parse HEAD)" = "$REMOTE" ]; then
  echo "The open sync PR already contains upstream ${UP:0:7} and main ${BASE:0:7}; rescanning it."
  PUSH=0
elif [ "$merge_ok" = 1 ] && [ "$ON_PR" = 0 ] && [ -n "$REMOTE" ] \
     && git merge-base --is-ancestor "$BASE" "$REMOTE" && git merge-base --is-ancestor "$UP" "$REMOTE" \
     && git diff --quiet "$REMOTE" HEAD; then
  # The bot's earlier merge of the same main and upstream: keep it, push nothing.
  git checkout -q -B "$BRANCH" "$REMOTE"
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
git rm -rq --cached .github/workflows && rm -rf .github/workflows \\
  && git checkout HEAD -- .github/workflows   # keep this branch's workflows, not upstream's
git commit                    # finish the merge
git push origin $BRANCH       # no -f: keeps the fixes already on this branch"
  else
    HEADING="Upstream \`${UP:0:7}\` ($UP_VERSION) conflicts with main (\`${BASE:0:7}\`) in $N files"
    CMDS="git fetch origin && git fetch https://github.com/$UPSTREAM.git main
git checkout -B $BRANCH origin/main
git merge FETCH_HEAD          # resolve, then run the checks in the README
git rm -rq --cached .github/workflows && rm -rf .github/workflows \\
  && git checkout origin/main -- .github/workflows   # keep the fork's workflows, not upstream's
git commit                    # finish the merge
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
  # Head: upstream's tip with the fork's workflows, so GitHub shows the PR as
  # conflicting until resolved and none of upstream's workflows run on it.
  git checkout -q --detach "$UP"
  hold_back_workflows "$BASE"
  git diff --cached --quiet || bot commit -q -m "Keep the fork's workflows (upstream's are held back)"
  PLACE="$(git rev-parse HEAD)"
  # Same tree as the bot's earlier placeholder: nothing to push.
  if [ -z "$REMOTE" ] || ! git diff --quiet "$REMOTE" "$PLACE"; then
    run git push -q "$LEASE" origin "$PLACE:refs/heads/$BRANCH"
  fi
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
# This includes .github/magister: the token scripts themselves.
WORKFLOWS="$(git diff --name-only "$BASE" HEAD -- .github)"
[ -z "$WORKFLOWS" ] || DRAFT=1

TITLE="Weekly upstream sync: marketingskills $UP_VERSION"
BODY="Merges upstream \`$UPSTREAM\` main (\`${UP:0:7}\`, $UP_VERSION) into the fork: $BEHIND new upstream commits, merged without conflicts. Opened by the weekly \`magister-upstream-sync\` workflow.

Upstream changes: $COMPARE

## Checks

- magister-marketing network-surface scan (the \`make skills-publish\` gate): $SCAN_ROW
- The fork's validators and tests run as this PR's checks once it is out of draft (some skip drafts).
$( [ -n "$WORKFLOWS" ] && printf '\n## Changed under .github (read each before merging)\n\nThe .github scripts and templates from upstream arrive here, as does anything pushed to this branch (workflows are held back). Keep this PR a draft until each file is checked: a workflow that runs on the fork must not use `environment:`, `secrets.` or write `permissions:` (README rule 5).\n\n```\n%s\n```\n' "$WORKFLOWS" || true)
$( [ -n "$HELD" ] && printf '\n## Upstream workflow changes held back\n\nThe fork keeps its own `.github/workflows`; these upstream changes were not brought over:\n\n```\n%s\n```\n' "$HELD" || true)
$( [ -n "$SCAN" ] && printf '\n## Magisterify before merging\n\nPublishing would refuse these surfaces. Rewrite each one for the hosted runtime (a typed `magister-*` tool, or `execution_unavailable`), push to this branch, and re-run `.github/magister/network-scan.sh`:\n\n```\n%s\n```\n' "$SCAN" || true)

## Merging

$( if [ -z "$DRAFT" ] && [ "$HUMAN" = 0 ] && [ "$PUSH" = 1 ]; then echo "This PR merges itself (merge commit) once the checks that run on it pass."; elif [ -z "$DRAFT" ] && [ "$HUMAN" = 0 ]; then echo "This PR merges itself after the next upstream change, or merge it by hand with a merge commit."; else echo "Merge with a merge commit once the items above are done."; fi )
Merging opens the magister-marketing pin-bump PR, which is where the Magister layer is checked on a lane; nothing ships until that PR runs \`make skills-publish\`."

# Put an open PR back in draft before its branch changes, if it must be one.
IS_DRAFT=""
[ -n "$PR_NUM" ] && IS_DRAFT="$(gh pr view "$PR_NUM" -R "$REPO" --json isDraft --jq .isDraft)"
if [ -n "$DRAFT" ] && [ -n "$PR_NUM" ]; then
  [ "$IS_DRAFT" = false ] && run gh pr ready "$PR_NUM" -R "$REPO" --undo
fi
# Ready it before pushing, so checks that skip drafts run on the new head.
if [ -z "$DRAFT" ] && [ "$IS_DRAFT" = true ] && [ "$PUSH" = 1 ]; then
  run gh pr ready "$PR_NUM" -R "$REPO"
fi
if [ "$PUSH" = 0 ]; then
  :
elif [ "$ON_PR" = 1 ]; then
  run git push -q origin "HEAD:refs/heads/$BRANCH" || PUSH=failed   # fast-forward only
else
  run git push -q "$LEASE" origin "HEAD:refs/heads/$BRANCH" || PUSH=failed
fi
if [ "$PUSH" = failed ]; then
  # Someone pushed in between: leave their head as a draft and stop.
  [ -n "$PR_NUM" ] && [ "$IS_DRAFT" = true ] && [ -z "$DRAFT" ] && run gh pr ready "$PR_NUM" -R "$REPO" --undo
  echo "The push to $BRANCH was rejected; it changed during the run. Re-run the workflow." >&2
  exit 1
fi
if [ -n "$PR_NUM" ]; then
  run gh pr edit "$PR_NUM" -R "$REPO" --title "$TITLE" --body "$BODY"
else
  run gh pr create -R "$REPO" --base main --head "$BRANCH" --title "$TITLE" --body "$BODY" ${DRAFT:+--draft}
  PR_NUM="$(gh pr list -R "$REPO" --head "$BRANCH" --state open --json number,isCrossRepository \
    --jq '[.[] | select(.isCrossRepository | not)][0].number // empty')"
fi
# A clean, scanned, bot-only sync merges itself once the checks that ran on it
# pass. Fork main is not production: the pin-bump PR and `make skills-publish` are.
# Self-merge only a head this run pushed: an existing head's checks may have
# run while it was a draft (skipped, and not re-run on ready).
if [ "$PUSH" = 0 ] && [ -z "$DRAFT" ] && [ "$HUMAN" = 0 ]; then
  echo "PR #$PR_NUM's head was not pushed by this run; it merges itself after the next upstream change (or merge it by hand)."
elif [ "$PUSH" = 0 ]; then
  :
elif [ -z "$DRAFT" ] && [ "$HUMAN" = 0 ]; then
  if [ "$DRY" = 1 ]; then
    echo "DRY_RUN: wait for the checks on #${PR_NUM:-<new PR>}, then gh pr merge --merge"
  else
    sleep 60   # let the PR's workflows register
    HEAD_SHA="$(git rev-parse HEAD)"
    # Fails on a real API error (no "|| true"): an error must never skip the wait.
    NCHECKS="$(gh pr view "$PR_NUM" -R "$REPO" --json statusCheckRollup --jq '.statusCheckRollup | length')"
    # A SKILL.md change must be validated: wait up to 5 more minutes for its
    # check to register, and never merge without it.
    if [ "$NCHECKS" = 0 ] && [ -n "$(git diff --name-only "$BASE" HEAD -- '*SKILL.md')" ]; then
      for _ in 1 2 3 4 5; do
        sleep 60
        NCHECKS="$(gh pr view "$PR_NUM" -R "$REPO" --json statusCheckRollup --jq '.statusCheckRollup | length')"
        [ "$NCHECKS" = 0 ] || break
      done
      if [ "$NCHECKS" = 0 ]; then
        echo "::warning::No check registered on PR #$PR_NUM although SKILL.md files changed; not merging. Merge it by hand once validate-skill passes." >&2
        exit 1
      fi
    fi
    if [ "$NCHECKS" != 0 ] && ! gh pr checks "$PR_NUM" -R "$REPO" --watch --fail-fast --interval 30 >/dev/null; then
      gh pr ready "$PR_NUM" -R "$REPO" --undo
      FMARK="<!-- magister-upstream-sync check-failed head=$HEAD_SHA -->"
      BODIES="$(gh pr view "$PR_NUM" -R "$REPO" --json comments --jq '.comments[].body')"
      grep -qF "$FMARK" <<<"$BODIES" || gh pr comment "$PR_NUM" -R "$REPO" --body "$FMARK
A check failed, so this sync was not merged. Fix it on this branch (README, rule 7), mark it ready and merge it with a merge commit."
      exit 1
    fi
    # Merge only the commit that was checked: a push in the meantime stops it.
    gh pr merge "$PR_NUM" -R "$REPO" --merge --match-head-commit "$HEAD_SHA"
  fi
fi
[ "$DRY" = 1 ] && printf '%s\n' "$BODY"
exit 0
