#!/usr/bin/env bash
set -euo pipefail

: "${DASHBOARD_URL:=https://plansolo.ru}"
: "${NAS_SYNC_TOKEN:?NAS_SYNC_TOKEN is required}"
: "${NAS_SYNC_AGENT_ID:=home-assistant-nas}"
: "${NAS_SYNC_ROOT:=/share/NAS}"
: "${NAS_SYNC_CATEGORY:=gallery}"
: "${NAS_SYNC_BATCH:=100}"

api="${DASHBOARD_URL%/}/api/sync/nas/manifest"
complete_api="${DASHBOARD_URL%/}/api/sync/nas/complete"
cursor=""
total=0
manifest=""
completion=""
trap 'rm -f "$manifest" "$completion"' EXIT

mkdir -p "$NAS_SYNC_ROOT"
printf '{"synced":0,"updatedAt":"%s"}\n' "$(date -u +%FT%TZ)" > /data/state.json 2>/dev/null || true

while :; do
  url="$api?category=$(printf '%s' "$NAS_SYNC_CATEGORY" | jq -sRr @uri)&limit=$NAS_SYNC_BATCH"
  if [[ -n "$cursor" ]]; then
    url+="&cursor=$(printf '%s' "$cursor" | jq -sRr @uri)"
  fi

  manifest="$(mktemp)"
  curl --fail --silent --show-error \
    -H "Authorization: Bearer $NAS_SYNC_TOKEN" \
    -H "X-NAS-Agent-Id: $NAS_SYNC_AGENT_ID" \
    "$url" >"$manifest"

  count="$(jq '.items | length' "$manifest")"
  [[ "$count" -gt 0 ]] || break
  completion="$(mktemp)"
  jq -c '{items: [.items[] | {fileId, sizeBytes, contentHash}]}' "$manifest" >"$completion"

  while IFS=$'\t' read -r file_id logical_path size_bytes content_hash download_url; do
    [[ -n "$file_id" && -n "$logical_path" && -n "$download_url" ]] || {
      printf 'invalid manifest item; refusing to continue\n' >&2
      exit 1
    }
    destination="$NAS_SYNC_ROOT/$logical_path"
    mkdir -p "$(dirname "$destination")"
    temporary="${destination}.nas-sync.tmp.$$"
    rm -f "$temporary"
    curl --fail --silent --show-error --location "$download_url" --output "$temporary"
    actual_size="$(stat -c '%s' "$temporary")"
    [[ "$actual_size" == "$size_bytes" ]] || {
      rm -f "$temporary"
      printf 'size mismatch for %s\n' "$logical_path" >&2
      exit 1
    }
    if [[ -n "$content_hash" ]]; then
      actual_hash="$(sha256sum "$temporary" | cut -d' ' -f1)"
      [[ "$actual_hash" == "$content_hash" ]] || {
        rm -f "$temporary"
        printf 'hash mismatch for %s\n' "$logical_path" >&2
        exit 1
      }
    fi
    mv -f "$temporary" "$destination"
    total=$((total + 1))
    printf '{"synced":%s,"updatedAt":"%s"}\n' "$total" "$(date -u +%FT%TZ)" > /data/state.json 2>/dev/null || true
    printf 'synced %s files\n' "$total"
  done < <(jq -r '.items[] | [.fileId, .logicalPath, .sizeBytes, (.contentHash // ""), .downloadUrl] | @tsv' "$manifest")

  response="$(curl --fail --silent --show-error -X POST \
    -H "Authorization: Bearer $NAS_SYNC_TOKEN" \
    -H "X-NAS-Agent-Id: $NAS_SYNC_AGENT_ID" \
    -H 'Content-Type: application/json' \
    --data-binary "@$completion" "$complete_api")"
  [[ "$(jq -r '.complete // false' <<<"$response")" == true ]] || {
    printf 'Dashboard rejected completion: %s\n' "$response" >&2
    exit 1
  }

  cursor="$(jq -r '.nextCursor // empty' "$manifest")"
  [[ -n "$cursor" ]] || break
done
