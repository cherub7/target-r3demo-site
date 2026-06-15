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
      "execute": {
        "mboxes": [{
          "name": "profile-attributes-demo",
          "index": 1,
          "parameters": {
            "entity.id": "'"${entity_id}"'",
            "website": "US"
          },
          "profileParameters": {}
        }]
      }
    }' > /dev/null
  echo -n "."
}

emit_batch() {
  local entity_id=$1 count=$2
  echo -n "${entity_id} (${count}x): "
  for i in $(seq 1 $count); do send_view "$entity_id" "$i"; done
  echo ""
}

echo "--- website=US ---"
emit_batch 900001-01-IN 5
emit_batch 900002-01-IN 10
emit_batch 900003-01-IN 20
emit_batch 900004-01-IN 30
emit_batch 900005-01-IN 40

# Test out of catalog items
# emit_batch r3demo-001 1
# emit_batch r3demo-002 2
# emit_batch r3demo-003 3

# test invalid entity id
# emit_batch r3demo-999 4
echo "Done."
