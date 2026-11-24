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

`upstream-sync.sh` merges upstream `main` into the branch `magister/upstream-sync` and opens one PR. It never pushes to `main`.

- **Clean merge:** the PR lists the result of each check: `validate-skills.sh`, `check-versions.mjs`, `check-hidden-content.mjs`, the regression and packaging tests, and magister-marketing's network-surface scan, the same gate `make skills-publish` applies. The PR opens as a draft when a check fails or the scan lists surfaces to Magisterify.
- **Conflicts:** a draft PR from upstream's tip, listing the conflicting files and the commands to resolve them. When a sync PR is already open, the run comments on it instead.
- **A sync PR left open:** the next run merges `main` and the new upstream into the same branch, so fixes pushed to it are kept.

### Resolving: the layer rule

Take upstream's content and keep the Magister layer.

1. Frontmatter: keep this fork's description and take upstream's `version`.
2. Where upstream adds `.agents/brand.md`, keep the fork's `BRAND.md` block.
3. Where upstream adds `curl`, `npx`, `fetch(`, `git clone` or a loopback call, keep or write the hosted form: a typed `magister-*` tool, or `execution_unavailable` with a user-side step.
4. Where the fork's text is just an older upstream copy (check with `git log`), take upstream's.
5. Check that every network surface is resolved:
   ```bash
   bash .github/magister/network-scan.sh <path to a magister-marketing checkout>
   ```
6. Run `./validate-skills.sh`, `node scripts/check-versions.mjs --base origin/main` and `bash tests/run-regression.sh`.
7. Merge the PR with a merge commit, never a squash, so the next sync starts from this merge.

## Pin bump

Every push to `main` opens or refreshes the draft PR `bump/marketingskills-magister` on magister-marketing. That PR lists the changed, added and removed skills. Nothing ships until someone runs the dev cycle in its body: a lane test, `make skills-check`, the merge train, then `make skills-publish`. A removed or renamed skill needs gateway slug aliases and a `focus_skills` migration first.

## One-time setup

1. Actions → enable workflows for this fork.
2. Disable upstream's two workflows that write to `main` or publish releases, which should only run upstream:
   ```bash
   gh workflow disable release.yml -R Magister-Marketing/marketingskills-magister
   gh workflow disable sync-skills.yml -R Magister-Marketing/marketingskills-magister
   ```
3. Add the secret `MAGISTER_SYNC_TOKEN`: a fine-grained token owned by Magister-Marketing, for the repos `marketingskills-magister` and `magister-marketing`, with **Contents: read and write** and **Pull requests: read and write**. It pushes the sync and bump branches, opens their PRs, and reads magister-marketing's network scan.
