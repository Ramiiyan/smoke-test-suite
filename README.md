# WSO2 API Manager 4.5.0 — Operational Smoke Suite

A Postman/Newman suite that verifies a **WSO2 API Manager 4.5.0 distributed deployment**
is healthy and functional. It is designed to be run **immediately before and immediately
after any maintenance activity** — keep both reports and compare them, so a regression is
caught within minutes rather than discovered by a customer.

The suite exercises a complete API lifecycle against a live deployment — create, publish,
deploy, subscribe, invoke, revoke, and tear down — and removes everything it creates.

| | |
|---|---|
| Checks per run | **90 assertions across 67 requests** |
| Typical runtime | **13–16 seconds** |
| Runs as | A least-privilege user (no admin rights at runtime) |
| Leaves behind | Nothing — all artifacts are deleted by the suite |

---

## 1. What the suite covers

| Folder | Requests | What it verifies |
|---|---:|---|
| **1_Auth** | 6 | OAuth2 password-grant tokens are issued, and each requested scope is actually granted |
| **2_PreClean** | 10 | Removes artifacts left behind by a previous interrupted run, so a failed run cannot block the next one |
| **3_Publisher** | 10 | Create an API, read it back, update it, create and deploy a revision to the gateway, publish it; list APIs, operation policies and throttling tiers |
| **4_Documents** | 5 | Full API document lifecycle: create, read, update, delete, confirm removal |
| **5_DevPortal** | 10 | Application creation, API discovery, subscription, key generation, and the listing endpoints |
| **6_Gateway** | 4 | Obtain an access token, invoke the API through the gateway, revoke the token, confirm the gateway then rejects it |
| **7_Policy** | 12 | Throttling policy create → **attach to API** → verify → detach → delete; operation policy create → verify → delete |
| **8_Teardown** | 10 | Removes the subscription, application, revision and API, then confirms each is gone |

### Full collection tree

Folders and requests are numbered so a failure can be located quickly. Newman
reports failures as `inside "7_Policy / 7.1_Throttling / 7.1.1 Create Throttling Policy"`,
which maps directly onto the inline log.

```
1_Auth/
    1.1 Token -api_create scope
    1.2 Token -api_view scope
    1.3 Token -api_publish scope
    1.4 Token -api_subscribe scope
    1.5 Token -tier scope
    1.6 Token -policy scope
2_PreClean/
    2.1 Find Leftover App
    2.2 Delete Leftover APP
    2.3 Find Leftover API
    2.4 Get Leftover Revisions
    2.5 Undeploy Leftover Revision
    2.6 Delete Leftover Revision
    2.7 Demote Leftover API
    2.8 Delete Leftover API
    2.9 Find Leftover Throttling Policy
    2.10 Delete Leftover Throttling Policy
3_Publisher/
    3.1 Create API
    3.2 Get api
    3.3 List APIs (Publisher)
    3.4 List Operation Policies
    3.5 List Subscription Throttling Policies
    3.6 Update API
    3.7 Create Revision
    3.8 Deploy Revision
    3.9 Verify Deployment
    3.10 Change Lifecycle to Publish
4_Documents/
    4.1 Create Document
    4.2 Get Document
    4.3 Update Document
    4.4 Delete Document
    4.5 Verify Document Deleted
5_DevPortal/
    5.1 Create Application
    5.2 List Applications
    5.3 Get Application
    5.4 Get API in DevPortal
    5.5 List APIs (DevPortal)
    5.6 Subscribe to API
    5.7 List Subscriptions
    5.8 Get Application details
    5.9 Generate Application Keys
    5.10 Get OAuth Keys
6_Gateway/
    6.1 Generate Access Token
    6.2 Invoke API
    6.3 Revoke Access Token
    6.4 Invoke with Revoked Token
7_Policy/
    7.1_Throttling/
        7.1.1 Create Throttling Policy
        7.1.2 Get API for Policy Attach
        7.1.3 Attach Throttling Policy to API
        7.1.4 Verify Policy Attached
        7.1.5 Detach Throttling Policy
        7.1.6 Get Throttling Policy
        7.1.7 Delete Throttling Policy
        7.1.8 Verify Throttling Policy Deleted
    7.2_OperationPolicy/
        7.2.1 Create Operation Policy
        7.2.2 Get Operation Policy
        7.2.3 Delete Operation Policy
        7.2.4 Verify Operation Policy Deleted
8_Teardown/
    8.1 Refresh Delete Token
    8.2 Remove Subscription
    8.3 Remove Application
    8.4 Undeploy Revision
    8.5 Delete Revision
    8.6 Demote to Created
    8.7 Delete API
    8.8 Verify Subscription Deleted
    8.9 Verify Application Deleted
    8.10 Verify API Deleted
```

### What it deliberately does **not** cover

- **Throttling enforcement (HTTP 429).** The suite verifies a policy can be *attached* to an
  API and that the association persists. It does **not** prove the limit is enforced —
  enforcement requires a revision redeploy and sustained traffic, which would take minutes.
  Do not read "Policy attached to API" as "rate limiting works".
- **High availability / failover.** The suite checks one gateway environment; it does not
  test failover between gateway nodes.
- **Performance.** This is a functional smoke suite, not a load test.

---

## 2. Prerequisites

### On the machine running the suite

| Tool | Version used | Purpose |
|---|---|---|
| **Newman** | 6.2.2 | Runs the collection. `npm install -g newman` |
| **Node.js** | v26.5.0 | Required by Newman |
| **jq** | 1.7.1 | Used by `bootstrap-client.sh`. `brew install jq` |
| **curl** | any | Used by the setup script |

### On the target deployment

- WSO2 API Manager **4.5.0** distributed: Control Plane, Universal Gateway, Traffic Manager
- All three nodes running and reachable
- A gateway environment registered (default name `Default`)
- A user account for the suite to run as, with the role described in section 6
- Network access from the gateway to the backend used by the test API
  (default `https://httpbin.org` — change `backend_url` if the deployment is air-gapped)

### Default ports

| Node | Port |
|---|---|
| Control Plane (Publisher / DevPortal / Admin APIs) | 9443 |
| Universal Gateway (HTTPS) | 8244 |
| Traffic Manager | 9445 |

---

## 3. Repository structure

```
MET_OFFICE/
├── README.md                                        this file
├── MET_OFFICE.postman_collection.json               the suite (67 requests)
├── DEMO-broken.postman_collection.json              deliberately broken copy, for demos
├── APIM-4.5.0-Local.postman_environment.json        environment template (fill in locally)
│
├── bootstrap-client.sh                              ONE-TIME admin setup (section 4)
├── seed-leftover.sh                                 demo helper: plants leftovers to show recovery
│
├── policy-files/                                    REQUIRED at runtime
│   ├── policy-spec.json                             uploaded by the operation-policy test
│   └── policy-definition.j2
│
└── reports/                                         Newman JSON reports land here
```

> **`policy-files/` must stay next to the collection.** The operation-policy test uploads
> those two files as multipart form data. This is why every command below passes
> `--working-dir`.

---

## 4. First-time setup (run once, by an administrator)

The suite itself never creates or deletes an OAuth client — that requires privileges the
runtime user does not have, and provisioning a client on a live system minutes before a
maintenance window is undesirable.

Instead, an administrator registers the client **once** and the credentials are written
into the environment file.

```bash
cd MET_OFFICE

./bootstrap-client.sh \
  --host localhost \
  --port 9443 \
  --admin-user admin \
  --env APIM-4.5.0-Local.postman_environment.json
```

You will be prompted for the admin password. It is **never written to disk** — only
`client_id` and `client_secret` are stored.

Expected output:

```
-- registering 'smoke_client_admin' (owner admin) at https://localhost:9443
-- backup: APIM-4.5.0-Local.postman_environment.json.orig
-- wrote client_id / client_secret to APIM-4.5.0-Local.postman_environment.json
   client_id   : <your-generated-client-id>
```

Notes:

- **Safe to re-run.** WSO2's DCR endpoint is get-or-create, so repeating this returns the
  same client rather than creating a duplicate.
- Re-run it if the Key Manager is rebuilt or the client is deleted.
- Before running, open the environment file and set `admin_user` / `admin_pass` to the
  account the suite should run as (section 6).

---

## 5. Running the suite

```bash
cd MET_OFFICE

newman run MET_OFFICE.postman_collection.json \
  -e APIM-4.5.0-Local.postman_environment.json \
  --insecure \
  --working-dir . \
  --reporters cli,json \
  --reporter-json-export "reports/run-$(date +%Y%m%d-%H%M%S).json"
```

| Flag | Why it is required |
|---|---|
| `-e` | The environment file. Without it every `{{variable}}` resolves empty and the run collapses |
| `--insecure` | Accepts the self-signed certificates WSO2 ships with. Omit only if the deployment has trusted certificates |
| `--working-dir .` | Resolves `policy-files/` for the multipart upload. Without it two policy requests fail |
| `--reporters cli,json` | Prints to the terminal **and** writes a machine-readable report |
| `--reporter-json-export` | Where that report goes. The timestamp keeps each run instead of overwriting |

### A healthy run ends with

```
│              assertions │  90 │  0 │
│ total run duration: 13.9s              │
```

**Read both numbers.** `0 failed` alone is not sufficient — see section 8.

### The report

Each run writes `reports/run-<timestamp>.json` — the full result: every request,
response code, timing, assertion and failure.

To compare two runs, keep both files and diff the summary:

```bash
for f in reports/run-*.json; do
  python3 -c "
import json,sys
d=json.load(open('$f'))
s=d['run']['stats']['assertions']
print(f\"$f  checks={s['total']:<4} failed={s['failed']}\")"
done
```

Drop `--reporters cli,json --reporter-json-export ...` if you only want terminal
output.

## 6. Environment variables

Set these in the environment JSON before the first run.

### Must be reviewed for your deployment

| Variable | Example | Description |
|---|---|---|
| `cp_host` / `cp_port` | `localhost` / `9443` | Control Plane |
| `gw_host` / `gw_port` | `localhost` / `8244` | Universal Gateway (HTTPS) |
| `admin_user` / `admin_pass` | `smoke_user` / … | The account the suite runs as. **Not** an administrator |
| `gw_env_name` | `Default` | Primary gateway environment name |
| `vhost` | `localhost` | Virtual host used when deploying revisions |
| `backend_url` | `https://httpbin.org` | Backend the test API points at. Must be reachable **from the gateway node** |

### Test artifact names — change only if they clash

| Variable | Default | Description |
|---|---|---|
| `api_name` | `SMOKE_FixedTest1` | Name of the API the suite creates |
| `api_context` | `smoke-fixed-1` | Its context path |
| `api_version` | `1.0.0` | Its version |

### Written automatically — do not edit by hand

| Variable | Set by |
|---|---|
| `client_id` / `client_secret` | `bootstrap-client.sh` |
| `expected_client_id` | The suite, on first run (see section 8) |

### Required role and scopes

The runtime account needs a role granting these scopes:

```
apim:api_create      apim:api_delete     apim:api_publish    apim:api_view
apim:subscribe       apim:app_manage     apim:sub_manage
apim:document_create apim:document_manage
apim:tier_manage     apim:tier_view
apim:common_operation_policy_view        apim:common_operation_policy_manage
apim:api_mediation_policy_manage
```

On a stock 4.5.0 deployment the built-in `Internal/WSO2_ReadWrite` role covers all of these
**except `apim:tier_manage` and `apim:tier_view`**, which are admin-only by default. Add
those two to the role via **Admin Portal → Settings → Scope Assignments**, or remove the
`7.1_Throttling` folder if throttling coverage is not required.

---

## 7. Reading the results

Newman's summary has four rows. Only one of them indicates a broken deployment.

| Row | Meaning |
|---|---|
| `requests` | HTTP calls sent. Higher than the request count when retries occur; lower when requests are skipped |
| `prerequest-scripts` | Setup scripts run. Exceeds the request count because one collection-level script runs before **every** request |
| `test-scripts` | Post-response scripts run |
| **`assertions`** | **The individual checks. This is the number that matters** |

### Important: skipped requests are not failures

When a request fails, the requests that depend on its output are **skipped** — one root
cause produces one failure rather than a cascade of eight. Those skips are **not** counted
as failures.

This means a run can report `0 failed` while having checked far less than it should.
**Always read the assertion total alongside the failure count.**

- A full healthy run is **90 assertions**.
- `0 failed` with fewer than 90 assertions means something was skipped.

To make this visible, every run prints a summary before the results table:

```
===== RUN SUMMARY =====
SKIPPED (3) -- these did NOT run, so the check
count below is LOWER than a full run. Fix the failure above first:
   - Get Throttling Policy
   - Delete Throttling Policy
   - Verify Throttling Policy Deleted
========================
```

Requests that gate a folder also carry a note in their failure message explaining that
their dependents were skipped.

---

## 8. Important notes

**The suite recovers from its own failures.**
`2_PreClean` removes any `SMOKE`-prefixed artifact left over from an interrupted run —
API, application and throttling policy — before creating anything. A run that is killed
half-way does not block the next one. Recovery runs report *more* assertions than normal
(around 95), because PreClean has real work to verify.

**Every delete is scoped to the `SMOKE` prefix.**
The cleanup logic only ever matches artifacts whose name begins with `SMOKE`. It is
structurally incapable of deleting a customer API, application or throttling tier. Preserve
this property in any modification.

**Artifact names are fixed, not randomised.**
The same names are reused every run. This is safe because of PreClean, and it keeps the
API context stable and predictable.

**Two asynchronous operations are polled, never slept through.**
Gateway artifact sync after a deployment takes roughly 5–6 seconds, and token revocation
propagates to the gateway via the Traffic Manager. Both are handled with bounded retries
that fail with a diagnostic naming the likely component.

**Attach is not enforcement.** See section 1.

**Deleting an API leaves a registry entry behind.**
This is WSO2 behaviour, not a fault in the suite: each API deletion leaves rows under
`/_system/governance/apimgt/applicationdata/provider/` that are never reclaimed. It is
harmless — names remain reusable, because `2_PreClean` clears leftovers before each run —
but the row count grows over time. If you ever need to check it:

```sql
SELECT COUNT(*) FROM REG_PATH
WHERE REG_PATH_VALUE LIKE '%/applicationdata/provider/%';
```

**The environment file contains credentials.**
`admin_pass` and `client_secret` are stored in plain text. Treat the environment JSON as a
secrets file: restrict its permissions and keep it out of version control.

---

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `client_id/client_secret are missing from the environment` and the run stops after one request | `bootstrap-client.sh` has not been run for this environment file. See section 4 |
| Two policy requests fail with a file-not-found error | `--working-dir .` was omitted, or `policy-files/` is missing |
| Every request fails with a TLS error | `--insecure` was omitted |
| `7.1.1 Create Throttling Policy` returns **401** | The runtime role lacks `apim:tier_manage`. See section 6 |
| `6.2 Invoke API` fails after 20 attempts with **404** | The revision did not reach the gateway. Check Control Plane → Gateway artifact sync and that the revision deployed to the `Default` label |
| `6.4 Invoke with Revoked Token` never returns 401 | Token revocation events are not reaching the gateway. Check the Traffic Manager JMS topic and the gateway's event listener configuration |
| `OAuth client unchanged since the pinned run` fails | The OAuth client was recreated — typically a Key Manager rebuild or a database restore. Re-run `bootstrap-client.sh` and clear `expected_client_id` |
| A run reports `0 failed` but fewer than 90 checks | Requests were skipped. Read the `RUN SUMMARY` block above the results table |
