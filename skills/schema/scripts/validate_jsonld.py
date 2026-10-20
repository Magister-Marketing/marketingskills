#!/usr/bin/env python3
"""Validate the JSON-LD in HTML or JSON files before they ship.

Usage:
    python3 validate_jsonld.py page.html [more.html schema.json ...]
    cat page.html | python3 validate_jsonld.py -

Standard library only. For every file it reports:

- errors: JSON that does not parse, a missing @context or @type, placeholder
  text, and properties Google requires for the common rich-result types;
- warnings: properties Google recommends, and types or features Google no
  longer shows as rich results (the markup is harmless, but promises no
  rich result).

Exit code 1 when any file has an error, 0 otherwise. Valid markup is not a
promise of a rich result; check the live page in Google's Rich Results Test.

Adapted from hooks/validate-schema.py in AgriciDaniel/claude-seo
(https://github.com/AgriciDaniel/claude-seo), used under the MIT License:

    Copyright (c) 2026 agricidaniel

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to permit
    persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
    NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
    DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
    USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any

# A <script> tag whose attributes may hold quoted ">" characters. A quoted
# span is consumed whole so `data-x="a>b"` cannot end the tag early, and the
# unquoted class excludes both quotes so a stray apostrophe cannot make the
# match backtrack exponentially.
_ATTRS = r'(?:"[^"]*"|\'[^\']*\'|[^"\'>])*'
SCRIPT_RE = re.compile(r"<script\b(" + _ATTRS + r")>(.*?)</script\s*>", re.DOTALL | re.IGNORECASE)
LD_JSON_TYPE_RE = re.compile(
    r"""(?:^|\s)type\s*=\s*(?:"application/ld\+json"|'application/ld\+json'|application/ld\+json(?=\s|$))""",
    re.IGNORECASE,
)
# Bodies rendered at runtime (JSX, Vue, PHP, EJS, template literals) are not
# JSON yet and cannot be checked statically.
TEMPLATE_RE = re.compile(r"^(?:<\?|<%|\{\{|\{@html\b|\$\{|\{\s*[A-Za-z_$][\w$.]*)")

SCHEMA_ORG = {"https://schema.org", "http://schema.org", "https://schema.org/", "http://schema.org/"}
PLACEHOLDERS = (
    "[business name]", "[city]", "[state]", "[phone]", "[address]", "[your",
    "[insert", "[url]", "[email]", "lorem ipsum", "example.com", "555-0",
)
BARE_PLACEHOLDER_RE = re.compile(r"\b(?:REPLACE(?:_[A-Z]+)*|TODO|TBD|XXX+)\b")

# Types Google no longer shows as a rich result. Dates are from Google Search
# Central's documentation updates (https://developers.google.com/search/updates).
RETIRED = {
    "FAQPage": "FAQ rich results stopped showing in Google Search on 2026-05-07",
    "HowTo": "HowTo rich results stopped showing in Google Search in September 2023",
    "SpecialAnnouncement": "special announcements stopped showing in Google Search on 2025-07-31",
    "ClaimReview": "Google announced it is phasing out fact-check rich results (2025-06-12)",
}

# Rich-result types and the properties Google requires for them. "One of"
# groups need at least one member present.
REQUIRED: dict[str, tuple[tuple[str, ...], ...]] = {
    "Product": (("name",), ("offers", "review", "aggregateRating")),
    "SoftwareApplication": (("name",), ("offers",), ("aggregateRating", "review")),
    "Event": (("name",), ("startDate",), ("location",)),
    "BreadcrumbList": (("itemListElement",),),
    "Recipe": (("name",), ("image",)),
    "VideoObject": (("name",), ("thumbnailUrl",), ("uploadDate",)),
    "JobPosting": (("title",), ("description",), ("datePosted",), ("hiringOrganization",)),
    "LocalBusiness": (("name",), ("address",)),
}
RECOMMENDED: dict[str, tuple[str, ...]] = {
    "Organization": ("name", "url", "logo"),
    "Article": ("headline", "image", "datePublished", "author"),
    "LocalBusiness": ("telephone", "url", "openingHoursSpecification", "geo"),
}
ARTICLE_TYPES = {"Article", "NewsArticle", "BlogPosting", "TechArticle"}
LOCAL_BUSINESS_TYPES = {
    "LocalBusiness", "AccountingService", "AutoDealer", "AutoRepair", "Bakery", "BarOrPub",
    "BeautySalon", "CafeOrCoffeeShop", "ChildCare", "Dentist", "DaySpa", "Electrician",
    "ExerciseGym", "FinancialService", "FoodEstablishment", "GeneralContractor", "HairSalon",
    "HealthClub", "HomeAndConstructionBusiness", "Hotel", "HousePainter", "HVACBusiness",
    "InsuranceAgency", "LegalService", "Attorney", "Locksmith", "LodgingBusiness",
    "MedicalBusiness", "MedicalClinic", "MovingCompany", "Optician", "Pharmacy", "Physician",
    "Plumber", "ProfessionalService", "RealEstateAgent", "Restaurant", "RoofingContractor",
    "Store", "ClothingStore", "VeterinaryCare",
}


def extract_blocks(text: str) -> list[str]:
    """Bodies of every <script type="application/ld+json"> in an HTML file."""
    return [body for attrs, body in SCRIPT_RE.findall(text) if LD_JSON_TYPE_RE.search(attrs)]


def _types(node: dict[str, Any]) -> list[str]:
    value = node.get("@type")
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [v for v in value if isinstance(v, str)]
    return []


def _has(node: dict[str, Any], key: str) -> bool:
    value = node.get(key)
    return value not in (None, "", [], {})


def _canonical_type(name: str) -> str:
    if name in LOCAL_BUSINESS_TYPES:
        return "LocalBusiness"
    if name in ARTICLE_TYPES:
        return "Article"
    return name


def check_node(node: dict[str, Any], where: str, *, context: bool, errors: list[str], warnings: list[str]) -> None:
    """Check one JSON-LD node and recurse into @graph members."""
    if "@context" in node:
        ctx = node["@context"]
        ctx_values = ctx if isinstance(ctx, list) else [ctx.get("@vocab") if isinstance(ctx, dict) else ctx]
        if not any(isinstance(v, str) and v in SCHEMA_ORG for v in ctx_values):
            errors.append(f"{where}: @context should be https://schema.org")
        context = True
    elif not context:
        errors.append(f"{where}: missing @context")

    graph = node.get("@graph")
    if "@graph" in node and not isinstance(graph, list):
        errors.append(f"{where}: @graph must be a list")
    names = _types(node)
    if not names and not isinstance(graph, list):
        errors.append(f"{where}: missing @type")

    own = json.dumps({k: v for k, v in node.items() if k != "@graph"}, ensure_ascii=False)
    lowered = own.lower()
    for placeholder in PLACEHOLDERS:
        if placeholder in lowered:
            errors.append(f"{where}: placeholder text {placeholder!r}")
    for match in sorted(set(BARE_PLACEHOLDER_RE.findall(own))):
        errors.append(f"{where}: placeholder text {match!r}")

    label = f"{where} ({'/'.join(names)})" if names else where
    for name in names:
        if name in RETIRED:
            warnings.append(f"{label}: no Google rich result; {RETIRED[name]}")
        kind = _canonical_type(name)
        for group in REQUIRED.get(kind, ()):
            if not any(_has(node, key) for key in group):
                wanted = " or ".join(group)
                errors.append(f"{label}: Google requires {wanted}")
        missing = [key for key in RECOMMENDED.get(kind, ()) if not _has(node, key)]
        if missing:
            warnings.append(f"{label}: Google recommends {', '.join(missing)}")
    if "WebSite" in names:
        action = json.dumps(node.get("potentialAction", ""))
        if "SearchAction" in action:
            warnings.append(
                f"{label}: SearchAction no longer earns a sitelinks search box "
                "(Google retired it on 2024-11-29)"
            )

    if isinstance(graph, list):
        for index, member in enumerate(graph, 1):
            if isinstance(member, dict):
                check_node(member, f"{where} @graph[{index}]", context=context, errors=errors, warnings=warnings)
            else:
                errors.append(f"{where} @graph[{index}]: must be an object")


def validate_text(text: str, *, is_json: bool) -> tuple[list[str], list[str], int]:
    """Return (errors, warnings, block count) for one file's text."""
    errors: list[str] = []
    warnings: list[str] = []
    blocks = [text] if is_json else extract_blocks(text)
    checked = 0
    for number, raw in enumerate(blocks, 1):
        body = raw.strip()
        where = f"block {number}"
        if TEMPLATE_RE.match(body):
            warnings.append(f"{where}: rendered at runtime; validate the rendered page instead")
            continue
        checked += 1
        try:
            data = json.loads(body)
        except json.JSONDecodeError as exc:
            errors.append(f"{where}: invalid JSON ({exc.msg} at line {exc.lineno}, column {exc.colno})")
            continue
        nodes = data if isinstance(data, list) else [data]
        for index, node in enumerate(nodes, 1):
            node_where = where if len(nodes) == 1 else f"{where}[{index}]"
            if isinstance(node, dict):
                check_node(node, node_where, context=False, errors=errors, warnings=warnings)
            else:
                errors.append(f"{node_where}: must be a JSON object")
    return errors, warnings, checked


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    failed = False
    for path in argv:
        if path == "-":
            text, name = sys.stdin.read(), "stdin"
        else:
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    text, name = handle.read(), path
            except OSError as exc:
                print(f"{path}: cannot read ({exc.strerror})")
                failed = True
                continue
        stripped = text.lstrip()
        is_json = path.lower().endswith((".json", ".jsonld")) or stripped.startswith(("{", "["))
        errors, warnings, checked = validate_text(text, is_json=is_json)
        if not checked and not errors and not warnings:
            print(f"{name}: no JSON-LD found")
            continue
        status = "FAIL" if errors else "OK"
        print(f"{name}: {status} ({checked} block{'s' if checked != 1 else ''}, {len(errors)} errors, {len(warnings)} warnings)")
        for line in errors:
            print(f"  error: {line}")
        for line in warnings:
            print(f"  warning: {line}")
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
