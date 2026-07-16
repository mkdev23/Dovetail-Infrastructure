# Sentinel Enclave Factory
**Dovetail Cyber — multitenant Sentinel deployment automation (LP-39)**

One enclave = one parameter file + one deploy command. Analysts in the Dovetail
parent tenant see every enclave via Azure Lighthouse delegated access; enclaves
are hard-isolated from each other (tenant-per-enclave, Option A).

## Confirmed architecture decisions
| Decision | Value |
|---|---|
| Isolation model | Option A — tenant per enclave, Azure Lighthouse delegation |
| Region | South Africa North (validate uplink onsite day 1) |
| Initial environments | Dovetail parent (SOC) + `enclave-dev` tenant + `enclave-demo` tenant |
| Enclave subscription Owner | Dovetail (Jay + Divyash) **during build only** → downgrade to Lighthouse-delegated at handoff; customer rep + break-glass account retain Owner |
| Analyst access | Sentinel Reader permanent; Responder/Contributor PIM-eligible (JIT, MFA, audit-logged in enclave tenant) |
| Filtering | At collection (DCR xPath / transformKql), never "ingest then tune" |

## Repo layout
```
main.bicep                     # subscription-scoped entrypoint (one enclave)
modules/
  workspace.bicep              # LAW + Sentinel onboarding + health audit
  ingestion.bicep              # DCE + DCRs: WinSec (curated), Syslog, CEF (+transformKql)
  connectors.bicep             # Defender for IoT + MDE connectors, incident-creation rules
  automation.bicep             # webhook notification playbook + managed identity RBAC
  forwarder.bicep              # dev/demo egress-server twin (rsyslog buffer + AMA + DCR assoc)
  rbac.bicep                   # enclave-user Sentinel Reader on the enclave RG
lighthouse/
  lighthouse.json              # registration definition + assignment (run in enclave tenant)
  lighthouse.parameters.json   # fill Dovetail tenant/group IDs once
enclaves/
  _template.bicepparam         # copy per enclave — only file that changes
  enclave-dev.bicepparam       # OT profile + cloud forwarder, 2 GB/day cap
  enclave-demo.bicepparam      # OT profile + cloud forwarder, 5 GB/day cap
  enclave-lec.bicepparam       # pre-staged prod: OT profile, physical forwarder via Arc
scripts/
  deploy-enclave.ps1           # idempotent deploy wrapper
  deploy-watchlists.ps1        # watchlist delivery (Repositories doesn't carry these)
  validate-enclave.ps1         # post-deploy health checks incl. forwarder heartbeat
content/                       # Sentinel Repositories source — one PR = all enclaves
  analytics-rules/             # 8 rules: pipeline health, OT boundary, EMS-tier detections
  automation-rules/            # OT tagging + severity floor, informational auto-close
  hunting-queries/             # new OT talker, rare outbound, new auth pairs
  workbooks/                   # Dovetail SOC Overview (pipeline health first)
  watchlists/                  # critical-assets (EO 163 inventory seed), approved-admins
  playbooks/                   # (playbooks deploy via modules/automation.bicep)
docs/
  LEC-REFERENCE-ARCHITECTURE.md  # proposal infra -> factory mapping, diode implications, Arc build
  SOC-OPERATIONS.md              # SLAs, daily/weekly routine, triage guides, escalation
```

## One-time setup (Dovetail parent tenant)
1. Create Entra groups: `SOC Analysts`, `SOC Responders`, `SOC Engineers` (optionally `PIM Approvers`).
2. Put the three group object IDs + Dovetail tenant ID into `lighthouse/lighthouse.parameters.json`.
3. Push this repo to GitHub (private) — it becomes the Sentinel Repositories source.

## Per-enclave runbook (~30 min once practiced)
1. **Tenant + subscription** exist in the enclave (customer-owned for prod; Dovetail-owned for dev/demo).
2. **Lighthouse onboard** — an Owner in the enclave subscription runs, from Cloud Shell:
   ```bash
   az deployment sub create --location southafricanorth \
     --template-file lighthouse/lighthouse.json \
     --parameters lighthouse/lighthouse.parameters.json
   ```
   Verify under *Service providers* in the enclave tenant / *My customers* in Dovetail.
3. **Copy** `enclaves/_template.bicepparam` → `enclave-<name>.bicepparam`, fill values.
4. **Deploy**:
   ```powershell
   ./scripts/deploy-enclave.ps1 -Enclave <name> -SubscriptionId <enclave-sub-id> -WhatIf   # review
   ./scripts/deploy-enclave.ps1 -Enclave <name> -SubscriptionId <enclave-sub-id>
   ```
5. **Connect Repositories**: Sentinel → Content management → Repositories → this repo. All 8 analytics rules, 2 automation rules, hunting queries, and the SOC workbook deploy automatically.
5b. **Deploy watchlists**: `./scripts/deploy-watchlists.ps1 -Enclave <name> -SubscriptionId <sub>` — three analytics rules join against `critical-assets`, so this step is not optional.
6. **Forwarders**: build the enclave forwarder VM (AMA + syslog-ng disk buffer), associate to the three DCRs:
   ```bash
   az monitor data-collection rule association create \
     --name "dcr-assoc-<name>-cef" \
     --resource "<forwarder-vm-resource-id>" \
     --rule-id "<dcr-dc-<name>-cef resource id>"
   ```
7. **Validate**:
   ```powershell
   ./scripts/validate-enclave.ps1 -Enclave <name> -SubscriptionId <enclave-sub-id>
   ```
8. Confirm the enclave's workspace appears in the Dovetail multi-workspace incident queue.

## Weekend dry run (before Monday)
- [ ] Create `enclave-dev` tenant + subscription
- [ ] One-time setup steps 1–3 above
- [ ] Full runbook against dev, including Lighthouse — this is the step you must not first-try in Monrovia
- [ ] Kill the forwarder → confirm the heartbeat-loss rule fires an incident visible from a Dovetail analyst account
- [ ] Demo the PIM elevation flow once, screen-record it (reusable for ministry meetings)
- [ ] Stamp `enclave-demo`, seed with sample data
- [ ] Export offline: AMA installers, this repo as a bundle, az CLI/Bicep installers

## Handoff checklist (per production enclave)
- [ ] Customer rep confirmed as subscription Owner; break-glass account created, creds sealed
- [ ] Dovetail direct Owner role assignments **removed** (access continues via Lighthouse only)
- [ ] Enclave staff group assigned via `enclaveReaderGroupId`
- [ ] Customer shown the Service Providers blade + their own audit log of Dovetail PIM elevations
