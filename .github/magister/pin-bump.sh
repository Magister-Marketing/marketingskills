#!/usr/bin/env bash
# Open (or refresh) one draft PR on magister-marketing that points the
# magister-marketingskills submodule at this fork's main.
#
# Run from the root of a full-history marketingskills-magister checkout.
# Env: GH_TOKEN (contents and pull requests on magister-marketing),
#      NEW_SHA (default: HEAD), MM_REPO, DRY_RUN=1.
# Merging the PR ships nothing: skills reach machines only through
# `make skills-publish`, after the lane check the PR body lists.
set -euo pipefail

MM_REPO="${MM_REPO:-Magister-Marketing/magister-marketing}"
FORK_REPO="${GITHUB_REPOSITORY:-Magister-Marketing/marketingskills-magister}"
SUB="magister-marketingskills"
BRANCH="bump/marketingskills-magister"
NEW="$(git rev-parse "${NEW_SHA:-HEAD}")"
FORK="$(pwd)"
DRY="${DRY_RUN:-0}"
run() { if [ "$DRY" = 1 ]; then echo "DRY_RUN: $*"; else "$@"; fi; }

WORK="$(mktemp -d)"
git clone -q --depth 1 --no-recurse-submodules \
  "https://x-access-token:${GH_TOKEN}@github.com/$MM_REPO.git" "$WORK/mm"
cd "$WORK/mm"
OLD_MAIN="$(git ls-tree HEAD "$SUB" | awk '{print $3}')"
[ -n "$OLD_MAIN" ] || { echo "no $SUB gitlink in $MM_REPO" >&2; exit 2; }
if [ "$OLD_MAIN" = "$NEW" ]; then echo "$MM_REPO main already pins ${NEW:0:7}."; exit 0; fi

PR_NUM="$(gh pr list -R "$MM_REPO" --head "$BRANCH" --state open --json number --jq '.[0].number // empty')"
REMOTE="$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)"
if [ -n "$PR_NUM" ]; then
  # Keep anything a person added to the open bump PR (lane notes, fixes).
  git fetch -q --depth 1 origin "$BRANCH"
  git checkout -q -B "$BRANCH" FETCH_HEAD
  if [ "$(git ls-tree HEAD "$SUB" | awk '{print $3}')" = "$NEW" ]; then echo "PR #$PR_NUM already pins ${NEW:0:7}."; exit 0; fi
else
  git checkout -q -B "$BRANCH"
fi

git update-index --add --cacheinfo "160000,$NEW,$SUB"
# The fork was renamed from Magister-Marketing/marketingskills (2026-11-24).
sed -i.bak "s#github.com/Magister-Marketing/marketingskills.git#github.com/$FORK_REPO.git#" .gitmodules && rm -f .gitmodules.bak
git add .gitmodules

# What changes for the agent, read from the fork's own history.
cd "$FORK"
COMMITS="$(git log -n 40 --oneline --no-merges "$OLD_MAIN..$NEW" -- skills tools)"
NCOMMITS="$(git rev-list --count --no-merges "$OLD_MAIN..$NEW")"
SKILLS_CHANGED="$(git diff --name-only "$OLD_MAIN" "$NEW" -- skills | cut -d/ -f2 | sort -u | tr '\n' ' ')"
ADDED="$(comm -13 <(git ls-tree --name-only "$OLD_MAIN" skills/ | sort) <(git ls-tree --name-only "$NEW" skills/ | sort) | sed 's#skills/##' | tr '\n' ' ')"
REMOVED="$(comm -23 <(git ls-tree --name-only "$OLD_MAIN" skills/ | sort) <(git ls-tree --name-only "$NEW" skills/ | sort) | sed 's#skills/##' | tr '\n' ' ')"
cd "$WORK/mm"

git -c user.name="magister-sync[bot]" -c user.email="magister-sync@users.noreply.github.com" \
  commit -q -m "Bump magister-marketingskills to ${NEW:0:7} (marketingskills-magister main)" \
  -m "https://github.com/$FORK_REPO/compare/$OLD_MAIN...$NEW"

TITLE="Bump marketing skills to marketingskills-magister ${NEW:0:7}"
BODY="$(cat <<EOF
## Summary

Points the \`$SUB\` submodule at [\`${NEW:0:7}\`](https://github.com/$FORK_REPO/commit/$NEW), the current \`main\` of [$FORK_REPO](https://github.com/$FORK_REPO). Opened by the fork's \`magister-pin-bump\` workflow when its \`main\` moved. It replaces \`${OLD_MAIN:0:7}\`: $NCOMMITS commits, [compare](https://github.com/$FORK_REPO/compare/$OLD_MAIN...$NEW).

- Skills changed: ${SKILLS_CHANGED:-none}
- Skills added: ${ADDED:-none}
- Skills removed or renamed: ${REMOVED:-none}$( [ -n "$REMOVED" ] && printf '\n  **A removed or renamed skill needs gateway slug aliases and a \`focus_skills\` data migration first (\`skills/CLAUDE.md\`).**')

<details><summary>Commits touching skills/ or tools/</summary>

\`\`\`
${COMMITS:-none}
\`\`\`

</details>

## Before and after

Not run yet. Before this leaves draft, run the dev cycle in \`AGENTS.md\` on a lane: the same chats on \`main\` and on this branch for the changed skills, judged by the raw tool results.

## Tests

Not run by the workflow. Run \`make skills-check\`, \`make agent-network-inventory-check\` and \`make agent-skill-selection-check\` (the catalog must stay \`tier=full\`).

## To fully deploy

1. Merge with the merge train.
2. \`make skills-publish\` from the updated \`main\`. No image rebuild is needed (https://github.com/$MM_REPO/issues/706).
3. Verify with \`make skills-status\`.

Deploy: pending.
EOF
)"

if [ -n "$PR_NUM" ]; then run git push -q origin "HEAD:refs/heads/$BRANCH"   # fast-forward only
else run git push -q "--force-with-lease=refs/heads/$BRANCH:$REMOTE" origin "HEAD:refs/heads/$BRANCH"; fi
if [ -n "$PR_NUM" ]; then run gh pr edit "$PR_NUM" -R "$MM_REPO" --title "$TITLE" --body "$BODY"
else run gh pr create -R "$MM_REPO" --draft --base main --head "$BRANCH" --title "$TITLE" --body "$BODY"; fi
[ "$DRY" = 1 ] && printf '%s\n' "$BODY"
exit 0
