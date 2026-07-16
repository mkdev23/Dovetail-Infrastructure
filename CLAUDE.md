# CLAUDE.md — Sentinel Enclave Factory: Content Restructure & Multi-Vertical Demo

**Audience:** Claude Code, working in VS Code on the `sentinel-enclave-factory` repo.
**Author:** Jay (Julius Stewart), Dovetail Cyber.
**Status:** Phase-1 factory is built and deploys. This task restructures *content*
so the factory serves multiple verticals cleanly — it does NOT change the deploy
mechanics, isolation model, or Lighthouse design. Do not touch those.

---

## 0. Context you need before touching anything

Dovetail runs a multitenant Microsoft Sentinel MSSP factory. One repo stamps out
isolated "enclaves" (Azure Lighthouse, tenant-per-enclave). The factory already
works. Read these first, in order, and do not contradict them:
- `README.md` — repo overview, confirmed architecture decisions
- `docs/DEPLOY-INITIAL-ENVIRONMENT.md` — the deploy runbook (don't break this flow)
- `docs/LEC-REFERENCE-ARCHITECTURE.md` — the OT reference (LEC = enclave zero)
- `main.bicep` and `modules/` — the deploy logic
- `enclaves/*.bicepparam` — per-enclave params; note the existing `profile` switch

**The one-line problem to solve:** all detection content in `content/` is currently
hardwired to the LEC/OT/SCADA vertical (FortiGate, Defender for IoT, diode, critical
SCADA assets). That's correct for a utility enclave but wrong as *the* content for
every enclave. A Ministry of Health customer with no OT devices would get rules that
never fire. We need content that layers: a universal **baseline** everyone gets, plus
**profile packs** (OT, IT) that deploy only where relevant, plus optional light
**vertical** flavor for demos.

**Guiding principle:** don't throw away the OT work — *demote* it from "the content"
to "the OT profile's content," and *promote* the vertical-neutral pieces to a baseline
every enclave inherits. Nothing about the OT detections is wrong; they're just
mis-scoped as universal.

---

## 1. Target content structure

Refactor `content/` from its current flat layout into:

```
content/
  baseline/                     # vertical-neutral — EVERY enclave gets this
    analytics-rules/
    automation-rules/
    hunting-queries/
    workbooks/
    watchlists/
  profiles/
    ot/                         # deploys only when profile = 'ot'
      analytics-rules/
      automation-rules/
      hunting-queries/
      workbooks/
      watchlists/
    it/                         # deploys only when profile = 'it' (identity/endpoint/SaaS)
      analytics-rules/
      automation-rules/
      hunting-queries/
      workbooks/
      watchlists/
  verticals/                    # OPTIONAL light flavor packs for demo polish
    health/                     # Ministry of Health demo (IT-profile flavored)
      workbooks/
      watchlists/
    utility/                    # utility flavor demo pack (see §3a)
      workbooks/
```

### 1a. How to classify the existing 8 analytics rules
Move each existing file to baseline or profiles/ot. Where a rule is *conceptually*
universal but *currently* has OT-specific joins (e.g. joins against a SCADA
`critical-assets` watchlist), split it: keep a clean vertical-neutral version in
baseline, and if an OT-specialized variant adds value, put that in profiles/ot.

| Current file | Destination | Action |
|---|---|---|
| `dovetail-baseline-forwarder-heartbeat-loss.json` | **baseline** | Already neutral. Move as-is. |
| `dovetail-windows-bruteforce.json` | **baseline** | Neutral (4625 burst). Remove any EMS/OT wording in the description; keep generic. |
| `dovetail-new-local-admin.json` | **baseline** | Neutral persistence pattern. Keep the approved-admins watchlist join but make the watchlist a baseline asset (see 1b). |
| `dovetail-after-hours-critical-access.json` | **baseline** (generalized) | Rename concept from "critical SCADA asset" to "critical asset" generally; the critical-assets watchlist becomes baseline and is populated per enclave. |
| `dovetail-service-installed-critical-asset.json` | **baseline** (generalized) | Same generalization — new service on any watchlisted critical asset, not just SCADA. |
| `dovetail-fortigate-admin-auth-failures.json` | **profiles/ot** | FortiGate-specific. OT boundary. Move. |
| `dovetail-fortigate-config-change.json` | **profiles/ot** | FortiGate-specific. Move. |
| `dovetail-ot-telemetry-silence.json` | **profiles/ot** | CEF/diode-specific. Move. |

### 1a-bis. How to classify the existing automation rules and hunting queries

The 5 files under `content/automation-rules/` and `content/hunting-queries/` also
need to move — the target tree above gives both `baseline/` and `profiles/ot/` /
`profiles/it/` an `automation-rules/` and `hunting-queries/` slot for exactly this.

| Current file | Destination | Action |
|---|---|---|
| `dovetail-autoclose-informational.json` (automation-rules) | **baseline** | Neutral triage automation. Move as-is. |
| `dovetail-tag-ot-incidents.json` (automation-rules) | **profiles/ot** | OT-specific tagging logic. Move. |
| `dovetail-hunt-auth-outside-pattern.json` (hunting-queries) | **baseline** | Neutral auth-pattern hunt. Move as-is; strip any OT wording in the description. |
| `dovetail-hunt-new-ot-talker.json` (hunting-queries) | **profiles/ot** | OT network-talker hunt. Move. |
| `dovetail-hunt-rare-outbound-ot.json` (hunting-queries) | **profiles/ot** | OT egress hunt. Move. |

### 1b. Watchlists
- `critical-assets.csv` and `approved-admins.csv` become **baseline** watchlists
  (every enclave has critical assets and approved admins — not an OT-only concept).
- BUT the *current* `critical-assets.csv` is seeded with SCADA/OT rows (EMS, historian,
  D4IoT sensors). Split it:
  - `content/baseline/watchlists/critical-assets.SAMPLE.csv` — schema + 2 generic rows,
    documented as "populate per enclave."
  - `content/profiles/ot/watchlists/critical-assets.ot-sample.csv` — the existing
    SCADA-seeded rows, as an OT example / demo seed.
- Keep the watchlist **schema identical** across both so the baseline rules' joins work
  regardless of which seed is used.

### 1c. Workbooks
- The existing SOC Overview workbook (`content/workbooks/dovetail-soc-overview.json`)
  mixes neutral panels (heartbeat, ingestion, incidents) with OT panels (FortiGate
  denies, Defender for IoT alerts). Split into:
  - `content/baseline/workbooks/dovetail-soc-overview.json` — neutral panels only
    (pipeline health, ingestion volume, incidents by severity, top sign-in anomalies).
  - `content/profiles/ot/workbooks/dovetail-ot-overview.json` — the OT panels
    (FortiGate denies, D4IoT alerts, OT asset silence).
  - `content/verticals/health/workbooks/dovetail-health-overview.json` — NEW, see §3.

---

## 2. Wire the structure into deployment

Content deploys via **Sentinel Repositories**, which connects a workspace to repo
folders. Today it points at flat `content/`. After restructure, an enclave should
receive: `baseline/` ALWAYS, plus `profiles/<profile>/` matching its `profile` param,
plus optionally a named vertical pack.

Two acceptable implementation paths — pick the simpler one that works, document which:

**Option 1 (preferred — config-driven):** add a `contentPacks` concept. In each
`enclave-*.bicepparam`, add a param like:
```bicep
param contentPacks = ['baseline', 'profiles/ot']          // lec / demo-ot
param contentPacks = ['baseline', 'profiles/it']          // moh
param contentPacks = ['baseline', 'profiles/it', 'verticals/health']  // demo-moh
```
This param drives which folders the Repositories connection (or the deployment script)
pulls. If Sentinel Repositories can't select multiple arbitrary folders per connection
cleanly, fall back to Option 2.

**Option 2 (branch/path-mapping):** use the deploy script to copy the selected packs
into a per-enclave staging path that Repositories watches, or generate a per-enclave
Repositories config. Keep it idempotent and scripted — no manual folder-picking in the
portal per enclave (that breaks the "factory" promise).

**Hard requirement:** whatever the mechanism, adding an enclave must stay: edit one
param file + run one deploy command. If your approach adds manual steps, it's wrong.

Update `scripts/deploy-enclave.ps1` and `scripts/deploy-watchlists.ps1` as needed so
they honor the selected packs. Update `docs/DEPLOY-INITIAL-ENVIRONMENT.md` Phase 6/7
to match.

---

## 3. New: IT profile + Ministry of Health demo content

The `profiles/it/` pack barely exists today — build it out. Target ~4-6 analytics
rules that need NO OT and speak to a ministry/agency IT environment:
- Impossible-travel / atypical sign-in (Entra `SigninLogs`)
- Mass download / potential data exfiltration (M365 / `OfficeActivity` or `CloudAppEvents`)
- Privileged role assignment change (Entra audit)
- MFA disabled / auth method removed on a privileged account
- Suspicious inbox forwarding rule (classic exfil pattern)
- Sign-in from anonymizer/Tor to a sensitive account

These are illustrative — write them as proper scheduled-rule ARM templates matching the
existing baseline rule format (same schema, `parameters.workspace`, entity mappings,
tactics/techniques). Keep queries defensive about table availability (an enclave may not
have every connector) — guard with `union isfuzzy=true` or existence checks where sensible.

Then `verticals/health/`:
- A **Ministry of Health SOC Overview workbook** — same neutral bones as baseline, but
  titled/flavored for MoH, with panels for the IT rules above (identity anomalies,
  data-access, privileged changes). This is what we show in a MoH demo.
- A sample `critical-assets.csv` seeded with plausible MoH IT assets (patient-records
  DB server, HIS app server, domain controllers, admin jump host) — same schema as
  baseline, so the baseline rules light up against it.

**Tone/accuracy note:** keep MoH sample data obviously synthetic (hostnames like
`MOH-HIS-APP-01`, no real patient data, no real IPs). This is a demo prop.

### 3a. New: utility vertical (demo flavor)

`verticals/utility/` is a light flavor pack, not a new content type — it should
NOT duplicate `profiles/ot`'s analytics rules or watchlists (those already exist
there). Build just:
- `content/verticals/utility/workbooks/dovetail-utility-overview.json` — a
  utility-company-titled SOC overview workbook that reframes the `profiles/ot`
  panels (FortiGate denies, D4IoT alerts, OT asset silence) for a utility-customer
  demo audience — same idea as the MoH workbook above, but for the OT side. It can
  reuse/alias the `profiles/ot` workbook's queries; the point is title/branding for
  the demo, not new detections.

Wire it into the OT demo enclave: `enclave-demo-ot.bicepparam`'s packs become
`['baseline','profiles/ot','verticals/utility']` (see §4).

---

## 4. New demo enclave param files

Create these in `enclaves/` (copy the `_template.bicepparam` pattern, keep the lab
`enableMde=false` and forwarder-VM choices consistent with existing demo file).

**Note:** `enclave-dev.bicepparam` and `enclave-lec.bicepparam` both still carry a
leftover header comment reading "copy to enclave-demo.bicepparam" from when they
were copied from `_template.bicepparam`. Fix each new file's header comment to
reference its own filename — don't propagate that copy-paste bug again.

- `enclave-demo-ot.bicepparam` — profile `ot`, packs
  `['baseline','profiles/ot','verticals/utility']`, the current LEC/utility demo.
  (This is essentially today's `enclave-demo` renamed; preserve its settings.)
- `enclave-demo-moh.bicepparam` — profile `it`, packs
  `['baseline','profiles/it','verticals/health']`, a Ministry of Health demo.
- `enclave-demo-baseline.bicepparam` — profile `it`, packs `['baseline']` only, a
  vendor-neutral generic-government demo (the safe default for a cold audience).

All three deploy into the **single Dovetail-Demo subscription** — separate enclaves,
not separate subscriptions. (One demo sub, many demo enclaves. Do not create new
subscriptions.) Confirm the naming/RG scheme in `main.bicep` supports multiple enclaves
per subscription (it should — RG name derives from `enclaveName`); if not, flag it.

---

## 5. Guardrails — do NOT do these

- Do not change the isolation model, Lighthouse templates (`lighthouse/`), or the
  tenant-per-enclave design.
- Do not add manual per-enclave portal steps. Factory = param file + one command.
- Do not delete the OT content — it moves to `profiles/ot/`, intact.
- Do not invent real-looking customer data (no real IPs, patient data, org names beyond
  the obvious synthetic `MOH-*` / `LEC-*` placeholders).
- Do not hardcode cloud endpoints; if you touch anything cloud-specific keep it
  commercial-Azure / South Africa North and env-driven.
- Do not break `az bicep build --file main.bicep`. Run it before finishing.

---

## 6. Definition of done

1. `content/` restructured into `baseline/`, `profiles/{ot,it}/`, `verticals/{health,utility}/`;
   all 8 existing analytics rules, plus the 2 automation rules and 3 hunting queries,
   relocated per §1a / §1a-bis; OT content intact under `profiles/ot/`.
2. Baseline rules are genuinely vertical-neutral (no FortiGate/D4IoT/SCADA assumptions);
   watchlists split into baseline sample + ot sample with identical schema.
3. IT profile pack built out (~4-6 identity/endpoint rules); MoH vertical workbook +
   sample assets created; utility vertical workbook created and wired into
   `enclave-demo-ot` (see §3a).
4. `contentPacks` (or equivalent) mechanism wired through params + deploy script so an
   enclave pulls baseline + its profile + optional vertical, with zero manual steps.
5. Three demo enclave param files created, all targeting the one Dovetail-Demo sub.
6. `docs/DEPLOY-INITIAL-ENVIRONMENT.md` updated for the new content flow; a short
   `docs/CONTENT-PACKS.md` written explaining the baseline/profile/vertical model so the
   next person (or demo) understands what deploys where.
7. `README.md`'s repo-layout / content description updated to match the new `content/`
   structure (it currently documents the old flat, OT-hardwired layout).
8. `az bicep build --file main.bicep` passes; JSON in `content/` validates.

---

## 7. Suggested order of work (small, reviewable commits)

1. Create the new `content/` folders; move the 3 FortiGate/OT-silence analytics rules
   plus the OT-specific automation rule and hunting queries to `profiles/ot/` unchanged.
   Commit.
2. Move + generalize the 5 baseline-bound analytics rules plus the neutral automation
   rule and hunting query; strip OT wording; split workbook and watchlists. Commit.
   Verify JSON validates.
3. Build the IT profile rule pack. Commit.
4. Build the MoH vertical (workbook + sample assets) and the utility vertical
   (workbook, wired into `enclave-demo-ot`). Commit.
5. Wire `contentPacks` through params + deploy script; update deploy doc. Commit.
6. Add the three demo param files. Commit.
7. Write `docs/CONTENT-PACKS.md`; update `README.md`'s content description; run
   `az bicep build`; final commit.

Keep each commit focused so Jay can review the restructure separately from the new
content. When unsure whether a rule is "baseline" or "profile," ask: *would this fire
usefully in an environment with no OT and no unusual connectors?* If yes → baseline.
If it depends on FortiGate/D4IoT/SCADA/CEF specifics → profiles/ot.
