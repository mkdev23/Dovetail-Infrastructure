# Dovetail SOC — Tier 1 Analyst Training & SC-200 Study Guide

**Status:** Production v1.0, 2026-07-16. Self-contained: you should be able to work
this guide start to finish without hopping between files, though it links back to
the rest of the suite for anything operational it doesn't repeat. Goal: every Tier 1
hire is job-ready on Dovetail's factory **and** ready to sit and pass
**SC-200: Microsoft Security Operations Analyst** within their first 90 days.

**Relationship to the rest of this suite:** `03-training-guide.md` is the original
single-track onboarding walkthrough (hands-on Lighthouse/PIM/queue exercises) — do
those exercises, they're not repeated here. This guide adds the exam-mapped study
path and goes deeper on the theory behind what `03` has you click through. Where
the two overlap, this is the newer document; if they ever disagree, `03`'s
hands-on steps win (they're verified against the live factory) and this doc's
prose should be corrected to match.

**Pairing:** read this alongside a live walkthrough of the `dev` or `demo` enclave.
Reading alone does not make you exam-ready or job-ready — you need queries you've
actually run and an incident you've actually triaged.

---

## 0. What Tier 1 is, and isn't

Tier 1 is the **frontline**: monitor the multi-workspace queue, triage every new
incident using SOP-4's isolation check and the documented triage guides, execute
the daily/weekly routine, and escalate anything outside the documented playbook to
Tier 2 or Jay/Divyash. Tier 1 holds **Sentinel Reader** permanently and may be
granted **Responder** (PIM-eligible, per `01-mssp-architecture.md` §3) once signed
off — see the promotion checklist at the end of this doc.

Tier 1 is explicitly **not** yet expected to: author or tune analytics rules, run
Engineer-tier PIM elevations, make client-notification judgment calls alone, or
execute anything against the OT hard gate. That's Tier 2 (`07-training-tier2.md`).
If a Tier 1 analyst finds themselves needing to do any of those to close an
incident, that itself is the signal to escalate, not push through.

---

## 1. SC-200 exam overview

**Exam:** SC-200 — Microsoft Security Operations Analyst. Passing it (alongside the
role-based experience in this guide) earns the **Microsoft Certified: Security
Operations Analyst Associate** badge.

**Skills measured (four domains).** Weights below are the structure Microsoft has
used for this exam; **verify the current weighting and objective list on Microsoft
Learn before you schedule** — Microsoft revises these periodically without much
fanfare, the same way you'd verify a regulatory citation before repeating it to a
client (see `01-mssp-architecture.md` §8 for why that habit matters here generally).

| Domain | Approx. weight | One-line scope |
|---|---|---|
| 1. Manage a security operations environment | 20-25% | Workspace/tenant config, data connectors, RBAC, watchlists, indicators |
| 2. Configure protections and detections | 15-20% | Analytics rules, automation rules, Defender product protections, UEBA, threat intel |
| 3. Manage incident response | 25-30% | Incident triage/investigation/remediation across Sentinel and Microsoft Defender XDR |
| 4. Perform threat hunting | 12-15% | KQL, hunting queries, notebooks, workbooks, livestream |

**Format (verify current details when you schedule):** roughly 40-60 questions,
multiple-choice/drag-and-drop/case-study format, ~150 minutes, scored 100-1000,
passing score typically 700. No formal prerequisite exam, but Microsoft assumes
familiarity with Microsoft 365, Azure fundamentals, and basic KQL going in — this
guide builds all three from the Dovetail environment you already have hands-on
access to.

**Registration:** via Microsoft's certification dashboard (Pearson VUE proctoring,
in-person or online). **Renewal:** Microsoft associate certs are valid ~1 year and
renew via a free, shorter online assessment on Microsoft Learn before expiry — put
a calendar reminder in, don't let it lapse.

**How Dovetail maps to it:** everything in Domains 1, 2, and 4 that Dovetail's
factory actually runs (Sentinel, KQL, analytics rules, hunting queries, workbooks,
Defender for IoT, Defender for Endpoint) you'll learn hands-on against a real
enclave — that's the strongest kind of exam prep there is. Domain 3 (incident
response) is close to 1:1 with your actual job. The exam also covers Microsoft
Defender for Office 365, Defender for Identity, and Defender for Cloud Apps, which
Dovetail's factory does **not** run today (§7 below) — for those, this guide gives
you the conceptual grounding and points you at the specific Microsoft Learn modules
to close the gap, clearly marked so you never confuse "exam knowledge" with
"something I've actually operated."

---

## 2. KQL fundamentals (Domain 4 foundation, needed everywhere else too)

Every analytics rule, hunting query, and workbook panel in `content/` is KQL. You
cannot triage, let alone hunt, without reading it fluently. Learn these against
**real Dovetail queries**, not toy examples.

**Core operators:**

| Operator | Does | Example from `content/` |
|---|---|---|
| `where` | Filters rows | `SecurityEvent \| where EventID == 4720` |
| `project` | Selects/renames columns | `\| project CreatedTime = TimeGenerated, TargetAccount, Computer` |
| `summarize` | Aggregates | `Heartbeat \| summarize LastHeartbeat = max(TimeGenerated) by Computer` |
| `join` | Combines tables on a key | `created \| join kind=inner (added) on Computer` |
| `let` | Names a reusable sub-query | `let created = SecurityEvent \| where EventID == 4720 ...` |
| `ago()` | Relative time | `where LastHeartbeat < ago(15m)` |
| `between` | Time-window filter | `where AddedTime between (CreatedTime .. 1h)` |
| `extend` | Adds a computed column without dropping others | not yet used in `content/` — you'll need it when you write your first tuning PR |
| `distinct` | Unique rows | used in the auth-outside-pattern hunt's baseline |

**Read this real rule line by line** — `content/analytics-rules/dovetail-baseline-forwarder-heartbeat-loss.json`:
```kql
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| where LastHeartbeat < ago(15m)
```
This is the single most important query in the whole factory (see Module 4 in
`03-training-guide.md` and `docs/LEC-REFERENCE-ARCHITECTURE.md`) and it's three
lines: get the most recent heartbeat per forwarder, keep only the ones older than
15 minutes. If you can explain why `summarize ... by Computer` runs before the
`where`, and what happens to a `Computer` that's never sent a heartbeat at all
(hint: it won't appear — `Heartbeat` only has rows for hosts that have reported at
least once), you understand `summarize` correctly.

**Now the harder one** — `content/analytics-rules/dovetail-new-local-admin.json`:
```kql
let created = SecurityEvent | where EventID == 4720 | project CreatedTime = TimeGenerated, TargetAccount, Computer;
let added   = SecurityEvent | where EventID == 4732 | where TargetAccount has "Admin" or GroupName has "Admin" | project AddedTime = TimeGenerated, MemberName, Computer;
created
| join kind=inner (added) on Computer
| where AddedTime between (CreatedTime .. 1h)
| join kind=leftanti (_GetWatchlist("approved-admins") | project TargetAccount = tostring(column_ifexists("account", ""))) on TargetAccount
| project TimeGenerated = AddedTime, TargetAccount, Computer
```
Trace it: two `let` sub-queries (account-created events, account-added-to-admin-
group events) joined on `Computer` where the "added" event happened within an hour
of the "created" event on the *same host* — that's the persistence pattern. Then
`join kind=leftanti` against the `approved-admins` watchlist: **leftanti keeps only
rows from the left side that have no match on the right** — i.e., this rule only
fires for accounts *not* already on the approved list. This is exactly why SOP-5
(`02-soc-sops.md`) exists: if `approved-admins` is stale, this rule can either miss
a real new admin (false negative, if the watchlist wrongly still lists someone) or
fire noisily (false positive, if it's missing someone who legitimately should be
there). `_GetWatchlist()` is the function that pulls a Sentinel watchlist into a
query — you'll use it constantly once you're writing rules at Tier 2.

**Practice, don't just read:** in the Sentinel Logs blade against the `dev`
enclave, run each query above yourself, then modify one clause (e.g. change `15m`
to `5m` in the heartbeat query, or the `1h` join window in the admin rule) and
predict the result before you run it.

---

## 3. Domain 1 — Manage a security operations environment

**What the exam tests:** configuring Microsoft Sentinel workspace settings, data
connectors, RBAC, watchlists, and threat indicators; configuring settings in
Microsoft Defender XDR.

**What you do at Tier 1, hands-on today:**
- **Workspace navigation.** Know the workspace naming convention
  (`law-dc-<enclave>-prod`) and why it matters — it's the only signal in the
  multi-workspace queue telling you which client's incident you're looking at
  (SOP-4, check #1).
- **RBAC — know your own access model.** You hold **Sentinel Reader**,
  permanently, via Lighthouse delegation from the **SOC Analysts** Entra group
  (`01-mssp-architecture.md` §3). Anything requiring **Responder** (changing an
  incident's status/owner) requires a PIM activation — MFA, reason field, max 8
  hours (`PT8H`), logged in the *client's* tenant, not Dovetail's. Do the full
  Module 1 hands-on in `03-training-guide.md` (activate, watch it expire, find
  your own activation in the client-side audit log) before you touch a real
  incident.
- **Data connectors — know what's actually feeding your workspace.** Per enclave
  `profile`:
  - `ot` profile: FortiGate CEF/Syslog (OT boundary firewall), Defender for IoT
    (OT sensor alerts), optionally Defender for Endpoint (IT-tier hosts).
  - `it` profile: Defender for Endpoint only (today — see `01` §4 for what's
    planned but not live).
  You don't configure these at Tier 1, but you must be able to say, for any
  incident, *which connector produced this data* — it's the first thing that
  explains why a query returned nothing (wrong table, connector not enabled for
  this enclave) versus a genuine true-negative.
- **Watchlists.** `critical-assets` and `approved-admins` — three analytics rules
  join against them (SOP-5). Know how to look one up in the Sentinel Watchlist
  blade during triage; you are not yet the one editing them (that's a PR against
  `content/`, Tier 2/Engineer work), but a triage call frequently depends on
  whether a host or account is on one.

**Exam-only, not yet Tier 1 operational** (you'll meet this in Tier 2 or the
roadmap in §7): workspace-level data retention/cost tuning, Data Collection Rule
(DCR) authoring, Sentinel Repositories connection setup, Microsoft Defender XDR
unified portal settings (`security.microsoft.com`) beyond what maps 1:1 to
Sentinel. Study these conceptually via Microsoft Learn's *SC-200: Configure your
Microsoft Sentinel environment* module — know the vocabulary for the exam even
though you won't touch these controls day one.

---

## 4. Domain 2 — Configure protections and detections

**What the exam tests:** configuring protections in Microsoft Defender products
(Endpoint, Office 365, Identity, Cloud Apps) and Microsoft Defender for Cloud;
configuring Sentinel analytics rules, automation rules, UEBA, and threat
intelligence.

**What you do at Tier 1, hands-on today — read and recognize, not yet author:**

Know all 8 analytics rules cold (severity, what fires it, entity mappings, MITRE
tactic/technique tags — every rule in `content/` carries both):

| Rule | Severity | Fires on | MITRE tactic |
|---|---|---|---|
| Forwarder heartbeat loss | High | No heartbeat from a forwarder in 15 min | Defense Evasion (T1562) |
| FortiGate admin auth failures | High | Repeated failed admin logins, OT boundary firewall | — |
| New local admin on critical asset | High | 4720+4732 within 1h, same host, not on `approved-admins` | Persistence / Privilege Escalation (T1136, T1078) |
| D4IoT critical (via connector) | High | Defender for IoT high-severity alert | — |
| FortiGate config change | Medium | Any config change, OT boundary firewall | — |
| Windows brute force | Medium | 4625 failure burst | — |
| OT telemetry silence (per device) | Medium | One OT source quiet, pipeline otherwise healthy | — |
| After-hours critical access | Low | Interactive logon to a critical asset outside 06:00-20:00 | — |

Also know the **2 automation rules** (auto-floor OT-tagged incidents to High,
auto-close Informational with classification recorded) and how they change what
you see in the queue before you ever open an incident — an automation rule that
already floored severity is *why* something you'd expect Medium shows as High.

**Read one full rule JSON end to end** (`dovetail-baseline-forwarder-heartbeat-loss.json`
is short — use it) and identify: `severity`, `query`, `queryFrequency`/
`queryPeriod` (how often it runs, over what lookback), `triggerOperator`/
`triggerThreshold` (when it fires), `suppressionDuration`, `tactics`/`techniques`
(MITRE ATT&CK mapping — this is exam-tested directly), `entityMappings` (what
becomes a clickable entity in the incident), `incidentConfiguration.groupingConfiguration`
(why related alerts land in one incident instead of ten).

**Exam-only, not yet Dovetail-operational** — flagged clearly, see §7 for the full
picture: UEBA, Fusion/ML-based detections, threat intelligence feed (TI) indicator
matching, Microsoft Defender for Office 365 protections (Safe Links/Attachments),
Defender for Identity protections, Defender for Cloud Apps (MDCA) protections,
Defender for Cloud (CSPM/workload protection). None of these run in Dovetail's
factory today. Study them via Microsoft Learn's *SC-200: Mitigate threats using
Microsoft Defender for Office 365 / Defender for Identity / Defender for Cloud
Apps* modules.

---

## 5. Domain 3 — Manage incident response

**This is your actual job at Tier 1, more than any other domain.**

**What the exam tests:** investigating and remediating incidents/alerts in both
Microsoft Sentinel and Microsoft Defender XDR.

**What you do, hands-on, every shift:**
1. **Read `docs/SOC-OPERATIONS.md` first, every shift** — SLAs, daily/weekly
   routine, the three High-severity triage guides. This is non-negotiable, listed
   first in `03-training-guide.md` for a reason.
2. **SOP-4, before touching any incident** (`02-soc-sops.md`): confirm the
   workspace/enclave, confirm your PIM elevation is scoped to *that* enclave (not
   a stale one from a prior incident), never cross-pollinate details between
   enclaves — including your own notes.
3. **Classification discipline.** "Probably maintenance" is not an accepted
   closure reason without a human confirmation in writing (see Scenario C in §8
   below, and `03-training-guide.md` Module 5). An incident with no matching
   change-calendar entry and no watchlist match **stays open**.
4. **Escalation.** Anything outside a documented triage guide, anything requiring
   Responder+ action you're not yet cleared for, and anything that might require
   client notification goes to Tier 2 or Jay/Divyash per the RACI in
   `05-escalation-matrix.md`. Escalating correctly and promptly is a Tier 1
   competency, not a failure to solve it yourself.
5. **Evidence and closure.** Follow `SOC-OPERATIONS.md`'s evidence-handling and
   closure procedure — every closure needs a stated reason and supporting
   evidence, referenced in Template 3 of `05-escalation-matrix.md`.

**Exam-only, not yet Tier 1 operational:** the unified Microsoft Defender XDR
incident queue (`security.microsoft.com`) that correlates Sentinel with Endpoint/
Identity/Office 365/Cloud Apps alerts into one incident — Dovetail's factory
doesn't run the products that populate that correlation today (§7). Automated
investigation and remediation (AIR) in Defender for Endpoint is a related exam
topic worth knowing conceptually even though Dovetail's MDE connector today only
promotes MDE alerts into Sentinel incidents, it doesn't yet expose AIR workflows to
Dovetail's SOC.

---

## 6. Domain 4 — Perform threat hunting (introductory depth)

**What the exam tests:** KQL-based hunting in Sentinel and Defender XDR, hunting
queries, notebooks, workbooks, livestream, bookmarks.

**What you do at Tier 1:** run the **3 existing hunting queries** weekly per the
`SOC-OPERATIONS.md` routine — they don't create incidents on their own, a human
reviews the results:

- `dovetail-hunt-auth-outside-pattern.json` — accounts authenticating to hosts they
  haven't touched in 14 days (lateral-movement baseline). Read its query: two
  `let` blocks, a `leftanti` join against the 14-day baseline, `summarize` for
  first-seen + count. Same join pattern as the new-local-admin rule — recognizing
  reused patterns across `content/` is a real skill, not a coincidence.
- `dovetail-hunt-new-ot-talker.json` — new OT network talker (`profiles/ot`).
- `dovetail-hunt-rare-outbound-ot.json` — rare outbound OT traffic (`profiles/ot`).

Also know the **Dovetail SOC Overview workbook** — pipeline health and ingestion
volume sit at the top deliberately (Module 4, `03-training-guide.md`: in a diode
architecture, that panel *is* the first line of detection). Practice reading it
before you practice hunting with it.

**Exam-only, not yet Tier 1 operational (Tier 2 territory, see `07-training-tier2.md`):**
writing new hunting queries, Jupyter notebooks in Sentinel, livestream, converting
a bookmark into an incident. Know these exist and roughly what they're for; you'll
build fluency at Tier 2.

---

## 7. The full unified Microsoft security suite — what's live vs. exam-only

SC-200 assumes a Microsoft Defender XDR customer running the full suite:
**Defender for Endpoint, Defender for Office 365, Defender for Identity, Defender
for Cloud Apps**, plus **Defender for Cloud** and the unified incident portal.
Dovetail's factory runs a **subset** today. Be precise about the line — don't ever
represent exam-only knowledge as something you've operated, the same discipline
`04-playbooks.md` and `01-mssp-architecture.md` §9 apply to design-target features.

| Product | Live in Dovetail's factory? | Where | Study for the exam via |
|---|---|---|---|
| Microsoft Sentinel | **Yes** | Every enclave (`modules/workspace.bicep`, `modules/ingestion.bicep`) | Hands-on — this is most of your job |
| Defender for IoT | **Yes**, `ot` profile only | `modules/connectors.bicep` (`defenderForIotSubscriptionId`) | Hands-on on OT-profile enclaves |
| Defender for Endpoint | **Yes**, when `enableMde=true` | `modules/connectors.bicep` | Hands-on where enabled |
| Microsoft Defender for Cloud (CSPM) | **Yes, `dev`/`demo` only**, Free tier | `main.bicep` (`enableXdrTraining`, `Microsoft.Security/pricings`) | Hands-on on `dev`/`demo`; Secure Score, recommendations, regulatory compliance dashboard are all live at Free tier |
| Entra ID Identity Protection alerts | **Yes, `dev`/`demo` only** | `modules/connectors.bicep` (`enableXdrTraining`, kind `AzureActiveDirectory`) | Hands-on on `dev`/`demo` — real alerts, depth scales with Entra P1/P2 licensing |
| Microsoft Defender for Identity | **No** — connector resource exists but is off (`enableDefenderForIdentityConnector=false` everywhere) | `modules/connectors.bicep` | MS Learn: *Mitigate threats using Microsoft Defender for Identity*. Blocked on a real MDI sensor next to a Domain Controller — nobody's installed one yet |
| Microsoft Defender for Cloud Apps | **No** — connector resource exists but is off (`enableDefenderForCloudAppsConnector=false` everywhere) | `modules/connectors.bicep` | MS Learn: *Mitigate threats using Microsoft Defender for Cloud Apps*. Blocked on the product being licensed/onboarded at a client tenant |
| Microsoft Defender for Office 365 | **No** | — | MS Learn: *Mitigate threats using Microsoft Defender for Office 365*. Modern onboarding path is the unified Microsoft Defender XDR connector, not a standalone Sentinel connector — nothing to deploy here yet |
| Unified Defender XDR portal correlation | **Partial** — MDE/D4IoT/Entra alerts promote *into Sentinel*, not the other direction | — | MS Learn: *Mitigate incidents using Microsoft 365 Defender* |

**This gap is a real, tracked initiative, not just a study problem** — the
Defender for Cloud and Entra ID Identity Protection rows above went live in
`dev`/`demo` on 2026-07-16 specifically so Tier 1/2 get hands-on practice instead
of exam-only theory. The two "No" rows with a connector resource already sitting
in `modules/connectors.bicep` (Defender for Identity, Defender for Cloud Apps) are
deliberately not just theory either — they're wired and ready, just switched off
because deploying the connector alone would produce zero alerts without a real MDI
sensor or MCAS onboarding behind it, which would be worse than not deploying it
(a trainee could mistake "connected, no data" for "verified working"). Microsoft
Defender for Office 365 has no connector to wire yet because its modern onboarding
path is the unified Microsoft Defender XDR connector rather than a
per-product Sentinel connector. Don't claim hands-on experience with a product
you've only read about — check `enableXdrTraining`/`enableDefenderForIdentityConnector`/
`enableDefenderForCloudAppsConnector` in your enclave's `.bicepparam` file if
you're unsure what's actually live.

---

## 8. Hands-on labs (run these against `dev` or `demo`, not `lec`)

Run all three tabletop scenarios from `03-training-guide.md` Module 5 first
(forwarder heartbeat loss, FortiGate escalation, new local admin with no
change-calendar match) — they are the foundation for everything below.

**Lab 1 — KQL drill.** In the Sentinel Logs blade, run the heartbeat-loss query
and the new-local-admin query verbatim. Then: change the heartbeat threshold from
`15m` to `5m` and explain what changes about the rule's false-positive rate.
Change the admin-rule join window from `1h` to `4h` and explain what class of
attack that would newly catch (slower manual persistence) versus what noise it
might add.

**Lab 2 — Full incident lifecycle.** Inject the test CEF event per
`docs/DEPLOY-INITIAL-ENVIRONMENT.md` Phase 9A against `dev`. Watch the incident
appear, apply SOP-4's isolation check, classify it, write a closure note per
`SOC-OPERATIONS.md`'s evidence standard.

**Lab 3 — Escalation practice.** Given a hypothetical incident that doesn't match
any documented triage guide, draft the escalation message you'd send to Tier 2 /
Jay-Divyash per the RACI in `05-escalation-matrix.md`. Have a Tier 2 analyst
critique it — the skill being tested is *recognizing you're outside the documented
playbook quickly*, not solving the incident alone.

---

## 9. Study schedule (suggested, 6 weeks to exam-ready)

| Week | Focus |
|---|---|
| 1 | `01-mssp-architecture.md` full read + Module 0-1 of `03-training-guide.md` (Lighthouse, PIM, hands-on) |
| 2 | This guide §2-3 (KQL fundamentals, Domain 1) + run Lab 1 |
| 3 | This guide §4-5 (Domains 2-3) + shadow a real triage shift |
| 4 | This guide §6 (Domain 4) + run Labs 2-3 |
| 5 | §7 gap-study via Microsoft Learn (Defender for Office 365/Identity/Cloud Apps/Cloud modules) |
| 6 | Full practice exam (Microsoft Learn or MeasureUp), review weak domains, schedule the real exam |

---

## 10. Practice questions (original, exam-style — not real exam content)

Work these without looking back at the guide first, then check yourself.

1. A Sentinel analytics rule uses `join kind=leftanti`. What does this join return?
   *(Answer: only rows from the left table that have **no** matching row in the
   right table — used in `dovetail-new-local-admin.json` to keep only accounts
   *not* on the `approved-admins` watchlist.)*
2. An incident fires from the forwarder-heartbeat-loss rule. Base-rate cause in a
   diode architecture is usually what, and why should you not default to
   "attack"? *(Answer: uplink outage — most environmental causes are more common
   than tamper; still treat it as an availability incident pending confirmation,
   per Module 4 of `03-training-guide.md`.)*
3. What's the maximum PIM activation window for a Dovetail Responder role, and
   where is that activation logged? *(Answer: 8 hours (`PT8H`); logged in the
   **enclave's own tenant** audit log, visible to the client.)*
4. True or false: Dovetail's factory today runs Microsoft Defender for Identity.
   *(Answer: False — see §7. Don't represent it as live to a client or on your own
   resume until it is.)*
5. A new-local-admin incident has no watchlist match and no change-calendar entry.
   What's the correct classification action? *(Answer: leave it open; "probably
   maintenance" is not an accepted closure reason without written human
   confirmation.)*

---

## 11. Promotion checklist — Tier 1 sign-off

- [ ] Completed `03-training-guide.md`'s certification checklist in full.
- [ ] Can read and explain, unprompted, the KQL in all 8 analytics rules and all 3
      hunting queries.
- [ ] Has run all three tabletop scenarios and reached the correct triage call
      without prompting.
- [ ] Has completed Lab 1-3 above against `dev`/`demo`.
- [ ] Can state, without checking, which of the six SC-200-relevant Microsoft
      security products are live in Dovetail's factory today and which are
      exam-only (§7 table).
- [ ] SC-200 exam scheduled or passed.
- [ ] Ready for Tier 2 track — see `07-training-tier2.md`.
