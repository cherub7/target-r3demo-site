#!/bin/bash
EDGE="https://bullseye.tt.omtrdc.net/rest/v1/delivery?client=bullseye"
SESSION_PREFIX="$(date +%Y%m%d%H%M%S)-$$"

send_view() {
  local entity_id=$1
  local session="${SESSION_PREFIX}-${entity_id}-${2}"
  curl -s --request POST "${EDGE}&sessionId=${session}" \
    -H "content-type: text/plain;charset=UTF-8" \
    --data-raw '{
      "requestId": "'"$(uuidgen)"'",
      "context": {"channel": "web"},
      "notifications": [{
        "id": "'"$(uuidgen)"'",
        "type": "display",
        "timestamp": '"$(date +%s000)"',
        "parameters": {"entity.id": "'"${entity_id}"'", "website": "IN"},
        "mbox": {"name": "profile-attributes-demo"}
      }]
    }' > /dev/null
  echo -n "."
}

emit_batch() {
  local entity_id=$1 count=$2
  echo -n "${entity_id} (${count}x): "
  for i in $(seq 1 $count); do send_view "$entity_id" "$i"; done
  echo ""
}

echo "--- website=IN ---"
emit_batch 900001-01-IN 40
emit_batch 900002-01-IN 30
emit_batch 900003-01-IN 20
emit_batch 900004-01-IN 10
emit_batch 900005-01-IN 5
echo "Done."
