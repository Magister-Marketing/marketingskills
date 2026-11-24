#!/usr/bin/env bash
# Run magister-marketing's managed-runtime scan over this checkout's skills.
#
#   network-scan.sh <magister-marketing checkout>
#
# Run from the root of a marketingskills-magister checkout. Copies skills/ and tools/ into
# the monorepo's magister-marketingskills/ path, runs
# scripts/inventory-agent-network-surfaces.py (the gate `make skills-publish`
# applies), and prints one line per surface that publishing would refuse.
# Exit 0: clean. Exit 1: violations. Exit 2: the scan could not run.
set -euo pipefail

MM="${1:?usage: network-scan.sh <magister-marketing checkout>}"
FORK="$(pwd)"
[ -f "$MM/scripts/inventory-agent-network-surfaces.py" ] || { echo "no inventory script in $MM" >&2; exit 2; }

rm -rf "$MM/magister-marketingskills"
mkdir -p "$MM/magister-marketingskills"
cp -R "$FORK/skills" "$FORK/tools" "$MM/magister-marketingskills/"

OUT="$(mktemp)"
(cd "$MM" && python3 scripts/inventory-agent-network-surfaces.py \
  --fail-on none --output "$OUT" >/dev/null) || exit 2

python3 - "$OUT" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
bad = []
for row in data["surfaces"]:
    src = row["source"]
    if not src.startswith("magister-marketingskills/") or "/evals/" in src:
        continue  # evals/ is never published
    src = src.removeprefix("magister-marketingskills/")
    if row["status"] in ("raw_network", "network_dependency_unresolved", "capability_binding_unresolved"):
        lines = ",".join(str(e.get("line")) for e in row.get("executable_raw_network", [])[:5])
        bad.append(f"{src}: {row['status']}" + (f" (lines {lines})" if lines else ""))
    for key in ("unknown_magister_tools", "capability_mismatched_tools"):
        if row.get(key):
            bad.append(f"{src}: {key}={','.join(row[key])}")
for line in bad:
    print(line)
sys.exit(1 if bad else 0)
EOF
