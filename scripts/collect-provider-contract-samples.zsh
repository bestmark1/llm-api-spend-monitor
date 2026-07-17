#!/bin/zsh

set -euo pipefail

umask 077

for dependency in curl jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    print -u2 "Missing required command: $dependency"
    exit 1
  fi
done

readonly output_root="${OUTPUT_ROOT:-.local/provider-contract-validation}"
readonly start_utc="${START_UTC:-$(date -u -v-1d '+%Y-%m-%dT00:00:00Z')}"
readonly end_utc="${END_UTC:-$(date -u '+%Y-%m-%dT00:00:00Z')}"
readonly start_unix="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$start_utc" '+%s')"
readonly end_unix="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$end_utc" '+%s')"
readonly page_cap=20

mkdir -p "$output_root/openai" "$output_root/anthropic" "$output_root/deepseek"

if [[ -z "${OPENAI_ADMIN_KEY:-}" ]]; then
  read -r -s 'OPENAI_ADMIN_KEY?OpenAI Organization Admin API key: '
  print
fi

if [[ -z "${ANTHROPIC_ADMIN_KEY:-}" ]]; then
  read -r -s 'ANTHROPIC_ADMIN_KEY?Anthropic Console Admin API key: '
  print
fi

if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  read -r -s 'DEEPSEEK_API_KEY?DeepSeek standard API key: '
  print
fi

cleanup() {
  unset OPENAI_ADMIN_KEY ANTHROPIC_ADMIN_KEY DEEPSEEK_API_KEY
}
trap cleanup EXIT INT TERM

openai_request() {
  print -r -- 'header = "Authorization: Bearer '"$OPENAI_ADMIN_KEY"'"'
  print -r -- 'header = "Content-Type: application/json"'
}

anthropic_request() {
  print -r -- 'header = "anthropic-version: 2023-06-01"'
  print -r -- 'header = "x-api-key: '"$ANTHROPIC_ADMIN_KEY"'"'
}

deepseek_request() {
  print -r -- 'header = "Accept: application/json"'
  print -r -- 'header = "Authorization: Bearer '"$DEEPSEEK_API_KEY"'"'
}

sanitize() {
  local input="$1"
  local output="$2"

  jq 'walk(
    if type == "object" then
      with_entries(
        if (.key | test("^(organization|workspace|project|user|api_key|account|service_account)(_id|_ids|_name|_email)?$")) and .value != null then
          .value = (if (.value | type) == "array" then ["REDACTED"] else "REDACTED" end)
        elif .key == "next_page" and .value != null then
          .value = "REDACTED_PAGE_TOKEN"
        else . end
      )
    else . end
  )' "$input" > "$output"
}

fetch_pages() {
  local provider="$1"
  local report="$2"
  local auth_function="$3"
  local url="$4"
  shift 4

  local -a query_arguments=("$@")
  local page=""
  local page_number=1

  while (( page_number <= page_cap )); do
    local raw_path="$output_root/$provider/$report-page-$page_number.raw.json"
    local sanitized_path="$output_root/$provider/$report-page-$page_number.sanitized.json"
    local -a page_arguments=("${query_arguments[@]}")

    if [[ -n "$page" ]]; then
      page_arguments+=(--data-urlencode "page=$page")
    fi

    "$auth_function" | curl \
      --config - \
      --fail-with-body \
      --silent \
      --show-error \
      --get \
      "$url" \
      "${page_arguments[@]}" \
      > "$raw_path"

    jq empty "$raw_path"
    sanitize "$raw_path" "$sanitized_path"

    local has_more="$(jq -r '.has_more // false' "$raw_path")"
    local next_page="$(jq -r '.next_page // empty' "$raw_path")"

    if [[ "$has_more" != "true" ]]; then
      return
    fi

    if [[ -z "$next_page" ]]; then
      print -u2 "$provider/$report says has_more=true without next_page"
      exit 1
    fi

    page="$next_page"
    (( page_number += 1 ))
  done

  print -u2 "$provider/$report exceeded the safety cap of $page_cap pages"
  exit 1
}

print "Collecting the closed UTC interval $start_utc to $end_utc"

fetch_pages \
  openai costs openai_request \
  'https://api.openai.com/v1/organization/costs' \
  --data-urlencode "start_time=$start_unix" \
  --data-urlencode "end_time=$end_unix" \
  --data-urlencode 'bucket_width=1d' \
  --data-urlencode 'limit=1'

fetch_pages \
  openai usage openai_request \
  'https://api.openai.com/v1/organization/usage/completions' \
  --data-urlencode "start_time=$start_unix" \
  --data-urlencode "end_time=$end_unix" \
  --data-urlencode 'bucket_width=1d' \
  --data-urlencode 'group_by=model' \
  --data-urlencode 'limit=1'

fetch_pages \
  anthropic costs anthropic_request \
  'https://api.anthropic.com/v1/organizations/cost_report' \
  --data-urlencode "starting_at=$start_utc" \
  --data-urlencode "ending_at=$end_utc" \
  --data-urlencode 'bucket_width=1d' \
  --data-urlencode 'limit=1'

fetch_pages \
  anthropic usage anthropic_request \
  'https://api.anthropic.com/v1/organizations/usage_report/messages' \
  --data-urlencode "starting_at=$start_utc" \
  --data-urlencode "ending_at=$end_utc" \
  --data-urlencode 'bucket_width=1d' \
  --data-urlencode 'group_by[]=model' \
  --data-urlencode 'limit=1'

fetch_pages \
  deepseek balance deepseek_request \
  'https://api.deepseek.com/user/balance'

print
print "Capture complete: $output_root"
print 'Review only *.sanitized.json files before sharing or copying them into fixtures.'
