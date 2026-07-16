# Dovetail SOC — Incident Response Playbooks (Agent-Mapped)

**Status:** Production v1.0 design spec, 2026-07-16. **Design target, not deployed
capability** — see below. Structured against **NIST CSF 2.0**'s six functions
(Govern, Identify, Protect, Detect, Respond, Recover) per **NIST SP 800-61 Rev. 3**
(final, April 2025): each category states what should already be true before an
alert fires (Govern/Identify/Protect) alongside what each agent does once one does
(Detect/Respond/Recover) — a playbook that only covers detect-and-respond isn't
following the current NIST guidance, which treats incident response as the whole
loop, not just the reactive half.
Today's automation is Sentinel-native only: two automation rules (OT severity floor
+ tagging, Informational auto-close) and one notification playbook
(`pb-dc-<enclave>-notify`) per GOALS.md and the `dovetail-infra` repo. The four AI
agents named below — SentinelSleuth, TriageForge, ResponseWarden, ContinuityMarshal
— are GOALS.md milestone M3/M4 (RTX 5080 PoC / RTX 6000 build), both **NOT STARTED**
as of 2026-07-16. This doc defines what each agent *will* do once built, mapped
against the real, currently-deployed alert categories — it is a design spec to build
toward, not a description of what runs today. Do not represent this as live capability
to a client.

Human-authored triage guides for the three High-severity rules already exist and are
authoritative: `dovetail-infra/docs/SOC-OPERATIONS.md`. Every agent behavior below is
designed to reach the *same conclusions* those guides direct a human analyst to reach
— the agents assist and accelerate triage, they don't override the documented
judgment calls (see the hard gate in every category below).

**Non-negotiable, all categories, all agents:** every agent run is instantiated
scoped to one workspace ID (one enclave), using credentials bound to that enclave's
Lighthouse delegation only. No agent run holds context, memory, or query access
spanning more than one enclave at a time. This is the AI-layer mirror of the
cross-tenant isolation check in `02-soc-sops.md` SOP-4 and ISO/IEC 27001 A.8.2
(privileged access rights, scope-verified) — it must hold even though no human is
in the loop for the investigation step.

**OT hard gate, standards basis:** the "propose, don't execute" limit on
ResponseWarden for anything OT-affecting isn't a Dovetail policy preference — it's
this design's implementation of the authority boundary **IEC 62443-2-4** requires
of an IACS service provider. An automated agent proposing containment and a human
at the client approving it is the human-in-the-loop control that standard expects;
an agent with autonomous OT-execution authority would not meet it.

---

## Alert categories (from the 8 live analytics rules)

| Category | Rules | Severity |
|---|---|---|
| **OT boundary / pipeline integrity** | Forwarder heartbeat loss, OT telemetry silence, FortiGate admin auth failures, FortiGate config change | High / High / High / Medium |
| **Identity & access** | New local admin on critical asset, Windows brute force, After-hours critical access | High / Medium / Low |
| **Asset integrity** | Service installed on critical asset | (severity per current rule config — treat as Medium/High pending confirmation) |

---

## Category: OT Boundary / Pipeline Integrity

**Govern / Identify / Protect (before an alert fires):** watchlist accuracy
(`critical-assets.csv`) is maintained per SOP-5; the change calendar this
category's agents cross-reference is a client-maintained artifact whose freshness
is itself a Protect-function gap if stale — flag to the client relationship owner
if it hasn't been touched in the maintenance-review cycle. Rsyslog buffer capacity
and diode TX-side health are Identify-function baseline facts ContinuityMarshal's
Recover-phase judgment (below) depends on knowing ahead of time, not discovering
mid-incident.

**SentinelSleuth (investigation) — CSF: Detect**
- On trigger, pull: last-known-good heartbeat timestamp, rsyslog disk-buffer state
  (if queryable via Arc/AMA telemetry), recent FortiGate config-change history,
  whether the workspace has *other* concurrent OT alerts (heartbeat loss + telemetry
  silence together is a stronger signal than either alone).
- Explicitly check: is this a known maintenance window? (Cross-reference the
  enclave's change calendar, same source SOC-OPERATIONS.md directs a human to.)
- Output: a structured context packet, not a verdict — heartbeat/silence incidents
  in a diode architecture require human confirmation via an out-of-band channel with
  the onsite contact (per the existing triage guide); SentinelSleuth cannot make that
  call, it prepares everything a human needs to make it fast.

**TriageForge (triage) — CSF: Detect**
- Applies the documented severity floor: anything OT-tagged is floored at High
  regardless of the rule's default severity — this mirrors the existing automation
  rule, TriageForge doesn't relax it.
- Classifies availability-vs-tamper based on SentinelSleuth's packet: uplink
  confirmed down externally → availability. Box down, uplink fine → flag as
  potential tamper, do not auto-classify as benign.

**ResponseWarden (response) — CSF: Respond**
- Authorized: draft the out-of-band confirmation request to the onsite contact,
  prep the FortiGate config snapshot command (do not execute), queue the
  notification per `05-escalation-matrix.md`.
- **Hard gate, no exception (IEC 62443-2-4):** any action that could affect OT
  generation, distribution, or the boundary firewall's live config requires
  **client operations approval** — ResponseWarden proposes, it does not execute
  containment on OT assets. This is the same "Dovetail advises, client operations
  approves" line from `SOC-OPERATIONS.md`, enforced at the agent layer, not just
  policy.

**ContinuityMarshal (DR/BC) — CSF: Recover**
- Engages specifically on confirmed pipeline-down (heartbeat loss where uplink is
  confirmed out, or diode/TX-side failure): tracks time-to-recovery against the
  8GB rsyslog buffer's drain capacity, flags if outage duration risks buffer
  overflow (data loss) before recovery, escalates urgency if so.

---

## Category: Identity & Access

**Govern / Identify / Protect (before an alert fires):** `approved-admins.csv`
currency is a Protect-function dependency for every rule in this category — SOP-5
governs its maintenance. Identity governance (who's authorized to *become* a local
admin, and the change-calendar process that legitimizes it) is a client-side
control Dovetail doesn't own; Identify-function work here is confirming that
process exists and is being followed, not substituting for it.

**SentinelSleuth (investigation) — CSF: Detect**
- New local admin: pulls the account's creation context, compares against
  `approved-admins` watchlist and change calendar (exactly the two checks the human
  triage guide requires).
- Brute force: pulls source IP reputation/geo, whether the same source has any
  history against other accounts/enclaves it could plausibly know about (bounded to
  this enclave's own log history — no cross-enclave lookups, see the non-negotiable
  above).
- After-hours access: pulls whether a matching maintenance window exists — this
  rule exists to be surfaced and confirmed, not auto-resolved.

**TriageForge (triage) — CSF: Detect**
- New local admin with no watchlist/calendar match: classification stays **open**,
  full stop — SentinelSleuth's packet cannot manufacture a closure justification
  TriageForge is allowed to accept. Matches the human SOP: "don't accept 'probably
  maintenance.'"
- After-hours access with a confirmed maintenance-window match: eligible for
  Low-confidence auto-classification, but always logged for the weekly Informational
  sample review (SOC-OPERATIONS.md weekly routine) — TriageForge doesn't get a
  silent pass any more than the existing automation rule does.

**ResponseWarden (response) — CSF: Respond**
- Authorized to draft a written confirmation request to the client for anything not
  auto-resolvable. Not authorized to disable accounts or force logoffs
  autonomously on any enclave — identity actions on a client's own admin accounts
  route through the same client-approval gate as OT containment (IEC 62443-2-4
  authority limits apply to identity actions on OT-tier assets same as network
  actions), until a specific, narrower authority is explicitly granted per-client.

**ContinuityMarshal (DR/BC) — CSF: Recover**
- Not typically engaged for this category, except: a confirmed-compromised admin
  account on a critical asset escalates to ContinuityMarshal if the asset's
  availability is now in question (e.g., an EMS/historian-tier box).

---

## Category: Asset Integrity (service installed on critical asset)

**Govern / Identify / Protect (before an alert fires):** the "known-good software
baseline for that host class" SentinelSleuth compares against below has to exist
and be maintained *before* this category is useful — if no baseline exists for a
host class yet, that's an Identify-function gap to close (build the baseline),
not a reason to skip the comparison silently.

**SentinelSleuth (investigation) — CSF: Detect** — pulls the service name/binary
path, whether it matches any known-good software baseline for that host class,
install-triggering account and whether it's on `approved-admins`.

**TriageForge (triage) — CSF: Detect** — unknown service + non-approved installer
account = escalate toward High regardless of the rule's default; known-good
pattern with an approved account = eligible for faster classification, still
logged.

**ResponseWarden (response) — CSF: Respond** — draft-only for anything touching a
critical OT asset (same IEC 62443-2-4 hard gate as above if the asset is OT-tier);
for IT-tier assets, narrower autonomous actions (e.g., quarantine recommendation)
may be scoped once this is a proven pattern — not assumed on day one.

**ContinuityMarshal — CSF: Recover** — engages if the asset is availability-critical
and the service install looks disruptive (resource contention, reboot-required
patterns).

---

## Building this — sequencing note

Per GOALS.md M3 (SentinelSleuth PoC on RTX 5080, querying the Sentinel Incidents
API), build investigation (SentinelSleuth) first against a single enclave (dev),
prove the tenant-scoping contract holds under test (deliberately try to make it
query a second enclave and confirm it can't), *then* layer TriageForge, then
ResponseWarden with the OT hard gate as its first and most heavily tested
constraint, then ContinuityMarshal last since it depends on the other three's
context to make a DR call. Don't build ResponseWarden's execution authority ahead
of the hard-gate logic — the gate is the load-bearing safety property of this
whole design, and it must exist before ResponseWarden touches anything.
