# WSO2 API Manager 4.5.0 — Operational Smoke Suite

A Postman/Newman suite that verifies a **WSO2 API Manager 4.5.0 distributed deployment**
is healthy and functional. It is designed to be run **immediately before and immediately
after any maintenance activity** — compare the two runs, so a regression is caught within
minutes rather than discovered by a customer.

The suite exercises a complete API lifecycle against a live deployment — create, publish,
deploy, subscribe, invoke, revoke, and tear down — and removes everything it creates.

| | |
|---|---|
| Checks per run | **93 assertions across 70 requests** |
| Typical runtime (In Local environment) | **13–16 seconds** |
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
| **9_ExistingAPI** | 3 | A pre-existing application obtains a token, an already-deployed API is invoked through the gateway, and the token is revoked. Read-only: creates nothing |

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
9_ExistingAPI/
    9.1 Generate Access Token (Existing APP)
    9.2 Invoke Existing API
    9.3 Revoke Existing App Token
```

### What it deliberately does **not** cover

- **Throttling enforcement (HTTP 429).** The suite verifies a policy can be *attached* to an
  API and that the association persists. It does **not** prove the limit is enforced —
  enforcement requires a revision redeploy and sustained traffic, which would take minutes.
  Do not read "Policy attached to API" as "rate limiting works".
- **High availability / failover.** The suite checks one gateway environment; it does not
  test failover between gateway nodes.
- **Performance.** This is a functional smoke suite, not a load test.
- **Gateway sync, in `9_ExistingAPI`.** 9.2 proves an *already-deployed* API is served by the
  gateway. A gateway loads deployed APIs at startup, so 9.2 can pass even when the Control
  Plane can no longer push changes to it. That is covered by `6.2` and `6.4`, not by 9.x.

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
- A gateway environment registered (stock name `Default` — set `gw_env_name` to yours)
- A user account for the suite to run as, with the role described in section 6
- Network access from the gateway to the backend used by the test API. `backend_url` must
  point at something the **gateway node** can reach; if the deployment is air-gapped,
  set it to an internal service that answers `GET /get`

### Stock ports

These are the out-of-the-box values. **Confirm them against your own deployment** — a port
offset, a reverse proxy or a load balancer changes them, and section 6 asks you to set the
two the suite uses.

| Node | Stock port | Used by the suite |
|---|---|---|
| Control Plane (Publisher / DevPortal / Admin APIs) | 9443 | yes — `cp_port` |
| Universal Gateway (HTTPS) | 8244 | yes — `gw_port` |
| Traffic Manager | 9445 | no — contacted by the gateway, not by the suite |

---

## 3. Repository structure

```
<suite-directory>/
├── README.md                                        this file
├── smoke-test-suite.postman_collection.json          the suite (70 requests)
├── APIM-4.5.0-Local.postman_environment.json        environment TEMPLATE -- copy, do not edit
├── working.local.json                               your filled-in copy -- you create this (section 6)
├── bootstrap-client.sh                              ONE-TIME admin setup (section 4)
│
└── policy-files/                                    REQUIRED at runtime
    ├── policy-spec.json                             uploaded by the operation-policy test
    └── policy-definition.j2
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
into your copy of the environment file.

```bash
cd <suite-directory>

cp APIM-4.5.0-Local.postman_environment.json working.local.json

./bootstrap-client.sh \
  --host <control-plane-host> \
  --port <control-plane-port> \
  --env working.local.json
```

You are prompted for the **admin username and password**. Deployments do not share an
admin account, so neither is baked into the command. Neither is written to disk — only
`client_id` and `client_secret` are stored.

Expected output:

```
Admin username (for client registration): wso2admin
Password for wso2admin:
-- registering 'smoke_client_wso2admin' (owner wso2admin) at https://<control-plane-host>:<port>
-- backup: working.local.json.orig
-- wrote client_id / client_secret to working.local.json
   client_id   : <your-generated-client-id>
```

Notes:

- **Safe to re-run.** WSO2's DCR endpoint is get-or-create, so repeating this returns the
  same client rather than creating a duplicate.
- Re-run it if the Key Manager is rebuilt or the client is deleted.
- `--admin-user <u>` skips the username prompt for unattended use. The password is always
  prompted and is never accepted as a flag.
- Before running the suite, open your `working.local.json` and fill in the rest of the
  values — host, gateway, and the account the suite runs as (section 6).

---

## 5. Running the suite

```bash
cd <suite-directory>

newman run smoke-test-suite.postman_collection.json \
  -e working.local.json \
  --insecure \
  --working-dir .
```

| Flag | Why it is required |
|---|---|
| `-e` | Your filled-in environment copy (section 6). Without it every `{{variable}}` resolves empty and the run collapses |
| `--insecure` | Accepts the self-signed certificates WSO2 ships with. Omit only if the deployment has trusted certificates |
| `--working-dir .` | Resolves `policy-files/` for the multipart upload. Without it two policy requests fail |

### A healthy run ends with

```
│              assertions │  93 │  0 │
│ total run duration: 13.9s              │
```

**Read both numbers.** `0 failed` alone is not sufficient — see section 8.

## 6. Environment variables

Set these in your environment file before the first run.

> **Copy it first.** The committed file is a template. Copy it to a name ending in
> `.local.json` — for example `working.local.json` — and edit *that*. `*.local.json` is
> gitignored, so your filled-in copy with its password and client secret can never be
> committed. Run against the copy, not the template.

### Must be reviewed for your deployment

**Every value below must be checked against your own deployment.** `<...>` marks a
placeholder — replace the whole thing, angle brackets included. The values in brackets
after each one are what a stock single-node 4.5.0 uses, and are a reasonable starting
point, but none of them are safe to assume.

| Variable | Set it to | Notes |
|---|---|---|
| `cp_host` | `<control-plane-host>` | Hostname or IP of the Control Plane *(stock: `localhost`)* |
| `cp_port` | `<control-plane-port>` | Control Plane HTTPS port *(stock: `9443`)*. Different if the deployment runs with a port offset, or behind a load balancer or reverse proxy |
| `gw_host` | `<gateway-host>` | Hostname or IP of the Universal Gateway *(stock: `localhost`)*. Often, but not always, the same as `cp_host` |
| `gw_port` | `<gateway-port>` | Gateway HTTPS port *(stock: `8244`)*. Same caveat as `cp_port` |
| `vhost` | `<gateway-vhost>` | Virtual host the revision is deployed on *(stock: `localhost`)*. Usually the same value as `gw_host`. Must match a vhost registered on the gateway environment |
| `gw_env_name` | `<gateway-environment>` | Gateway environment name **exactly as registered** in Admin Portal → Gateways *(stock: `Default`)* |
| `admin_user` | `<runtime-username>` | The account the suite runs as |
| `admin_pass` | `<runtime-password>` | That account's password |
| `backend_url` | `<backend-url>` | Backend the test API proxies *(example: `https://httpbin.org`)*. Must be reachable **from the gateway node** — if that host has no outbound internet access, point this at any internal HTTP service that answers `GET /get` |

> **The ports matter as much as the hosts.** A deployment behind a reverse proxy, or one
> started with a port offset, exposes neither `9443` nor `8244`. Confirm both before the
> first run — a wrong port fails every request with a connection error, not a clear
> message.

> **`admin_user` is not an administrator.** The name is historical. It is the
> **least-privilege** account the suite runs as, and it needs exactly the scopes listed
> below — nothing more. It is *not* the admin account `bootstrap-client.sh` prompts for;
> that one is only used to register the OAuth client and is never stored anywhere.

### Test artifact names — change only if they clash

The suite creates, verifies and deletes these on every run. Change them only if something
with the same name already exists on the deployment.

| Variable | Default | Notes |
|---|---|---|
| `api_name` | `SMOKE_FixedTest1` | **Keep the `SMOKE` prefix.** It is what scopes every delete in the suite (section 8) |
| `api_context` | `smoke-fixed-1` | Context path. Must be unique across the deployment |
| `api_version` | `1.0.0` | |

### Existing API check — `9_ExistingAPI`

The folder invokes an API that already exists on the deployment, using an application that
is already subscribed to it. The suite only reads them; it never creates, changes or deletes
either one. Leave the two credentials blank to skip the folder (the run then reports 90
assertions and lists 9.1–9.3 as SKIPPED).

| Variable | Set it to | Notes |
|---|---|---|
| `existing_api_path` | `<context>/<version>` | Path after the gateway host, no leading slash *(default: `wso2_main_gateway_health_check_api/v1`)* |
| `existing_app_client_id` | `<consumer-key>` | Consumer key of an application subscribed to that API. Its grant types must include **Client Credentials** |
| `existing_app_client_secret` | `<consumer-secret>` | That application's consumer secret |

> **Use an application dedicated to this check.** 9.1 issues a token for the application and
> 9.3 revokes it. Unless `renew_token_without_revoking_existing` is enabled, issuing a new
> token can revoke the application's previously active token — so do not point this at an
> application that real consumers use.

### Written automatically — leave blank, do not edit by hand

| Variable | Set by |
|---|---|
| `client_id` / `client_secret` | `bootstrap-client.sh` (section 4) |
| `expected_client_id` | The suite, on its first run. It pins the client id and compares it every run after — see section 8 |

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

- A full healthy run is **93 assertions** (90 if the `9_ExistingAPI` credentials are left blank).
- `0 failed` with fewer assertions than that means something was skipped.

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
(around 98), because PreClean has real work to verify.

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
`admin_pass` and `client_secret` are stored in plain text. Treat your filled-in copy as a
secrets file: `chmod 600` it, and keep the `.local.json` name so the gitignore rule covers
it. `bootstrap-client.sh` also leaves a `.orig` backup holding the same values — that is
covered by the `*.orig` rule.

---

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `client_id/client_secret are missing from the environment` and the run stops after one request | `bootstrap-client.sh` has not been run against this environment file. See section 4 |
| Every request fails against `localhost` when your deployment is elsewhere | `cp_host` / `gw_host` were left at the template defaults. See section 6 |
| Two policy requests fail with a file-not-found error | `--working-dir .` was omitted, or `policy-files/` is missing |
| Every request fails with a TLS error | `--insecure` was omitted |
| `7.1.1 Create Throttling Policy` returns **401** | The runtime role lacks `apim:tier_manage`. See section 6 |
| `6.2 Invoke API` fails after 20 attempts with **404** | The revision did not reach the gateway. Check Control Plane → Gateway artifact sync and that the revision deployed to the `Default` label |
| `6.4 Invoke with Revoked Token` never returns 401 | Token revocation events are not reaching the gateway. Check the Traffic Manager JMS topic and the gateway's event listener configuration |
| `9.1 Generate Access Token (Existing APP)` returns **401** | `existing_app_client_id` / `existing_app_client_secret` are wrong, or the application's grant types do not include Client Credentials |
| `9.2 Invoke Existing API` returns **404** | The existing API is not deployed on this gateway, or `existing_api_path` / the vhost is wrong |
| `9.2 Invoke Existing API` returns **403** | The application is not subscribed to the API, or the subscription has not reached the gateway |
| `OAuth client unchanged since the pinned run` fails | The OAuth client was recreated — typically a Key Manager rebuild or a database restore. Re-run `bootstrap-client.sh` and clear `expected_client_id` |
| A run reports `0 failed` but fewer than 93 checks | Requests were skipped. Read the `RUN SUMMARY` block above the results table |
