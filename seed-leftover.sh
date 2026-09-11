#!/usr/bin/env bash
# =============================================================================
# seed-leftover.sh -- DEMO HELPER
#
# Plants the artifacts an interrupted run would leave behind: an API, an
# application, and a throttling policy, all using the names the suite expects.
#
# Run it, then run the suite. B_PreClean will find and remove all three before
# creating its own, and the assertion count rises because PreClean has real
# work to verify.
#
#   ./seed-leftover.sh [--env <environment.json>]
#
# This exists only to demonstrate recovery. It is not part of the suite.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"
ENVFILE="APIM-4.5.0-Local-LeastPriv.postman_environment.json"
[[ "${1:-}" == "--env" ]] && ENVFILE="${2:-$ENVFILE}"

command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 2; }
[[ -f "$ENVFILE" ]] || { echo "ERROR: environment not found: $ENVFILE"; exit 2; }

get() { jq -r --arg k "$1" '.values[] | select(.key==$k) | .value' "$ENVFILE"; }
CP="https://$(get cp_host):$(get cp_port)"
USER=$(get admin_user); PASS=$(get admin_pass)
CID=$(get client_id);   CSEC=$(get client_secret)
API_NAME=$(get api_name); API_CTX=$(get api_context); API_VER=$(get api_version)
BACKEND=$(get backend_url)

[[ -n "$CID" && -n "$CSEC" ]] || { echo "ERROR: run ./bootstrap-client.sh first"; exit 2; }

tok() {
  curl -sk -m 20 -u "${CID}:${CSEC}" -X POST "${CP}/oauth2/token" \
    -d "grant_type=password&username=${USER}&password=${PASS}&scope=$1" | jq -r '.access_token // empty'
}
T_API=$(tok "apim:api_create apim:api_view")
T_APP=$(tok "apim:subscribe apim:app_manage")
T_TIER=$(tok "apim:tier_manage apim:tier_view")

echo "Planting leftovers on ${CP} as ${USER}"
echo

# 1. leftover API
code=$(curl -sk -m 30 -o /tmp/seed_api.json -w "%{http_code}" -X POST "${CP}/api/am/publisher/v4/apis" \
  -H "Authorization: Bearer ${T_API}" -H "Content-Type: application/json" -d "{
    \"name\":\"${API_NAME}\",\"context\":\"/${API_CTX}\",\"version\":\"${API_VER}\",
    \"description\":\"LEFTOVER: simulates an interrupted run\",
    \"type\":\"HTTP\",\"transport\":[\"https\"],\"policies\":[\"Unlimited\"],\"visibility\":\"PUBLIC\",
    \"endpointConfig\":{\"endpoint_type\":\"http\",
      \"production_endpoints\":{\"url\":\"${BACKEND}\"},\"sandbox_endpoints\":{\"url\":\"${BACKEND}\"}},
    \"operations\":[{\"target\":\"/get\",\"verb\":\"GET\",
      \"authType\":\"Application & Application User\",\"throttlingPolicy\":\"Unlimited\"}]}")
if [[ "$code" == "201" ]]; then
  echo "  API                 ${API_NAME}  (id $(jq -r .id /tmp/seed_api.json))"
else
  echo "  API                 not planted (HTTP $code) -- $(jq -r '.description // empty' /tmp/seed_api.json | head -c 70)"
fi

# 2. leftover application
code=$(curl -sk -m 20 -o /tmp/seed_app.json -w "%{http_code}" -X POST "${CP}/api/am/devportal/v3/applications" \
  -H "Authorization: Bearer ${T_APP}" -H "Content-Type: application/json" \
  -d '{"name":"SMOKE_TestApp","throttlingPolicy":"Unlimited","description":"LEFTOVER: simulates an interrupted run","tokenType":"OAUTH"}')
if [[ "$code" == "201" ]]; then
  echo "  Application         SMOKE_TestApp  (id $(jq -r .applicationId /tmp/seed_app.json))"
else
  echo "  Application         not planted (HTTP $code) -- $(jq -r '.description // empty' /tmp/seed_app.json | head -c 70)"
fi

# 3. leftover throttling policy
code=$(curl -sk -m 20 -o /tmp/seed_thr.json -w "%{http_code}" -X POST "${CP}/api/am/admin/v4/throttling/policies/advanced" \
  -H "Authorization: Bearer ${T_TIER}" -H "Content-Type: application/json" \
  -d '{"policyName":"SMOKE_Throttle","displayName":"SMOKE_Throttle","description":"LEFTOVER: simulates an interrupted run","conditionalGroups":[],"defaultLimit":{"type":"REQUESTCOUNTLIMIT","requestCount":{"timeUnit":"min","unitTime":1,"requestCount":1000}}}')
if [[ "$code" == "201" ]]; then
  echo "  Throttling policy   SMOKE_Throttle  (id $(jq -r .policyId /tmp/seed_thr.json))"
else
  echo "  Throttling policy   not planted (HTTP $code) -- $(jq -r '.description // empty' /tmp/seed_thr.json | head -c 70)"
fi

rm -f /tmp/seed_api.json /tmp/seed_app.json /tmp/seed_thr.json
echo
echo "Now run the suite. B_PreClean will remove all of the above before creating its own,"
echo "and the assertion total will be higher than a clean run because PreClean has work to verify."
