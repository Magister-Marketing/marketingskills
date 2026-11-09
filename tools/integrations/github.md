# GitHub

GitHub REST API for developer-intent research: which companies' developers star, fork, or watch a repo.

**Never a mailing list.** GitHub's Acceptable Use Policies forbid using information from GitHub, "whether scraped, collected through our API, or obtained otherwise", to send unsolicited email to its users. Finding the address somewhere else does not change that. Use the data for company-level aggregation, consent matching (people who already opted in), opt-in calls to action, and fork research — never to email, DM, or enrich individual users with email.

## Capabilities

| Integration | Available | Notes |
|-------------|-----------|-------|
| API | ✓ | Public REST API, well-documented |
| MCP | - | Several community MCP servers exist; not bundled here |
| CLI | ✓ | [github-prospects.js](../clis/github-prospects.js) — stargazers, forks, watchers, user, rate-limit |
| SDK | ✓ | Official Octokit (JS, Python, Ruby, .NET, Go) |

## Authentication

- **Type**: Personal Access Token (PAT) or Fine-Grained PAT
- **Header**: `Authorization: Bearer {token}`
- **Get token**: https://github.com/settings/tokens
- **Scopes for prospecting**:
  - Public data (stargazers, forks, public profiles): **no scope required** with a token, or unauthenticated
  - Public repo metadata: `public_repo` scope
- **Env var**: `GITHUB_TOKEN`

### Rate limits

| Auth | Limit | When you hit it |
|------|-------|-----------------|
| Unauthenticated | 60 req/hr | Fine for one-off small lookups |
| Authenticated PAT | 5,000 req/hr | Sufficient for a 10K-star repo pull in one hour |
| GitHub App | 5,000–15,000 req/hr | For high-volume use |

A 1,000-star repo with full enrichment (1 list call + 1 profile call per user) = ~1,011 requests. Always set a token.

## Common Agent Operations

### List stargazers (users who starred a repo)

```bash
GET https://api.github.com/repos/{owner}/{repo}/stargazers?per_page=100&page=1

Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
Authorization: Bearer {token}
```

Pagination via `Link` header (`rel="next"`, `rel="last"`). Default 30 per page, max 100.

Returns array of user objects with `login`, `id`, `html_url`, `type` (User or Organization). Full profile fields (email, company, blog, bio, location) require a follow-up call per user.

### List forks (gives fork owner profiles)

```bash
GET https://api.github.com/repos/{owner}/{repo}/forks?per_page=100&page=1
```

Each fork object includes the `owner` (the user/org that forked). Forks are a stronger signal than stars — they imply intent to modify, not just bookmark.

### List watchers (subscribers)

```bash
GET https://api.github.com/repos/{owner}/{repo}/subscribers?per_page=100&page=1
```

GitHub's "watch" → API's "subscribers". Smaller pool than stargazers but signals deeper engagement.

### Get user profile (enrichment)

```bash
GET https://api.github.com/users/{username}
```

Returns: `name`, `company`, `blog`, `email` (if public), `bio`, `twitter_username`, `location`, `public_repos`, `followers`, `created_at`, `hireable`.

**Key fields for prospecting**:
- `email`: only ~5–20% of users publish this. Always nullable. Not for outreach: GitHub's terms forbid unsolicited email to its users.
- `company`: many users include `@org` syntax — strip the `@` for plain company name.
- `blog`: often a personal website where contact info is published.
- `twitter_username` / `bio`: useful for cross-channel research.

### Check rate limit

```bash
GET https://api.github.com/rate_limit
```

## Prospecting Workflows

### Workflow 1 — Stargazers of a competitor or adjacent tool

```bash
# 100 stargazers with profiles, for company-level aggregation
node tools/clis/github-prospects.js stargazers vercel/next.js \
  --limit 100 --enrich --with-company --format csv > nextjs-stars.csv
```

Count rows per `company` (normalized) to rank the companies showing interest. Reach the right buyer at those companies through other sources; never look up emails for the stargazers themselves.

### Workflow 2 — Forks of your own repo (warm intent)

People who fork your repo have already shown direct interest. Read what they change (product research), and invite them to opt in from the README or release notes rather than emailing them.

```bash
node tools/clis/github-prospects.js forks yourorg/yourrepo \
  --enrich --with-company --format csv > my-forks.csv
```

### Workflow 3 — Watchers of a category-defining repo

Watchers are smaller in number but higher in intent — they're tracking changes, not just bookmarking.

```bash
node tools/clis/github-prospects.js watchers tldraw/tldraw \
  --enrich --with-company --format csv > tldraw-watchers.csv
```

## CLI Reference

```bash
# Stargazers
node tools/clis/github-prospects.js stargazers <owner/repo> \
  [--limit N] [--enrich] [--with-email] [--with-company] \
  [--with-blog] [--type User|Organization] [--format csv|json]

# Forks
node tools/clis/github-prospects.js forks <owner/repo> [...same flags]

# Watchers (subscribers in API terms)
node tools/clis/github-prospects.js watchers <owner/repo> [...same flags]

# Single user lookup
node tools/clis/github-prospects.js user <username>

# Check rate limit
node tools/clis/github-prospects.js rate-limit
```

**Flags**:
- `--limit N`: cap total results pulled from the list endpoint
- `--target N`: when filtering with `--with-*`, stop enriching as soon as N users match (saves quota on restrictive filters)
- `--enrich`: fetch full profile per user (1 extra request each)
- `--with-email` / `--with-company` / `--with-blog`: filter to users with these fields set (implies `--enrich`)
- `--type User|Organization`: filter by account type
- `--format csv`: output CSV; default is JSON
- `--dry-run`: preview the request without sending

## When to Use

- **SaaS account research** (primary use case): which companies' developers star a competitor, complement, or category-defining repo
- **Open-source product research**: see who forks or watches your own repo and read what they change; invite them to opt in from the README or release notes rather than contacting them
- **Developer-tool ICP discovery**: stargazers of `next.js`, `prisma`, `tailwindcss`, etc. show which companies build on Next.js / Prisma / Tailwind
- **Trigger event monitoring**: recent forks of a competitor's repo by developers at one company often signal evaluation at that company

## When NOT to Use

- **To build an email or DM list** — never. GitHub's Acceptable Use Policies forbid using information from GitHub, "whether scraped, collected through our API, or obtained otherwise", to send unsolicited email to its users. Looking the address up in Apollo, Clay, or Hunter does not change that.
- **To contact the individual users at all** — reach the right buyer at an interested company through other sources instead.
- **Hyper-broad lists** — a repo with 100K+ stars is mostly noise. Smaller, more specific repos (5K–25K stars) give a clearer company signal.

## Compliance Notes

- **Reading is fine, contacting is not** — reading public data through the API within its rate limits is legitimate use. Emailing, DMing, or bulk-contacting the users it lists is forbidden by GitHub's Acceptable Use Policies, however the address was found.
- **Emails published on GitHub profiles** are not consent to be emailed. Don't collect them for outreach.
- **Source lineage** — for every company you count, keep the source repo and the date of the pull.
- **Cool-down between large pulls** — even at 5,000 req/hr, don't burst-fingerprint. Pagination is naturally paced; respect `X-RateLimit-Remaining` headers.

## Pairing with Other Tools

Typical GitHub company-intent pipeline:

1. Pull stargazers/forkers via this CLI (`--with-company`)
2. **Aggregate by company**: normalize the free-text `company` field (case, `@`, obvious variants) and rank companies by interest
3. **Find the right buyer** at the top companies through your usual B2B sources (Apollo, the company's own site) — never the GitHub users themselves
4. **Validate** those buyers' emails via Truelist before adding them to an outreach list
5. **Hand off** to the cold-email skill for one-to-one, low-volume outreach to those buyers

See `skills/prospecting/references/saas-prospecting.md` and `data-sources.md` for the full prospecting framework.

## Relevant Skills

- prospecting (primary use case)
- cold-email (outreach to buyers at interested companies, sourced elsewhere)
- competitor-profiling (deeper research on the companies that show interest)
