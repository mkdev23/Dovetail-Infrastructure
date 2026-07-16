# Deploy the Initial Environment — Step by Step
**Dovetail parent (SOC) tenant + enclave-dev, end to end.**
Follow top to bottom. Each phase has a checkpoint — don't proceed past a red check.
Demo is a repeat of Phases 4–10 with `demo` in place of `dev`.

Legend: `▶` = run this   `✓` = you should see this   `⚠` = watch out

---

## Phase 0 — Workstation prerequisites (one time)
▶
```bash
az version                 # Azure CLI present
az bicep install           # or: az bicep upgrade
pwsh --version             # PowerShell 7+ (the scripts are .ps1)
git --version
```
✓ All four return versions.
⚠ Do this on your i9 workstation, not over the Monrovia link. Everything below
should be dry-run complete before you fly.

---

## Phase 1 — One-time setup in the Dovetail (parent / SOC) tenant
This tenant is management-plane only — no workspace, no logs live here.

▶ Sign in to the Dovetail tenant:
```bash
az login
az account show --query tenantId -o tsv          # note as DOVETAIL_TENANT_ID
```

▶ Create the three SOC role groups and capture their object IDs:
```bash
az ad group create --display-name "SOC Analysts"   --mail-nickname "soc-analysts"
az ad group create --display-name "SOC Responders" --mail-nickname "soc-responders"
az ad group create --display-name "SOC Engineers"  --mail-nickname "soc-engineers"

az ad group show --group "SOC Analysts"   --query id -o tsv   # ANALYSTS_ID
az ad group show --group "SOC Responders" --query id -o tsv   # RESPONDERS_ID
az ad group show --group "SOC Engineers"  --query id -o tsv   # ENGINEERS_ID
```

▶ Add yourself and Divyash to the groups you'll operate from:
```bash
az ad group member add --group "SOC Analysts"   --member-id <your-user-objectid>
az ad group member add --group "SOC Responders" --member-id <your-user-objectid>
# repeat for Divyash
```

▶ Fill `lighthouse/lighthouse.parameters.json` with the four values:
```json
"managedByTenantId":   { "value": "DOVETAIL_TENANT_ID" },
"socReaderGroupId":    { "value": "ANALYSTS_ID" },
"socResponderGroupId": { "value": "RESPONDERS_ID" },
"socEngineerGroupId":  { "value": "ENGINEERS_ID" }
```

▶ Push the repo to a **private** GitHub repo (needed for Repositories in Phase 6):
```bash
cd sentinel-enclave-factory
git init && git add . && git commit -m "Sentinel enclave factory - initial"
git remote add origin git@github.com:dovetailcyber/sentinel-enclave-factory.git
git push -u origin main
```
✓ Three groups exist, their IDs are in the lighthouse param file, repo is on GitHub.

---

## Phase 2 — Create the enclave-dev tenant + subscription
Dev is a **separate tenant** on purpose — it's the only way to actually test the
Lighthouse cross-tenant onboarding before a real customer.

▶ Create the tenant (portal): Entra admin center → **Manage tenants** → **Create**
→ type "Workforce" → name `Dovetail Enclave Dev`. Note the new **DEV_TENANT_ID**.

▶ Attach a subscription to the dev tenant. This is the one step that needs your
billing setup and can't be fully scripted. Fastest paths:
- **MCA/EA billing account:** create a subscription and set its tenant to the dev
  tenant (`az account subscription create ...` if you have billing-account rights), or
- **PAYG:** while signed into the dev tenant in the portal, sign up a new
  pay-as-you-go subscription (needs a card).

Note the **DEV_SUB_ID**. As the tenant/subscription creator you now hold **Owner** in dev.
✓ You can `az login --tenant DEV_TENANT_ID` and see DEV_SUB_ID.

---

## Phase 3 — Lighthouse onboard dev  (run as Owner *in the dev tenant*)
▶
```bash
az login --tenant <DEV_TENANT_ID>
az account set --subscription <DEV_SUB_ID>

az deployment sub create \
  --location southafricanorth \
  --template-file lighthouse/lighthouse.json \
  --parameters lighthouse/lighthouse.parameters.json
```
✓ Verify both directions:
- Dovetail tenant → **Service providers → My customers** shows the dev subscription.
- (Optional) dev tenant → **Service providers** shows the Dovetail offer.
⚠ If you don't see it in ~2 min, re-check the four IDs in the param file — a wrong
group ID is the usual culprit and it fails silently (deploys, grants nothing useful).

---

## Phase 4 — SSH key for the dev forwarder
Dev deploys a forwarder VM (the egress-server cloud twin), so it needs a public key.

▶
```bash
ssh-keygen -t ed25519 -f ./dc-dev-forwarder -C "dc-dev-forwarder" -N ""
cat ./dc-dev-forwarder.pub          # copy the whole line
```
▶ Paste that public key into `enclaves/enclave-dev.bicepparam`:
```bicep
param forwarderSshPublicKey = 'ssh-ed25519 AAAA... dc-dev-forwarder'
```
✓ Param file has a real key string (not empty).
⚠ Keep `dc-dev-forwarder` (the private key) out of git — add it to `.gitignore`.

---

## Phase 5 — Deploy the dev enclave
Still signed into the dev subscription (you hold Owner during build).

▶ Preview first:
```powershell
./scripts/deploy-enclave.ps1 -Enclave dev -SubscriptionId <DEV_SUB_ID> -WhatIf
```
✓ What-if lists: 1 resource group, workspace, Sentinel onboarding, DCE, 3 DCRs,
notification playbook, forwarder VM + NIC + NSG + VNet + 3 DCR associations.

▶ Deploy for real:
```powershell
./scripts/deploy-enclave.ps1 -Enclave dev -SubscriptionId <DEV_SUB_ID>
```
✓ Ends with the outputs block (workspace name, DCE ingestion endpoint).
⚠ MDE and Defender-for-IoT connectors are intentionally **off** for the bare lab
(`enableMde=false`, no D4IoT sub) — nothing to connect to yet. You'll flip these on
in a real customer enclave. If a deploy ever errors on a connector, that's why.

---

## Phase 6 — Connect Sentinel Repositories (push the detection content)
This deploys `content/` (8 analytics rules, 2 automation rules, hunting queries,
SOC workbook) into the dev workspace via a GitHub Action.

▶ In the portal (Dovetail tenant, reaching dev via Lighthouse — or sign into dev):
Microsoft Sentinel → select **law-dc-dev-prod** → **Content management → Repositories**
→ **Add new** → authorize GitHub → pick `sentinel-enclave-factory` → branch `main`
→ content types: Analytics rules, Automation rules, Hunting queries, Workbooks → **Create**.

✓ A GitHub Action runs (check the Actions tab). Within a few minutes:
Sentinel → **Analytics** shows the 8 Dovetail rules; **Workbooks** shows "Dovetail SOC Overview".
⚠ Watchlists are **not** carried by Repositories — that's the next phase, and three
rules stay dormant until it's done.

---

## Phase 7 — Deploy watchlists
▶
```powershell
./scripts/deploy-watchlists.ps1 -Enclave dev -SubscriptionId <DEV_SUB_ID>
```
✓ Sentinel → **Watchlist** shows `critical-assets` and `approved-admins`.

---

## Phase 8 — Validate
▶
```powershell
./scripts/validate-enclave.ps1 -Enclave dev -SubscriptionId <DEV_SUB_ID>
```
✓ Every line PASS: RG, workspace, Sentinel, DCE, 3 DCRs, forwarder heartbeat.
⚠ Heartbeat may take 5–10 min after the VM boots. Re-run if it's the only fail.

---

## Phase 9 — Prove the pipeline is alive (the test that matters)
Two quick proofs — do both.

**A. Data lands.** SSH to the forwarder and inject a test CEF event:
```bash
ssh -i ./dc-dev-forwarder dcadmin@<forwarder-private-ip-or-bastion>
logger -n 127.0.0.1 -P 514 -t CEF \
  "CEF:0|Fortinet|FortiGate|7.4|logauth|admin login failed|5|src=10.90.0.99 duser=admin"
```
✓ Within ~5 min: `CommonSecurityLog | where DeviceVendor == "Fortinet" | take 10`
returns your test event in the dev workspace.

**B. Detection + Lighthouse + queue, end to end.** Stop the forwarder:
```bash
sudo systemctl stop rsyslog        # or stop the VM from the portal
```
✓ Within ~15 min the **"Log Forwarder Heartbeat Loss"** analytic fires an incident,
and — signed in as a Dovetail analyst in the **parent** tenant — it appears in the
Defender **multi-workspace incident queue**. That single incident proves the whole
chain: ingestion → detection content → Lighthouse delegation → cross-tenant visibility.

▶ Restart when done: `sudo systemctl start rsyslog`.

---

## Phase 10 — Repeat for demo, then you're done
Phases 4–9 with `demo`: own SSH key, `-Enclave demo -SubscriptionId <DEMO_SUB_ID>`.
Seed demo with sample data later (ask for the demo-seeding script) so the workbook
and queue look alive for ministry meetings.

---

## Initial-environment checklist
- [ ] SOC groups created, IDs in lighthouse param file
- [ ] Repo on private GitHub
- [ ] Dev tenant + subscription exist; you hold Owner
- [ ] Lighthouse onboarded; dev visible under My customers
- [ ] Forwarder SSH key generated and in the param file (private key git-ignored)
- [ ] `deploy-enclave.ps1 dev` succeeded
- [ ] Repositories connected; 8 rules + workbook present
- [ ] Watchlists deployed
- [ ] `validate-enclave.ps1 dev` all PASS
- [ ] Test CEF event visible in CommonSecurityLog
- [ ] Heartbeat-loss incident seen in the parent multi-workspace queue
- [ ] Demo repeated
