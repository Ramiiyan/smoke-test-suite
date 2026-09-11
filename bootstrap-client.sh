#!/usr/bin/env bash
# =============================================================================
# bootstrap-client.sh -- ONE-TIME admin setup for the smoke test suite
#
# Registers the OAuth client the suite uses and writes client_id/client_secret
# into a Postman environment file. Run once, by an admin, before the suite is
# first pointed at a deployment.
#
# After this, the smoke suite runs as a least-privilege user and never creates
# or deletes an OAuth client -- nothing is provisioned on a live system during
# a maintenance window.
#
#   ./bootstrap-client.sh --host localhost --port 9443 \
#       --env APIM-4.5.0-Local-LeastPriv.postman_environment.json
#
# The admin USERNAME and PASSWORD are both prompted for -- deployments do not
# share an admin account, and neither is taken from a file or written to one.
# Only client_id/client_secret are persisted.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"

HOST=""; PORT=""; ADMIN_USER=""; ENVFILE=""; CLIENT_OWNER=""
DCR_VERSION="v0.17"

usage() {
  cat <<USAGE
usage: $0 --host <h> --port <p> --env <environment.json>
          [--admin-user <u>] [--owner <username>] [--dcr-version v0.17]

  --host         Control Plane host (e.g. localhost)
  --port         Control Plane port (e.g. 9443)
  --env          Postman environment JSON to write client_id/client_secret into
  --admin-user   Admin username used to register the client. PROMPTED if not
                 given -- pass it only for unattended use. The password is
                 always prompted and is never accepted as a flag.
  --owner        Owner recorded on the client. Defaults to --admin-user.
                 The clientName is derived as smoke_client_<owner>, matching
                 what the collection used to register, so an existing client is
                 returned rather than a duplicate created.
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --admin-user) ADMIN_USER="${2:-}"; shift 2 ;;
    --env) ENVFILE="${2:-}"; shift 2 ;;
    --owner) CLIENT_OWNER="${2:-}"; shift 2 ;;
    --dcr-version) DCR_VERSION="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1"; usage ;;
  esac
done

[[ -n "$HOST" && -n "$PORT" && -n "$ENVFILE" ]] || usage
command -v jq >/dev/null || { echo "ERROR: jq is required but not installed (brew install jq)"; exit 2; }
[[ -f "$ENVFILE" ]] || { echo "ERROR: environment file not found: $ENVFILE"; exit 2; }
jq -e . "$ENVFILE" >/dev/null 2>&1 || { echo "ERROR: $ENVFILE is not valid JSON"; exit 2; }

# Admin identity is asked for, not configured: each deployment has its own admin
# username, and it is NOT the least-privilege account in admin_user that the
# suite itself runs as.
if [[ -z "$ADMIN_USER" ]]; then
  printf "Admin username (for client registration): " >&2
  read -r ADMIN_USER
fi
[[ -n "$ADMIN_USER" ]] || { echo "ERROR: admin username is required"; exit 2; }

[[ -n "$CLIENT_OWNER" ]] || CLIENT_OWNER="$ADMIN_USER"
CLIENT_NAME="smoke_client_${CLIENT_OWNER}"

# Password is read into a shell variable only. Never echoed, never persisted.
printf "Password for %s: " "$ADMIN_USER" >&2
read -rs ADMIN_PASS
echo >&2
[[ -n "$ADMIN_PASS" ]] || { echo "ERROR: empty password"; exit 2; }

CP="https://${HOST}:${PORT}"
echo "-- registering '${CLIENT_NAME}' (owner ${CLIENT_OWNER}) at ${CP}"

BODY=$(jq -nc --arg cb "https://${HOST}/callback" --arg cn "$CLIENT_NAME" --arg ow "$CLIENT_OWNER" \
  '{callbackUrl:$cb, clientName:$cn, owner:$ow,
    grantType:"password refresh_token client_credentials", saasApp:true}')

RESP=$(mktemp); trap 'rm -f "$RESP"' EXIT
CODE=$(curl -sk -m 30 -o "$RESP" -w "%{http_code}" \
  -X POST "${CP}/client-registration/${DCR_VERSION}/register" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  --data-binary "$BODY")
unset ADMIN_PASS

if [[ "$CODE" != "200" && "$CODE" != "201" ]]; then
  echo "ERROR: DCR failed with HTTP $CODE"
  echo "  $(head -c 400 "$RESP")"
  case "$CODE" in
    401) echo "  -> check the admin username/password" ;;
    403) echo "  -> that user may not own '${CLIENT_NAME}'. Another user already"
         echo "     registered this clientName; pass --owner to scope it, or use that user." ;;
  esac
  exit 1
fi

CID=$(jq -r '.clientId // empty' "$RESP")
CSEC=$(jq -r '.clientSecret // empty' "$RESP")
[[ -n "$CID" && -n "$CSEC" ]] || { echo "ERROR: response had no clientId/clientSecret"; head -c 300 "$RESP"; exit 1; }

# One-time backup before we ever modify the environment file.
[[ -f "${ENVFILE}.orig" ]] || { cp "$ENVFILE" "${ENVFILE}.orig"; echo "-- backup: ${ENVFILE}.orig"; }

# Update in place if the key exists, append if it doesn't.
TMP=$(mktemp)
jq --arg cid "$CID" --arg csec "$CSEC" '
  def upsert($k; $v):
    if any(.values[]?; .key == $k)
    then .values |= map(if .key == $k then .value = $v else . end)
    else .values += [{key: $k, value: $v, type: "default", enabled: true}]
    end;
  upsert("client_id"; $cid) | upsert("client_secret"; $csec)
' "$ENVFILE" > "$TMP" || { echo "ERROR: jq update failed"; rm -f "$TMP"; exit 1; }
jq -e . "$TMP" >/dev/null 2>&1 || { echo "ERROR: produced invalid JSON, not writing"; rm -f "$TMP"; exit 1; }
mv "$TMP" "$ENVFILE"

echo "-- wrote client_id / client_secret to ${ENVFILE}"
echo "   client_name : ${CLIENT_NAME}"
echo "   client_id   : ${CID}"
echo "   client_secret: (written to the env file, not shown)"
echo
echo "DCR is get-or-create: re-running this returns the same client, so it is safe to repeat."
echo "The suite can now run as a least-privilege user without creating or deleting a client."
