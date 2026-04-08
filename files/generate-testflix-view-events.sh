#!/bin/bash
#
# Generate Target delivery API calls that simulate view traffic for pages/testflix.html
# (client emeastage3, mbox item-view-mbox, params entity.id + recsRegion per viewItemOnce / trackEvent).
#
# Aligned with TopUsageByProfileAttributeAlgorithm (see work-notes deep analysis):
#   - Input is session files; each session contributes entity usage once per metric.
#   - getProductIdsCounter() sets count 1 per entity in the session regardless of repeat
#     clicks — the ranking score is "how many distinct sessions included this entity".
#   - Therefore each synthetic "view" MUST use a unique sessionId so the reducer
#     increments the per-(environment, attribute-group-key) entity counts as intended.
#     Reusing one session for multiple views of the same title would still count as 1.
#
# Per geo: 4 Testflix titles (see CATALOG in testflix.html), with 40 / 30 / 20 / 10
# delivery calls respectively — clear ordering after UTU processes the traffic.
#
# Usage (from repo root):
#   bash target-r3demo-site/files/generate-testflix-view-events.sh
#
# Prerequisites (verify before relying on ER output):
#   - Target client emeastage3; edge host matches testflix.html (targetGlobalSettings).
#   - Entity IDs exist in the Recommendations catalog for that client (entities-feed-testflix.csv).
#   - Profile script maps mbox param recsRegion → user.recsAttributeRegion (or your algo's attribute).
#   - Same payload shape as at.js trackEvent in pages/testflix.html: params { entity.id, recsRegion }.
#     The categoryId column in emit_batch is comment/catalog metadata only.
#
# Requires: bash, curl, python3
set -euo pipefail

# Matches at.js 2.11+ delivery POST: version query, text/plain body, trackEvent => notifications (display).
EDGE="https://emeastage3.tt-stage1.omtrdc.net/rest/v1/delivery?client=emeastage3&version=2.11.1"
CONTENT_TYPE="content-type: text/plain;charset=UTF-8"
PAGE_URL="https://cherub7.github.io/target-r3demo-site/pages/testflix.html"
# Unique per script run so sessionIds never collide across reruns.
SESSION_PREFIX="$(date +%Y%m%d%H%M%S)-$$-${RANDOM}"

# Mirrors adobe.target.trackEvent({ mbox, params: { 'entity.id', 'recsRegion' } }) -> delivery notifications.
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
        "userAgent": "generate-testflix-view-events.sh",
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
  # $2: category from CATALOG in emit_batch (not sent; testflix viewItemOnce uses entity.id + recsRegion only)
  local region=$3
  local session=$4
  # --fail: non-2xx HTTP fails the script (surface auth/edge issues immediately)
  curl -sS --fail --connect-timeout 30 \
    "$EDGE&sessionId=${session}" \
    -H "$CONTENT_TYPE" \
    --data-raw "$(build_track_event_body "$entity_id" "$region")" >/dev/null
}

emit_batch() {
  local region=$1
  local prefix=$2
  local entity_id=$3
  local category_id=$4
  local count=$5

  local i
  for ((i = 1; i <= count; i++)); do
    send_view "$entity_id" "$category_id" "$region" "${prefix}-${entity_id}-${i}-${SESSION_PREFIX}"
    echo -n "."
  done
  echo ""
}

# ── US — Hollywood blockbusters / streaming hits
echo ""
echo "Client: emeastage3 | Mbox: item-view-mbox"
echo ""
echo "--- Region US (40 / 30 / 20 / 10) ---"
emit_batch US    us   testflix-019 cat-action 40   # Avengers: Endgame
emit_batch US    us   testflix-017 cat-sci-fi 30   # Avatar: The Way of Water
emit_batch US    us   testflix-005 cat-sci-fi 20   # Stranger Things
emit_batch US    us   testflix-001 cat-sci-fi 10   # Dune: Part Two

# ── INDIA — Bollywood / Indian theatrical & genre hits
echo ""
echo "--- Region INDIA (40 / 30 / 20 / 10) ---"
emit_batch INDIA in   testflix-012 cat-action 40     # RRR
emit_batch INDIA in   testflix-015 cat-thriller 30   # The Family Man
emit_batch INDIA in   testflix-011 cat-action 20     # Pathaan
emit_batch INDIA in   testflix-020 cat-sci-fi 10     # Kalki 2898 AD

# ── UK — British series / co-productions
echo ""
echo "--- Region UK (40 / 30 / 20 / 10) ---"
emit_batch UK     uk   testflix-007 cat-crime   40   # Peaky Blinders
emit_batch UK     uk   testflix-008 cat-crime   30   # Top Boy
emit_batch UK     uk   testflix-009 cat-mystery 20   # Sherlock
emit_batch UK     uk   testflix-006 cat-drama   10   # The Crown

echo ""
echo "Done."
