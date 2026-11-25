# Keeping this fork in sync

This repo is the Magister fork of [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills). It is the source of truth for the marketing skills Magister ships: upstream plus a Magister layer. magister-marketing pins it as the `magister-marketingskills` submodule, and `make skills-publish` there ships the pinned commit to every project machine.

```
coreyhaines31/marketingskills ──weekly sync PR──▶ marketingskills-magister ──pin-bump PR──▶ magister-marketing ──make skills-publish──▶ machines
            ▲                                                │
            └────────── "better in general" changes, as reviewed upstream PRs ──┘
```

## What flows where

| Change | Lives in | How it moves |
|---|---|---|
| Anything new upstream | upstream | Weekly sync PR here (`magister-upstream-sync.yml`) |
| Magister-only: `BRAND.md`, the `magister-library` instructions, `magister-*` tool routes and proxy endpoints, "no raw network" rewrites (`execution_unavailable`), short catalog descriptions | this fork | Stays here |
| Better for everyone: a sharper rule, less overlap between skills | this fork first, then upstream | A hand-written PR to upstream in upstream's voice, without the Magister specifics. Once it merges, the next sync replaces the fork's copy with upstream's wording |
| This fork's `main` moved | this fork | Pin-bump PR on magister-marketing (`magister-pin-bump.yml`) |
| Magister-only skills, such as `outbound-prospecting` and the `magister-*` integrations | magister-marketing `skills/` | Not part of this sync |

## Weekly sync (Mondays 16:00 UTC, or Actions → "Magister upstream sync" → Run workflow)

`upstream-sync.sh` merges upstream `main` into the branch `magister/upstream-sync` and opens one PR. It never pushes to `main`, and it runs no code from upstream: the fork's validators and tests (upstream's own workflows, which come with the merge) run as the PR's checks.

- **Clean merge:** the PR body has the result of magister-marketing's network-surface scan, the same gate `make skills-publish` applies. The PR is a draft unless the scan passed.
- **Conflicts:** a draft PR whose head is upstream's tip, listing the conflicting files and the commands to resolve them.
- **A sync PR left open:** the next run merges `main` and the new upstream into that branch, so fixes pushed to it are kept. If that merge conflicts, the run leaves the branch alone and comments once with the commands.
- A leftover `magister/upstream-sync` branch with its own commits and no open PR stops the run instead of being overwritten.

### Resolving: the layer rule

Take upstream's content and keep the Magister layer.

1. Frontmatter: keep this fork's description and take upstream's `version`.
2. Where upstream adds `.agents/brand.md`, keep the fork's `BRAND.md` block.
3. Where upstream adds `curl`, `npx`, `fetch(`, `git clone` or a loopback call, keep or write the hosted form: a typed `magister-*` tool, or `execution_unavailable` with a user-side step.
4. Where the fork's text is just an older upstream copy (check with `git log`), take upstream's.
5. Upstream workflows that write to `main` or publish (`release.yml`, `sync-skills.yml`) keep the fork's `if: github.repository == 'coreyhaines31/marketingskills'` guard, so they run only upstream.
6. Check that every network surface is resolved. The script only reads the monorepo checkout:
   ```bash
   bash .github/magister/network-scan.sh <path to a magister-marketing checkout>
   ```
7. Run `./validate-skills.sh`, `node scripts/check-versions.mjs --base origin/main` and `bash tests/run-regression.sh`.
8. Merge the PR with a merge commit, never a squash, so the next sync starts from this merge.

## Pin bump

Every push to `main` opens or refreshes the draft PR `bump/marketingskills-magister` on magister-marketing. That PR lists the changed, added and removed skills. Nothing ships until someone runs the dev cycle in its body: a lane test, `make skills-check`, the merge train, then `make skills-publish`. A removed or renamed skill needs gateway slug aliases and a `focus_skills` migration first.

## One-time setup, in this order

1. Merge the first catch-up sync, which adds the guard on `release.yml` and `sync-skills.yml` (rule 5), and this automation.
2. Create a fine-grained token owned by Magister-Marketing for the repos `marketingskills-magister` and `magister-marketing`, with **Contents**, **Pull requests** and **Workflows** set to read and write. Workflows is needed because a sync pushes upstream's workflow changes.
3. Settings → Environments → New environment `magister-sync`. Under deployment branches, allow only `main`. Add the token as the environment secret `MAGISTER_SYNC_TOKEN`. Don't add it as a repository secret: a workflow on a PR branch, including one a sync brings in, could read it.
4. Actions → enable workflows for this fork.
