# SaaS Prospecting Reference

For when the user sells SaaS or digital services to other SaaS companies / digital businesses.

---

## ICP Signals That Matter (SaaS branch)

Beyond standard firmographics (industry, size, geography), SaaS prospects are qualified by:

### Technographic signals

- **Tech stack** — do they use complementary tools (your integration target) or competing tools (a switch opportunity)?
- **Recent stack changes** — adding/removing tools signals active vendor evaluation
- **Custom-built vs off-the-shelf** — DIY tooling often means a buyer who'd benefit from your product
- **Free/freemium plan signals** — using a free competitor means they may be ready to upgrade

### Growth signals

- **Funding round** — Series A / B / C in last 6 months = budget + new hires + tool needs
- **Headcount growth** — 10%+ growth in last quarter signals scaling pressure
- **Hiring signals** — specific role openings (e.g., "Head of RevOps" → ICP for revops tooling)
- **Product velocity** — frequent shipping, new features, blog posts = healthy growth motion
- **Open positions for your buyer's role** — if you sell to Marketing Ops and they're hiring one, that's a signal

### Decay signals (downgrade scoring)

- Layoffs in target department
- Funding round >2 years ago with no follow-up
- Product hasn't shipped in 6+ months
- Team page shows founders only (very early — may not have budget)

---

## Discovery Sources (SaaS branch)

Combine 2+ sources for cross-verification.

### Tier 1 — primary discovery

- **Apollo**: firmographic + technographic + contact data. Good for building large initial lists.
- **Clay**: waterfall enrichment, custom scoring, multi-source merges. Best for high-quality smaller lists.
- **ZoomInfo**: enterprise-grade firmographic + intent signals. Expensive; mid-market+.
- **LinkedIn Sales Navigator**: decision-maker mapping. Use manually, never bulk scrape.

### Tier 2 — technographic / growth signals

- **BuiltWith**: tech stack lookups, find sites using specific tools
- **Wappalyzer**: free browser extension + API; lighter tech stack signal
- **Crunchbase**: funding rounds, headcount, founders
- **Pitchbook**: deeper investor data (enterprise/paid)
- **ProductHunt**: recent launches, builder audience
- **Hacker News / Show HN**: technical builders launching products

### Tier 3 — buying signals

- **Job boards** (LinkedIn Jobs, Indeed, AngelList): role openings as signals
- **RB2B / Clearbit Reveal**: visitor identification (warm anonymous traffic)
- **GitHub stars/forks of competitor or adjacent repos**: company-level intent signal (see `tools/integrations/github.md` and the typed
  [`magister-github`](../../magister-github/SKILL.md) integration). Especially
  strong for dev-tool SaaS — a company whose developers starred `vercel/next.js`
  last week may be in-market for adjacent Next.js infrastructure. Count
  companies, not people: never email the developers themselves.
- **Recent blog posts / changelog**: product direction signals
- **G2 reviews mentioning competitor switches**: explicit dissatisfaction signal

#### GitHub company-intent pattern (when audience is developers)

For dev-tool SaaS, GitHub hints at which companies are evaluating a space. It is research, never a list of people to email: GitHub's Acceptable Use Policies forbid using information from GitHub, "whether scraped, collected through our API, or obtained otherwise", to send unsolicited email to its users, however the address was found.

1. Identify 3–5 "anchor" repos: your direct competitors, your category leader, complementary tools your buyer uses
2. Load and follow [`magister-github`](../../magister-github/SKILL.md), then use
   `magister_integration_read` with the reviewed GitHub relative paths to pull
   stargazers or forks. The upstream network CLI is not installed. GitHub is limiting the stargazer and watcher lists to a repository's admins and collaborators (changelog, 2026-06-30): on a repo you don't administer they may come back empty or 403. An empty list is not evidence of no interest; use forks, which are not restricted, or your own repos.
3. Aggregate by the public `company` field (normalize case, strip `@`, merge variants) and rank companies by interest
4. Treat each top company as a candidate account: confirm a buying signal from another source (hiring for the stack, funding, a stated need) before ranking it, then find the right buyer there through your usual B2B sources (Apollo, the company's own site), not the GitHub users
5. Validate with Truelist before adding them to an outreach list

Tradeoffs: a developer's star is a hypothesis about their company, not proof it is in-market: developers star tools for side projects, learning, or a previous job. Several developers at one company starring a niche dev tool is a lead worth checking, and only independent buying evidence makes it Hot. The individual stargazers stay research only.

---

## Qualification Checklist (SaaS branch)

For each candidate, verify:

- [ ] Industry vertical matches ICP
- [ ] Company size (headcount) within range
- [ ] Tech stack includes (or notably excludes) a target technology
- [ ] Funding stage matches buyer maturity
- [ ] At least one growth signal in last 90 days (funding, hiring, product velocity)
- [ ] Decision-maker role exists at the company (named or inferable from job listings)
- [ ] Email contact verifiable
- [ ] No disqualifiers (closed, acquired-and-paused, layoffs, ICP miss)

---

## Output Columns (SaaS branch)

Recommended CSV columns:

```csv
score,company,domain,industry,size_band,country,funding_stage,last_round_date,tech_stack_match,signal,signal_date,contact_name,contact_title,contact_email,email_status,linkedin_url,source_urls,why_prospect,confidence,verified_date,notes
```

For chat table, condense to: Score | Company | Industry | Size | Signal | Contact | Email status | Confidence.

---

## Top Outreach Targets Selection (SaaS)

Prioritize for the top 3–5 hot leads:

1. **Strongest signal recency** — funding 30 days ago beats funding 9 months ago
2. **Tech stack match strength** — known integration partner beats inferred fit
3. **Decision-maker named with verified email** — beats role-pattern-guessed email
4. **Multi-source confidence** — both Apollo + Crunchbase agree beats one source

Each top target gets a one-sentence outreach rationale that names the specific signal: "Raised Series B 30 days ago; hiring Head of RevOps; verified VP of Ops email."

---

## Common Mistakes (SaaS)

1. **Buying lists from Apollo wholesale** without re-verifying email and re-checking firmographics. Stale data is the norm.
2. **Treating tech stack data as 100% accurate**. BuiltWith and Wappalyzer miss things; Clay's waterfalls miss things. Cross-check.
3. **Targeting Series C+ for early-stage SaaS sellers**. The buyer profile is wrong — too many procurement hoops, too much red tape.
4. **Targeting Series Pre-Seed seed** for products requiring meaningful budget. They have neither budget nor evaluator bandwidth.
5. **Ignoring intent data when it exists** (ZoomInfo Intent, 6sense, etc.) — pre-warm signals beat cold every time.
