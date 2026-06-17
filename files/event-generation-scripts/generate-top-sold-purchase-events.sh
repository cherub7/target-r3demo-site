#!/bin/bash
#
# Generate Target delivery API calls that simulate purchase traffic for pages/top-sold.html
# (client bullseye, mbox item-purchase-mbox, params orderId + orderTotal + productPurchasedId + recsRegion).
#
# Aligned with TopSellersAlgorithm:
#   - Each unique orderId contributes one purchase count for the entity.
#   - getProductIdsCounter() increments the per-(environment, attribute-group-key) entity count
#     once per orderId — NOT once per session — so every call here uses a unique orderId.
#   - A unique sessionId per call also avoids any session-level deduplication.
#
# Per region: 4 book titles with 40 / 30 / 20 / 10 purchase calls each → 100 events per region,
# 300 total. Expected ranking after UTU processing:
#   US    : Atomic Habits > Gone Girl > The Great Gatsby > The Catcher in the Rye
#   India : Five Point Someone > The White Tiger > The God of Small Things > Shantaram
#   UK    : Harry Potter > The Hobbit > Pride and Prejudice > Normal People
#
# Usage (from repo root):
#   bash files/event-generation-scripts/generate-top-sold-purchase-events.sh
#
# Prerequisites:
#   - entities-feed-books.csv uploaded to Recommendations catalog on client bullseye.
#   - Profile script  recsAttributeRegion : return mbox.param("recsRegion");
#   - Activities live:
#       r3demo-top-sold-recs              (Top Sold — global)
#       r3demo-top-sold-by-region-recs    (Top Sold — by Profile Attribute: recsAttributeRegion)
#
# Requires: bash, curl, python3
set -euo pipefail

EDGE="https://bullseye.tt.omtrdc.net/rest/v1/delivery?client=bullseye&version=2.11.1"
CONTENT_TYPE="content-type: text/plain;charset=UTF-8"
PAGE_URL="https://cherub7.github.io/target-r3demo-site/pages/top-sold.html"
SESSION_PREFIX="$(date +%Y%m%d%H%M%S)-$$-${RANDOM}"

# ── Build delivery request body for one purchase event ─────────────────────────
build_purchase_body() {
  local entity_id=$1
  local region=$2
  local order_total=$3
  ENTITY_ID="$entity_id" REGION="$region" ORDER_TOTAL="$order_total" PAGE_URL="$PAGE_URL" python3 - <<'PY'
import json, os, time, secrets

def rid():
    return secrets.token_hex(16)

e      = os.environ["ENTITY_ID"]
r      = os.environ["REGION"]
total  = os.environ["ORDER_TOTAL"]
url    = os.environ["PAGE_URL"]

# Unique orderId per call — timestamp ms + 8 random hex chars
order_id = "ord-" + str(int(time.time() * 1000)) + "-" + secrets.token_hex(4)

body = {
    "requestId": rid(),
    "context": {
        "userAgent": "generate-top-sold-purchase-events.sh",
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
        "parameters": {"recsRegion": r},
        "order": {
            "id":                  order_id,
            "total":               str(float(total)),
            "purchasedProductIds": [e],
        },
        "mbox": {"name": "item-purchase-mbox"},
    }],
}
print(json.dumps(body, separators=(",", ":")))
PY
}

# ── Send one purchase event ────────────────────────────────────────────────────
send_purchase() {
  local entity_id=$1
  local region=$2
  local order_total=$3
  local session=$4
  curl -sS --fail --connect-timeout 30 \
    "$EDGE&sessionId=${session}" \
    -H "$CONTENT_TYPE" \
    --data-raw "$(build_purchase_body "$entity_id" "$region" "$order_total")" >/dev/null
}

# ── Emit N purchase events for one book ───────────────────────────────────────
emit_batch() {
  local region=$1
  local prefix=$2
  local entity_id=$3
  local order_total=$4
  local count=$5
  local book_name=$6

  printf "  %-44s (%3d): " "$book_name" "$count"
  local i
  for ((i = 1; i <= count; i++)); do
    send_purchase "$entity_id" "$region" "$order_total" "${prefix}-${entity_id}-${i}-${SESSION_PREFIX}"
    echo -n "."
  done
  echo " done"
}

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "Client: bullseye | Mbox: item-purchase-mbox"
echo ""

# ── US ────────────────────────────────────────────────────────────────────────
echo "--- Region US (40 / 30 / 20 / 10) ---"
emit_batch US us book-004 16.99 40 "Atomic Habits"
emit_batch US us book-005 14.99 30 "Gone Girl"
emit_batch US us book-001 12.99 20 "The Great Gatsby"
emit_batch US us book-003 11.99 10 "The Catcher in the Rye"

# ── INDIA ─────────────────────────────────────────────────────────────────────
echo ""
echo "--- Region INDIA (40 / 30 / 20 / 10) ---"
emit_batch INDIA in book-019 10.99 40 "Five Point Someone"
emit_batch INDIA in book-016 12.99 30 "The White Tiger"
emit_batch INDIA in book-015 13.99 20 "The God of Small Things"
emit_batch INDIA in book-020 17.99 10 "Shantaram"

# ── UK ────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Region UK (40 / 30 / 20 / 10) ---"
emit_batch UK uk book-008 14.99 40 "Harry Potter and the Philosopher's Stone"
emit_batch UK uk book-010 12.99 30 "The Hobbit"
emit_batch UK uk book-009  9.99 20 "Pride and Prejudice"
emit_batch UK uk book-012 14.99 10 "Normal People"

echo ""
echo "Done. 300 purchase events sent (100 per region)."
