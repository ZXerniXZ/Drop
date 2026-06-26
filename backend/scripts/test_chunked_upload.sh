#!/usr/bin/env bash
# Test chunked upload against a running Drop backend.
# Usage: BASE_URL=http://localhost:8080 TOKEN=<jwt> ./test_chunked_upload.sh [size_mb]
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
TOKEN="${TOKEN:-}"
SIZE_MB="${1:-7}"

if [[ -z "$TOKEN" ]]; then
  echo "Set TOKEN to a valid Supabase JWT (export TOKEN=...)"
  exit 1
fi

CHUNK_SIZE=$((2 * 1024 * 1024))
TOTAL_SIZE=$((SIZE_MB * 1024 * 1024))
TOTAL_CHUNKS=$(( (TOTAL_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
TMP_FILE="$(mktemp /tmp/drop_upload_test.XXXXXX)"
trap 'rm -f "$TMP_FILE"' EXIT

dd if=/dev/zero of="$TMP_FILE" bs=1M count="$SIZE_MB" status=none

echo "Creating upload session (${SIZE_MB}MB, ${TOTAL_CHUNKS} chunks)..."
SESSION_RESP=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"filename\":\"test.m4a\",\"total_size\":${TOTAL_SIZE},\"total_chunks\":${TOTAL_CHUNKS},\"language\":\"italian\"}" \
  "$BASE_URL/upload-audio/sessions")

UPLOAD_ID=$(echo "$SESSION_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['upload_id'])")
echo "upload_id=$UPLOAD_ID"

for ((i=0; i<TOTAL_CHUNKS; i++)); do
  if (( i < TOTAL_CHUNKS - 1 )); then
    CHUNK_BYTES=$CHUNK_SIZE
  else
    CHUNK_BYTES=$((TOTAL_SIZE - CHUNK_SIZE * (TOTAL_CHUNKS - 1)))
  fi
  OFFSET=$((i * CHUNK_SIZE))
  echo "Uploading chunk $i ($CHUNK_BYTES bytes)..."
  dd if="$TMP_FILE" of=/dev/stdout bs=1 skip="$OFFSET" count="$CHUNK_BYTES" status=none | \
    curl -sf -X PUT \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @- \
      "$BASE_URL/upload-audio/sessions/${UPLOAD_ID}/chunks/${i}" >/dev/null
done

echo "Completing session..."
COMPLETE_RESP=$(curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/upload-audio/sessions/${UPLOAD_ID}/complete")

echo "$COMPLETE_RESP"
JOB_ID=$(echo "$COMPLETE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")
echo "job_id=$JOB_ID — poll GET /jobs/$JOB_ID for processing status"
