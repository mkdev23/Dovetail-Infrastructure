# Dovetail SOC — Tier 2 Analyst Training & SC-200 Study Guide

**Status:** Production v1.0, 2026-07-16. Self-contained, exam-mapped, written for
an analyst who has already completed `06-training-tier1.md` (or equivalent Tier 1
experience) and holds or is close to holding **SC-200**. Where Tier 1's guide
covers *reading and recognizing* Dovetail's content and procedures, this guide
covers *authoring, tuning, and owning* them — the deeper half of every SC-200
domain, plus the operational authority (Engineer-tier PIM, content PRs, OT
judgment calls) that comes with it.

**Prerequisite assumption:** you can already read every query in `content/`
fluently (Tier 1 §2 KQL fundamentals). This guide does not re-teach `where`/
`summarize`/`join` — it teaches you to write the next rule.

---

## 0. What Tier 2 is

Tier 2 **authors and tunes** detection content, **owns** threat hunting cadence,
**leads** incident investigation and response beyond documented triage guides,
**executes** enclave lifecycle procedures (onboarding/handoff/offboarding —
`02-soc-sops.md` SOP-1/2/3), **mentors and signs off** Tier 1 trainees, and is the
escalation point before Jay/Divyash. Tier 2 is PIM-eligible for **Responder** and
**Engineer** (Sentinel Contributor) roles per `01-mssp-architecture.md` §3 —
Engineer-tier access is what lets you actually deploy content and connector
changes, not just investigate.

The line that matters most: Tier 2 carries the **IEC 62443-2-4 judgment calls** —
whether something crosses the OT hard gate ("client operations approves, Dovetail
advises"), whether a client notification is warranted, whether an offboarding is
authorized. Tier 1 escalates into these decisions; Tier 2 owns making them (with
Jay/Divyash as the next escalation tier, not a rubber stamp you skip).

---

## 1. SC-200 exam overview (same exam, deeper target)

Same exam as Tier 1's guide (`06-training-tier1.md` §1) — domains, weights, format,
registration, renewal are identical, repeated here only where the depth differs.
**The bar for Tier 2 is not just passing — it's being able to explain *why* an
answer is correct well enough to teach it to a Tier 1 trainee.** If you can't
justify a KQL clause or a Defender product's config option out loud, you don't
know it well enough yet, exam pass or not.

Tier 2 should specifically deepen: Domain 2 (you'll *author* analytics rules,
automation rules, and eventually playbooks — the exam tests configuring these, you
should be able to build them from scratch), and Domain 4 (you *own* the hunting
cadence and will write new hunting queries, not just run existing ones).

---

## 2. Advanced KQL

Beyond Tier 1's fundamentals, you need these for content authoring and hunting at
scale:

| Construct | Use | Where you'll need it |
|---|---|---|
| `_GetWatchlist("name")` | Pulls a Sentinel watchlist into a query as a table | Every rule joining against `critical-assets`/`approved-admins` — see `dovetail-new-local-admin.json` |
| `column_ifexists("col", default)` | Defensive column reference — avoids a hard failure if a watchlist's schema shifts | Same rule: `tostring(column_ifexists("account", ""))` |
| `mv-expand` | Un-nests a dynamic/array column into multiple rows | You'll need this the first time you parse a CEF field with multiple values |
| `materialize()` | Caches a sub-query result reused multiple times in one query | Performance — avoid recomputing an expensive `let` block twice |
| `externaldata()` | Pulls data from outside the workspace (e.g. a blob) | Rarely needed here; know it exists for the exam |
| `union isfuzzy=true` | Unions tables that may not all exist in every workspace, without hard-failing | **Required** pattern per `CLAUDE.md` §3 for any IT-profile rule — an enclave may not have every connector, guard for it |
| `bin()` | Buckets time into fixed intervals | Workbook time-series panels |
| `render` | Chart-rendering hint for the portal (timechart, barchart, etc.) | Workbook authoring |

**Cross-workspace queries** (exam topic, not yet a Dovetail need): Sentinel can
query across workspaces with explicit `workspace("name").TableName` syntax *if*
the querying identity has access to both. Dovetail's tenant-per-enclave isolation
model deliberately does not do this — the multi-workspace **incident** queue
aggregates incidents, but nothing in the factory runs a query that spans two
enclaves' log data, and nothing should (that would undermine Option A isolation).
Know the syntax for the exam; never propose using it against two client enclaves.

---

## 3. Domain 1, advanced — environment engineering

**Data Collection Rules (DCRs).** `modules/ingestion.bicep` defines three per
enclave — know why each is shaped the way it is, because you'll be the one asked
to add a fourth:
- **`dcr-dc-<enclave>-winsec`** — curated Windows Security Event IDs via an XPath
  filter (auth, privilege, persistence, lateral-movement — 4624/4625/4720/4732/
  etc.). Deliberately *not* `Security!*` — the comment in the file is explicit:
  "never fall back to `Security!*`." Know why: unfiltered Security log ingestion
  is expensive and mostly noise; the curated list is what the analytics rules
  actually consume.
- **`dcr-dc-<enclave>-syslog`** — Warning-and-above only for general facilities,
  full level range for `auth`/`authpriv`. Cost/signal tradeoff, tunable per
  client.
- **`dcr-dc-<enclave>-cef`** — CEF from the forwarder, with a `transformKql` that
  drops allowed intra-zone traffic before it crosses the uplink
  (`where not(DeviceAction =~ "allow" and LogSeverity in ("0","1","2"))`). This
  transform runs **at the Data Collection Endpoint**, before the Monrovia uplink —
  filtering at collection time, not after ingestion, is a standing architectural
  decision (`modules/ingestion.bicep` header comment) driven by uplink cost and
  capacity. If you're ever asked to add ingestion for a new source, this is the
  pattern: curate at the DCR, don't ingest everything and filter in KQL later.

**RBAC engineering.** `modules/rbac.bicep` is what grants a *client's own* staff
(not Dovetail) Sentinel Reader (or Responder) scoped to their own resource group
only — the built-in role GUID is swappable (`8d289c81-...` Reader vs.
`3e150937-...` Responder). Understand this is the mirror image of Dovetail's own
Lighthouse-delegated access (`01-mssp-architecture.md` §3): both directions use
narrowly-scoped RBAC, no standing broad access anywhere.

**Content delivery pipeline.** Today (2026-07-16), `content/` is flat and every
enclave's Sentinel Repositories connection pulls all of it. A restructure into
`baseline/` + `profiles/{ot,it}/` + `verticals/{health,utility}/`, driven by a
`contentPacks` param, is specified in this repo's `CLAUDE.md` but **not yet
implemented** — know this is in flight, and if you're the Tier 2 engineer who
picks it up, that document is your spec.

**Watchlist lifecycle — you own SOP-5.** Weekly diff, PR against `content/`
(never a console edit — it won't propagate and is lost on redeploy), then
`./scripts/deploy-watchlists.ps1` per affected enclave. You're also the one who
explains to a Tier 1 analyst *why* a rule went silently blind (stale watchlist,
no error surfaced) rather than just fixing it.

---

## 4. Domain 2, advanced — authoring detections

**Anatomy of a scheduled analytics rule** — walk `dovetail-new-local-admin.json`
as your template for writing a new one:

```json
{
  "kind": "Scheduled",
  "properties": {
    "displayName": "...",
    "description": "...",
    "severity": "High",
    "query": "<KQL>",
    "queryFrequency": "PT1H",
    "queryPeriod": "PT2H",
    "triggerOperator": "GreaterThan",
    "triggerThreshold": 0,
    "suppressionDuration": "PT1H",
    "suppressionEnabled": false,
    "tactics": ["Persistence", "PrivilegeEscalation"],
    "techniques": ["T1136", "T1078"],
    "entityMappings": [ ... ],
    "incidentConfiguration": {
      "createIncident": true,
      "groupingConfiguration": {
        "enabled": true,
        "reopenClosedIncident": false,
        "lookbackDuration": "PT5H",
        "matchingMethod": "AllEntities"
      }
    }
  }
}
```

Every field is a design decision, not boilerplate:
- **`queryFrequency` vs `queryPeriod`** — how often the rule runs vs. how far back
  each run looks. `PT1H`/`PT2H` means it runs hourly but looks back 2 hours —
  deliberate overlap so a slow-to-land event near a run boundary isn't missed.
- **`tactics`/`techniques`** — MITRE ATT&CK mapping, tested directly on the exam
  and operationally useful: it's how an analyst (or a client's security review)
  understands what class of behavior a rule defends against, independent of its
  specific KQL.
- **`entityMappings`** — what becomes a clickable, correlatable entity
  (`Account`, `Host`, `IP`, etc.) in the resulting incident. Get this wrong and
  the incident's investigation graph is useless even if the query logic is
  perfect.
- **`groupingConfiguration`** — `matchingMethod: AllEntities` with a 5-hour
  lookback means alerts sharing *all* mapped entities within 5 hours group into
  one incident instead of flooding the queue with duplicates.

**Where a new rule belongs** — this is a live, real decision now that the
`CLAUDE.md` restructure is in flight: ask *"would this fire usefully in an
environment with no OT and no unusual connectors?"* If yes, `baseline/`. If it
depends on FortiGate/D4IoT/SCADA/CEF specifics, `profiles/ot/`. Use
`union isfuzzy=true` or existence checks for anything IT-profile that touches a
table an enclave might not have (`CLAUDE.md` §3) — this is the practical
application of the `union isfuzzy=true` construct from §2 above.

**Automation rules.** `dovetail-tag-ot-incidents.json` is your template: a
`triggeringLogic` condition (title contains OT/IoT/SCADA/FortiGate) plus ordered
`actions` (add labels, then floor severity to High). Two things worth internalizing
by reading it: `order` matters (actions apply in sequence — labels are applied
before the severity floor here, though order is largely cosmetic for this specific
pair), and this automation rule is *why* an OT-tagged incident a Tier 1 analyst
sees is already High even if the underlying analytics rule's default severity was
lower — know this before you ever question why an incident's severity doesn't
match the rule that fired it.

**Playbooks (Logic Apps).** `pb-dc-<enclave>-notify` is the one deployed
notification playbook today (`04-playbooks.md`). Building a new playbook is
Engineer-tier work — you'll need Logic Apps fundamentals (triggers, the Sentinel
incident trigger payload shape, actions, conditions) which the exam covers under
Domain 2/3's SOAR content. Not deeply built out in Dovetail's factory yet beyond
notification — a real growth area if you want to pick up scope.

**Exam-only, not yet Dovetail-operational — you're the one who'd build it:**
- **UEBA** (User and Entity Behavior Analytics) — Sentinel feature, not yet
  enabled in any enclave. Know it conceptually (baselines normal behavior per
  entity, flags anomalies) for the exam.
- **Fusion / ML-based detections** — Sentinel's built-in multi-stage-attack
  correlation. Not yet tuned/relied on here.
- **Threat Intelligence (TI) indicator matching** — Dovetail's current substitute
  for a TI feed is its watchlists (`critical-assets`, `approved-admins`), which
  are asset/identity lists, not IOC feeds. A real STIX/TAXII TI connector feeding
  `ThreatIntelligenceIndicator` and a TI-matching analytics rule is exam-tested
  and not yet built here.
- **Defender for Office 365 / Identity / Cloud Apps protections** — see §7 in
  `06-training-tier1.md`, not repeated here; you're the tier likely to scope
  adding these (see the roadmap note there).

---

## 5. Domain 3, advanced — incident leadership

Beyond Tier 1's isolation-check-and-escalate discipline, Tier 2 **leads**:

- **Investigation depth.** Use the Sentinel investigation graph to correlate
  entities across an incident's alerts — this is where `entityMappings` quality
  (§4) directly determines whether investigation is fast or manual grep-through.
- **The AI-agent-mapped design (`04-playbooks.md`).** SentinelSleuth, TriageForge,
  ResponseWarden, ContinuityMarshal are **design target, not deployed** (GOALS.md
  M3/M4, NOT STARTED as of 2026-07-16) — but the document maps *exactly* the
  investigation/triage/response/recovery judgment calls Tier 2 makes manually
  today. Read it as a description of your own current judgment process, formalized
  — and know the **OT hard gate** it encodes (agent proposes, never executes
  containment on OT assets) is the same authority limit you personally operate
  under today, IEC 62443-2-4, not a future AI-safety feature.
- **SOP-1/2/3 execution.** You run enclave onboarding (verify the Lighthouse
  registration lands in both directions — it fails silently on a bad Entra group
  ID), handoff (remove Dovetail's direct Owner role — from that point access is
  Lighthouse-only, no exceptions), and — once it's been rehearsed — offboarding
  (export evidence per ISO/IEC 27037 principles, revoke the
  `registrationAssignments` resource, confirm removal in both verification
  blades). SOP-3 is explicitly **unrehearsed** as of this writing — if you're
  asked to close that gap, do it against a disposable dev/demo enclave first, the
  same discipline that validated onboarding.
- **Client communication.** You draft (Jay/Divyash still make the "does this need
  to go beyond the OT/IT lead" call, per the RACI) using Templates 1-4 in
  `05-escalation-matrix.md`. The one line that overrides everything: for anything
  that could affect OT generation or distribution, **client operations approves,
  Dovetail advises** — you never initiate that class of action unilaterally, full
  stop, regardless of how confident the investigation is.

---

## 6. Domain 4, advanced — owning the hunt

**Writing a new hunting query** — `dovetail-hunt-auth-outside-pattern.json` is
your template. Structurally simpler than an analytics rule (no severity, no
incident creation, no entity mappings) — it's a saved search under category
`"Hunting Queries"`, with a `description` and `tactics` tag for documentation.
The judgment call is entirely in the query design: a 14-day rolling baseline via
`leftanti` join is the pattern here; know when a baseline window is too short
(noisy, high false positive during commissioning — flagged explicitly in the
file's own description) versus too long (stale, misses genuine drift in normal
behavior).

**Notebooks** (Jupyter, via Sentinel) — exam topic, not used in Dovetail's factory
today. Useful for hunts requiring more than KQL alone (e.g., pulling external
enrichment, statistical analysis beyond what `summarize`/`render` do well). A
reasonable Tier 2 growth area if a hunt outgrows plain KQL.

**Workbook authoring.** The SOC Overview workbook (`content/workbooks/` today,
splitting into `baseline/`+`profiles/ot/`+`verticals/*` per `CLAUDE.md`) is an ARM
template with a `serializedData` blob describing panels — pipeline health and
ingestion volume placed first, deliberately (Module 4, `03-training-guide.md`).
If you're building the health or utility vertical workbook per `CLAUDE.md` §3/§3a,
this is your starting structure: same neutral bones, different title and panel
selection for the audience.

**Livestream** — exam topic (near-real-time query results without waiting for a
scheduled rule's `queryFrequency`). Not a standing Dovetail workflow but useful
during active investigation of something time-sensitive.

**Bookmarks → incidents.** During a hunt, a bookmarked result can be promoted
directly into an incident. Know the workflow for the exam and use it operationally
the first time a hunting query surfaces something that warrants a full incident
rather than a note in the weekly review.

---

## 7. Closing the full-suite gap — status and your role in what's left

`06-training-tier1.md` §7 has the current live-vs-exam-only table. As of
2026-07-16, two rows moved from "exam-only" to "live, `dev`/`demo` only" per a
direct scoping decision with Jay — know exactly what shipped and why the rest is
still gated, because you're the tier that will pick up closing what's left.

**What's live now (`dev`/`demo` only, `enableXdrTraining=true`):**
- **Defender for Cloud (CSPM), Free tier** — `main.bicep`, a subscription-scoped
  `Microsoft.Security/pricings` resource named `'CloudPosture'`. Free tier costs
  nothing and already exposes Secure Score, recommendations, and the regulatory
  compliance dashboard — the exam-tested surface. It's declared as a singleton
  per subscription, which is why it's deployed once in `main.bicep` rather than
  per-enclave in `modules/connectors.bicep`: multiple enclaves sharing one
  subscription (the three planned demo enclaves in `CLAUDE.md` §4) each
  redeclaring the same resource name converges safely rather than conflicting —
  know this pattern before you assume every Azure resource needs per-enclave
  isolation the way workspaces and DCRs do.
- **Entra ID Identity Protection connector** (`modules/connectors.bicep`, kind
  `AzureActiveDirectory`) + its `MicrosoftSecurityIncidentCreation` promotion
  rule (`productFilter: 'Azure Active Directory Identity Protection'`). This is
  a real, working connector on any Entra tier — not a placeholder. It's also the
  data source the planned IT-profile analytics rules (`CLAUDE.md` §3 —
  impossible-travel, MFA-disabled-on-privileged-account) are meant to run
  against once that content pack is built.

**What's wired but deliberately off everywhere (`enableDefenderForIdentityConnector`,
`enableDefenderForCloudAppsConnector`, both `false`):** the connector resources
for Defender for Identity (kind `AzureAdvancedThreatProtection`) and Defender for
Cloud Apps (kind `MicrosoftCloudAppSecurity`) exist in `modules/connectors.bicep`,
each with its own promotion rule, ready to flip on — but deploying a connector
without the underlying product actually provisioned produces a connector that
shows "connected" with zero alerts ever flowing, which is worse for training than
not deploying it at all (a trainee could mistake "connected" for "verified
working"). Real prerequisites, unresolved as of this writing:
- **Defender for Identity** needs a sensor installed on-prem next to Active
  Directory Domain Controllers. Flag explicitly: an OT enclave like `lec` may not
  expose AD in a way that makes this straightforward, and the physical-
  forwarder/diode architecture (`docs/LEC-REFERENCE-ARCHITECTURE.md`) wasn't
  designed around an on-prem sensor's outbound connectivity needs — a real design
  question, not just a deployment step, and one reason this factory-wide decision
  scoped to `dev`/`demo` only rather than `lec`.
- **Defender for Cloud Apps** needs Conditional Access App Control policies and
  OAuth app connectors configured at the client's Entra tenant — most relevant to
  IT-profile enclaves (a ministry with SaaS exposure), largely irrelevant to a
  pure OT boundary.

**What has no connector to wire at all yet: Microsoft Defender for Office 365.**
Verified against the current `Microsoft.SecurityInsights/dataConnectors@2024-03-01`
schema: there is no standalone "Defender for Office 365 alerts" connector kind in
the current API (the old `OfficeATP` kind that once existed has been superseded).
Microsoft's modern onboarding path for MDO is the **unified Microsoft Defender
XDR connector** (tenant-level, via the unified security operations platform,
`security.microsoft.com`) rather than a per-product Sentinel-native connector —
this is also the direction Sentinel itself is heading (Microsoft has stated
Sentinel-in-Azure-portal support ends March 31, 2027, moving fully into the
Defender portal). If you're the one scoping MDO next, research the unified
connector's current onboarding requirements before assuming a `kind:` value
exists to add to `modules/connectors.bicep` the way the others did — this is
exactly the kind of claim to verify against current Microsoft Learn docs rather
than pattern-match from the older connectors, the same discipline this whole
suite applies to regulatory citations (`01-mssp-architecture.md` §8).

**If you're picking up the next piece of this** (Defender for Identity sensor
placement, Defender for Cloud Apps onboarding, or scoping the MDO/unified-XDR
path): bring the specific prerequisite and its cost/licensing implication to Jay
before touching `modules/` or flipping any of these flags to `true` on a new
enclave — the `dev`/`demo`-only scope was a deliberate decision, not a default to
quietly expand.

---

## 8. Hands-on labs

**Lab 1 — Author a rule end to end.** Pick a plausible new detection (e.g.,
"service account interactive logon" — a real, common finding). Write the KQL
against `dev`, build the full rule JSON using `dovetail-new-local-admin.json`'s
structure as a template (severity, tactics/techniques, entity mappings, grouping),
open a PR against `content/`, and walk it through review — including stating
whether it belongs in `baseline/` or a `profiles/` pack per the test in §4.

**Lab 2 — Own an incident as IC.** Run Scenario B from `03-training-guide.md`
Module 5 (FortiGate escalation) as incident commander with a Tier 1 analyst
shadowing you. Narrate your reasoning out loud at each decision point — that's
the actual skill being built, for both of you.

**Lab 3 — Rehearse SOP-3.** Against a disposable dev/demo enclave (never a real
client), run the full offboarding procedure once. Note anything that doesn't work
as written and update `02-soc-sops.md` SOP-3 accordingly — it's explicitly marked
unrehearsed today.

---

## 9. Study schedule (suggested, 4 weeks — assumes Tier 1 depth already solid)

| Week | Focus |
|---|---|
| 1 | This guide §2-3 (advanced KQL, environment engineering) + Lab 1 |
| 2 | §4 (authoring detections) — write and PR a real rule |
| 3 | §5-6 (incident leadership, hunting) + Lab 2 |
| 4 | §7 gap analysis writeup + full practice exam + Lab 3 if scheduling allows |

---

## 10. Practice questions (original, exam-style — not real exam content)

1. Why does `dcr-dc-<enclave>-winsec` filter to a specific XPath event-ID list
   instead of ingesting the full Windows Security log? *(Answer: cost and
   signal-to-noise — the curated list is exactly what the analytics rules
   consume; the file's own comment states "never fall back to `Security!*`.")*
2. You're asked to add a new IT-profile analytics rule that queries `SigninLogs`.
   Why must the query guard with `union isfuzzy=true` or an existence check?
   *(Answer: not every enclave has every connector — an IT-profile enclave
   without Entra sign-in log ingestion enabled would otherwise hard-fail instead
   of just returning no results, per `CLAUDE.md` §3.)*
3. What determines whether a new analytics rule belongs in `baseline/` versus
   `profiles/ot/`? *(Answer: would it fire usefully in an environment with no OT
   and no unusual connectors — if yes, baseline; if it depends on
   FortiGate/D4IoT/SCADA/CEF specifics, profiles/ot.)*
4. Who has authority to approve an action affecting OT generation or distribution
   during incident response? *(Answer: client operations — Dovetail advises,
   never executes unilaterally; enforced technically via Sentinel Responder role
   scope and, per the design in `04-playbooks.md`, at the AI-agent layer too once
   built.)*
5. Name two real, non-hypothetical blockers to deploying Defender for Identity
   in the `lec` enclave specifically. *(Answer: needs an on-prem sensor next to
   AD Domain Controllers, and the diode/physical-forwarder architecture wasn't
   designed around an on-prem sensor's connectivity needs — both are open design
   questions, not just deployment steps.)*

---

## 11. Sign-off — ready to lead

- [ ] Has authored and merged at least one real analytics rule or hunting query PR.
- [ ] Has led (as IC) at least one live or tabletop incident with a Tier 1 analyst
      shadowing.
- [ ] Can explain the OT hard gate (IEC 62443-2-4) and apply it correctly under
      pressure, unprompted.
- [ ] Has read `04-playbooks.md` in full and can explain how it maps today's
      manual judgment calls to the planned agent design.
- [ ] Can walk through SOP-1 (onboarding) end to end from memory; has executed or
      shadowed SOP-2 (handoff) at least once.
- [ ] Can produce, unprompted, the §7 gap table (what's live vs. exam-only in the
      full Microsoft security suite) and speak to what closing each gap would
      actually require.
- [ ] SC-200 passed.
- [ ] Has signed off at least one Tier 1 trainee against `06-training-tier1.md`'s
      promotion checklist.
