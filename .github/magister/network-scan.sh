#!/usr/bin/env bash
# Run magister-marketing's managed-runtime scan over this checkout's skills.
#
#   network-scan.sh <magister-marketing checkout>
#
# Run from the root of a marketingskills-magister checkout. Builds a temporary
# tree from the monorepo's scripts/ and gateway/app/ plus this checkout's
# skills/ and tools/ (the monorepo checkout is only read), runs
# scripts/inventory-agent-network-surfaces.py (the gate `make skills-publish`
# applies), and prints one line per surface that publishing would refuse.
# Exit 0: clean. Exit 1: violations. Exit 2: the scan could not run.
set -euo pipefail

MM="${1:?usage: network-scan.sh <magister-marketing checkout>}"
FORK="$(pwd)"
[ -f "$MM/scripts/inventory-agent-network-surfaces.py" ] || { echo "no inventory script in $MM" >&2; exit 2; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/gateway" "$T/magister-marketingskills"
cp -R "$MM/scripts" "$T/"
cp -R "$MM/gateway/app" "$T/gateway/"
cp -R "$FORK/skills" "$FORK/tools" "$T/magister-marketingskills/"

(cd "$T" && python3 scripts/inventory-agent-network-surfaces.py --fail-on none --output "$T/out.json" >/dev/null) || exit 2

OUT="$(python3 - "$T/out.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
for row in data["surfaces"]:
    src = row["source"]
    if not src.startswith("magister-marketingskills/") or "/evals/" in src:
        continue  # evals/ is never published
    src = src.removeprefix("magister-marketingskills/")
    if row["status"] in ("raw_network", "network_dependency_unresolved", "capability_binding_unresolved"):
        lines = ",".join(str(e.get("line")) for e in row.get("executable_raw_network", [])[:5])
        print(f"{src}: {row['status']}" + (f" (lines {lines})" if lines else ""))
    for key in ("unknown_magister_tools", "capability_mismatched_tools"):
        if row.get(key):
            print(f"{src}: {key}={','.join(row[key])}")
EOF
)" || exit 2
[ -z "$OUT" ] && exit 0
printf '%s\n' "$OUT"
exit 1
