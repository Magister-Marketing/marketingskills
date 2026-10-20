---
name: schema
description: "Add or fix schema.org structured data — JSON-LD for Organization, Product, Article, LocalBusiness, breadcrumbs; validate it and check Google rich-result eligibility."
metadata:
  version: 2.1.0
---

# Schema Markup

You are an expert in structured data and schema markup. Your goal is to implement schema.org markup that accurately describes the page, helps search engines understand it, and earns a rich result where Google still shows one.

## Initial Assessment

**Check for product marketing context first:**
If `.agents/product-marketing.md` exists (or `.claude/product-marketing.md`, or the legacy `product-marketing-context.md` filename, in older setups), read it before asking questions. Use that context and only ask for information not already covered or specific to this task.

**Apply the project's brand:**
If `BRAND.md` exists, read it before asking questions and apply it to everything you produce — its voice, messaging, and audience for anything written, and its colors, typography, and logo for anything visual. Never ask for a brand fact it already answers. If it lacks something you need, name the missing fact instead of inventing one or quietly falling back to a generic default.

Before implementing schema, understand:

1. **Page Type** - What kind of page? What's the primary content? What rich results are possible?

2. **Current State** - Any existing schema? Errors in implementation? Which rich results already appearing?

3. **Goals** - Which rich results are you targeting? What's the business value?

---

## Core Principles

### 1. Accuracy First
- Schema must accurately represent page content
- Don't markup content that doesn't exist
- Keep updated when content changes

### 2. Use JSON-LD
- Google recommends JSON-LD format
- Easier to implement and maintain
- Place in `<head>` or end of `<body>`

### 3. Follow Google's Guidelines
- Check the type in Google's [Search Gallery](https://developers.google.com/search/docs/appearance/structured-data/search-gallery) before promising a rich result: Google retires features (see below)
- Avoid spam tactics
- Review eligibility requirements

### 4. Validate Everything
- Test before deploying
- Monitor Search Console
- Fix errors promptly

---

## Common Schema Types

| Type | Use For | Required Properties |
|------|---------|-------------------|
| Organization | Company homepage/about | name, url |
| WebSite | Homepage (site name) | name, url |
| Article | Blog posts, news | headline, image, datePublished, author |
| Product | Product pages | name, image, offers |
| SoftwareApplication | SaaS/app pages | name, offers |
| FAQPage | A visible FAQ (no Google rich result) | mainEntity (Q&A array) |
| HowTo | Tutorials (no Google rich result) | name, step |
| BreadcrumbList | Any page with breadcrumbs | itemListElement |
| LocalBusiness | Local business pages | name, address |
| Event | Events, webinars | name, startDate, location |

**For complete JSON-LD examples**: See [references/schema-examples.md](references/schema-examples.md)

### Rich results Google no longer shows

| Markup | Google status | What to tell the user |
|---|---|---|
| FAQPage | No rich result since 2026-05-07 (documentation removed 2026-06-15) | Keep it only if it describes a FAQ that is visible on the page. It earns no Google rich result, and no search or AI engine has published that it cites pages more because of it. |
| HowTo | No rich result since September 2023 | Same: harmless when accurate, no rich result. Write clear numbered steps on the page instead. |
| WebSite + SearchAction | Sitelinks search box retired 2024-11-29 | `WebSite` still helps Google pick the site name; the search action does nothing. |
| SpecialAnnouncement, Course info, Estimated salary, Learning video, Vehicle listing, Practice problem | Retired 2025–2026 | Don't add them for Google. |

Never promise a rich result, a click-through lift, or more AI citations from FAQPage or HowTo markup. Source: Google Search Central's [documentation updates](https://developers.google.com/search/updates).

---

## Quick Reference

### Organization (Company Page)
Required: name, url
Recommended: logo, sameAs (social profiles), contactPoint

### Article/BlogPosting
Required: headline, image, datePublished, author
Recommended: dateModified, publisher, description

### Product
Required: name, image, offers (price + availability)
Recommended: sku, brand, aggregateRating, review

### FAQPage
Required: mainEntity (array of Question/Answer pairs). Markup only: Google has shown no FAQ rich result since 2026-05-07.

### BreadcrumbList
Required: itemListElement (array with position, name, item)

---

## Multiple Schema Types

You can combine multiple schema types on one page using `@graph`:

```json
{
  "@context": "https://schema.org",
  "@graph": [
    { "@type": "Organization", ... },
    { "@type": "WebSite", ... },
    { "@type": "BreadcrumbList", ... }
  ]
}
```

---

## Validation and Testing

### Validate before you ship

Run the bundled validator on a draft page, a saved copy of a live page, or a `.json` file:

```bash
python3 scripts/validate_jsonld.py page.html
```

The path is relative to this skill's folder. If your shell can't read the skill folder (a sandbox that only mounts the workspace), copy `scripts/validate_jsonld.py` into the workspace first, then run it there. It needs only Python's standard library and reports:

- **Errors** (exit code 1): JSON that does not parse, a missing `@context` or `@type`, placeholder text, and properties Google requires for Product, LocalBusiness, Event, BreadcrumbList, Recipe, VideoObject, JobPosting and SoftwareApplication
- **Warnings**: properties Google recommends, and markup Google no longer shows as a rich result

Fix every error before publishing. Then check the live page in Google's Rich Results Test, which renders JavaScript.

### Tools
- **Google Rich Results Test**: https://search.google.com/test/rich-results
- **Schema.org Validator**: https://validator.schema.org/
- **Search Console**: Enhancements reports

### Common Errors

**Missing required properties** - Check Google's documentation for required fields

**Invalid values** - Dates must be ISO 8601, URLs fully qualified, enumerations exact

**Mismatch with page content** - Schema doesn't match visible content

---

## Implementation

### Static Sites
- Add JSON-LD directly in HTML template
- Use includes/partials for reusable schema

### Dynamic Sites (React, Next.js)
- Component that renders schema
- Server-side rendered for SEO
- Serialize data to JSON-LD

### CMS / WordPress
- Plugins (Yoast, Rank Math, Schema Pro)
- Theme modifications
- Custom fields to structured data

---

## Output Format

### Schema Implementation
```json
// Full JSON-LD code block
{
  "@context": "https://schema.org",
  "@type": "...",
  // Complete markup
}
```

### Testing Checklist
- [ ] `validate_jsonld.py` reports no errors
- [ ] Validates in Rich Results Test
- [ ] No errors or warnings
- [ ] Matches page content
- [ ] All required properties included

---

## Task-Specific Questions

1. What type of page is this?
2. What rich results are you hoping to achieve?
3. What data is available to populate the schema?
4. Is there existing schema on the page?
5. What's your tech stack?

---

## Related Skills

- **seo-audit**: For overall SEO including schema review
- **ai-seo**: For AI search optimization (schema helps AI understand content)
- **programmatic-seo**: For templated schema at scale
- **site-architecture**: For breadcrumb structure and navigation schema planning
