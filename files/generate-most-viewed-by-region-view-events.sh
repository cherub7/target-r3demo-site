#!/bin/bash
#
# Generate Target delivery API calls that simulate view traffic for pages/most-viewed-by-region.html
# (client bullseye, mbox item-view-mbox, params entity.id + recsRegion per viewItemOnce / trackEvent).
#
# Aligned with TopUsageByProfileAttributeAlgorithm:
#   - Each session contributes entity usage once per metric.
#   - getProductIdsCounter() sets count 1 per entity in the session regardless of repeat
#     clicks — the ranking score is "how many distinct sessions included this entity".
#   - Therefore each synthetic "view" MUST use a unique sessionId so the reducer
#     increments the per-(environment, attribute-group-key) entity counts as intended.
#     Reusing one session for multiple views of the same title would still count as 1.
#
# Per geo: 4 OTT titles (see CATALOG in most-viewed-by-region.html), with 40 / 30 / 20 / 10
# delivery calls respectively — clear ordering after UTU processes the traffic.
#
# Usage (from repo root):
#   bash target-r3demo-site/files/generate-most-viewed-by-region-view-events.sh
#
# Prerequisites (verify before relying on ER output):
#   - Target client bullseye; edge host matches most-viewed-by-region.html (targetGlobalSettings).
#   - Entity IDs exist in the Recommendations catalog for that client (entities-feed-ott.csv).
#   - Profile script maps mbox param recsRegion → user.recsAttributeRegion.
#   - Same payload shape as at.js trackEvent in pages/most-viewed-by-region.html: params { entity.id, recsRegion }.
#
# Requires: bash, curl, python3
set -euo pipefail

EDGE="https://bullseye.tt.omtrdc.net/rest/v1/delivery?client=bullseye&version=2.11.1"
CONTENT_TYPE="content-type: text/plain;charset=UTF-8"
PAGE_URL="https://cherub7.github.io/target-r3demo-site/pages/most-viewed-by-region.html"
SESSION_PREFIX="$(date +%Y%m%d%H%M%S)-$$-${RANDOM}"

build_track_event_body() {
  local entity_id=$1
  local region=$2
  ENTITY_ID="$entity_id" REGION="$region" PAGE_URL="$PAGE_URL" python3 - <<'PY'
import json, os, time, secrets
def rid():
    return secrets.token_hex(16)
e, r, url = os.environ["ENTITY_ID"], os.environ["REGION"], os.environ["PAGE_URL"]
body = {
    "requestId": rid(),
    "context": {
        "userAgent": "generate-most-viewed-by-region-view-events.sh",
        "timeOffsetInMinutes": 0,
        "channel": "web",
        "screen": {"width": 1280, "height": 800, "orientation": "landscape", "colorDepth": 24, "pixelRatio": 1},
        "window": {"width": 1200, "height": 800},
        "browser": {"host": "cherub7.github.io"},
        "address": {"url": url, "referringUrl": ""},
        "beacon": True,
    },
    "id": {"tntId": rid() + ".1_0"},
    "experienceCloud": {"analytics": {"logging": "server_side"}},
    "notifications": [{
        "id": rid(),
        "type": "display",
        "timestamp": int(time.time() * 1000),
        "parameters": {"entity.id": e, "recsRegion": r},
        "mbox": {"name": "item-view-mbox"},
    }],
}
print(json.dumps(body, separators=(",", ":")))
PY
}

send_view() {
  local entity_id=$1
  local region=$2
  local session=$3
  curl -sS --fail --connect-timeout 30 \
    "$EDGE&sessionId=${session}" \
    -H "$CONTENT_TYPE" \
    --data-raw "$(build_track_event_body "$entity_id" "$region")" >/dev/null
}

emit_batch() {
  local region=$1
  local prefix=$2
  local entity_id=$3
  local count=$4

  local i
  for ((i = 1; i <= count; i++)); do
    send_view "$entity_id" "$region" "${prefix}-${entity_id}-${i}-${SESSION_PREFIX}"
    echo -n "."
  done
  echo ""
}

echo ""
echo "Client: bullseye | Mbox: item-view-mbox"
echo ""

# ── US
echo "--- Region US (40 / 30 / 20 / 10) ---"
emit_batch US us ott-001 40   # The Last Frontier
emit_batch US us ott-002 30   # Midnight Signal
emit_batch US us ott-003 20   # Valley of Echoes
emit_batch US us ott-004 10   # Neon Drive

# ── INDIA
echo ""
echo "--- Region INDIA (40 / 30 / 20 / 10) ---"
emit_batch INDIA in ott-012 40   # High Stakes
emit_batch INDIA in ott-015 30   # The Loop
emit_batch INDIA in ott-011 20   # Grid Lock
emit_batch INDIA in ott-020 10   # Final Run

# ── UK
echo ""
echo "--- Region UK (40 / 30 / 20 / 10) ---"
emit_batch UK uk ott-007 40   # The Quiet Room
emit_batch UK uk ott-008 30   # Deep Space
emit_batch UK uk ott-009 20   # Shadow Lane
emit_batch UK uk ott-006 10   # Code Black

echo ""
echo "Done."
