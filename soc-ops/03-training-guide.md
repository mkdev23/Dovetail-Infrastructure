# Dovetail SOC — Analyst Training Guide

**Status:** Production v1.0, 2026-07-16. Written for the first hire past the current
two-analyst reality (Jay + Divyash). Assumes the trainee has general SOC/SIEM
background but zero context on Dovetail's specific factory, delegation model, or
content. Pair with a live walkthrough of an actual enclave (dev or demo) — reading
this alone is not certification.

---

## Module 0 — Orientation

Dovetail Cyber runs a **multi-tenant MSSP** on Microsoft Sentinel. Read
`01-mssp-architecture.md` in full before continuing — everything below assumes you
understand: tenant-per-enclave isolation, Azure Lighthouse delegation, and the
three access tiers (Reader / Responder / Engineer).

Repo you'll live in day-to-day: `dovetail-infra` ("Sentinel Enclave Factory").
Know these paths before your first shift:
- `docs/SOC-OPERATIONS.md` — SLAs, daily/weekly routine, the three High-rule triage
  guides. Your first read every shift.
- `docs/DEPLOY-INITIAL-ENVIRONMENT.md` / `docs/LEC-REFERENCE-ARCHITECTURE.md` —
  how enclaves get built; read once, reference during onboarding.
- `content/` — the detection rules, automation, hunting queries, and workbook you'll
  work against daily.
- `02-soc-sops.md` (this suite) — onboarding/offboarding/isolation procedures.

---

## Module 0b — Standards & Regulatory Frame

Know the *why* behind the procedures before you learn the mechanics — every SOP
and playbook in this suite is written against a specific standards frame, not
invented from scratch.

- **NIST CSF 2.0** — six functions: Govern, Identify, Protect, Detect, Respond,
  Recover. Every SOP in `02-soc-sops.md` and every playbook category in
  `04-playbooks.md` is tagged against these — when you read "CSF 2.0: Respond,
  Recover" at the top of a procedure, that's telling you where it sits in the
  overall security lifecycle, not just what to click.
- **NIST SP 800-61 Rev. 3** (final, April 2025) is the specific incident-response
  guidance this suite follows — current as of this writing, supersedes the older
  Rev 2 lifecycle you may have learned elsewhere.
- **IEC 62443-2-4** matters because of *what Dovetail is*: a third-party service
  provider with delegated access to industrial control system environments. It's
  the standard that describes the authority limits you operate under — most
  concretely, the OT hard gate ("client operations approves, Dovetail advises")
  you'll see repeated throughout this suite isn't a Dovetail policy choice, it's
  what this standard expects of your role.
- **ISO/IEC 27019** covers energy-utility-sector ISMS controls — relevant every
  time you're working an LEC incident specifically.
- **Liberia's legal landscape, in one paragraph**: as of 2026-07-16, Liberia has
  no enacted general data protection law and no national CERT/CSIRT — incident
  notification for the LEC engagement runs through the client contract, not
  Liberian statute, though that's actively changing (a Cybercrime Act has cleared
  the legislature, more is on the roadmap). You don't need to memorize the legal
  detail — you need to know it exists, know where it lives
  (`01-mssp-architecture.md` §8, `02-soc-sops.md` SOP-6), and know to route any
  "are we legally required to..." question to Jay/Divyash rather than answering
  it yourself.

---

## Module 1 — Azure Lighthouse & Cross-Tenant Access

**Concept:** Lighthouse lets Dovetail act inside a client's Azure tenant without a
standing account there. A client runs one deployment (`lighthouse.json`) once; from
then on, specific Dovetail Entra groups get specific roles in that tenant, visible
and auditable from the client's side at all times.

**Hands-on, in order:**
1. In the Dovetail tenant, open **Service Providers → My customers**. Every listed
   subscription is an enclave you have some level of delegated access to.
2. Pick a non-production enclave (dev or demo — never practice this on `lec`).
   Confirm your **SOC Analysts** membership gives you Sentinel Reader there right
   now, with no elevation.
3. **PIM walkthrough:** attempt an action that requires Responder (e.g. changing an
   incident's status/owner). You'll be prompted to activate — MFA challenge, reason
   field, max 8-hour window. Complete one full activation cycle so you've seen it,
   then let it expire naturally and confirm you're back to Reader-only.
4. In the *enclave* tenant (dev), find **Service Providers** and locate the Dovetail
   offer. Open the activity/audit log and find your own PIM activation from step 3.
   This is what a client sees — internalize that every elevated action you take is
   visible to them, permanently.

**Why this matters operationally:** SOP-4 in `02-soc-sops.md` (cross-tenant
isolation check) only works if you actually understand what an "enclave" and a
"PIM activation scoped to one subscription" mean. Don't skip the hands-on steps
above for the reading.

---

## Module 2 — The Multi-Workspace Incident Queue

Signed into the Dovetail parent tenant, Sentinel's multi-workspace incident queue
aggregates every enclave you're delegated into — this is the "one SOC, many
clients" pane of glass.

**Exercise:** open the queue. For each incident, identify its source workspace
(`law-dc-<enclave>-prod`) before opening it. This is a deliberate habit-forming
step — see SOP-4, check #1. There is nothing in the UI that stops you from acting
on the wrong client's incident by mistake; the workspace name in the incident
header is the only signal, and reading it first is a discipline, not a system
guarantee.

---

## Module 3 — Detection Content Walkthrough

As of this writing, `content/` is flat (a profile/baseline split is planned, see
`01-mssp-architecture.md` §4 — don't assume it exists yet). Know all 8 rules:

| Rule | Severity | What it catches |
|---|---|---|
| Forwarder heartbeat loss | High | Whole ingestion pipeline down (egress server, diode TX, or uplink). See Module 4 — this is the single most important rule in a diode architecture. |
| FortiGate admin auth failures | High | Repeated failed admin logins to the OT boundary firewall — possible brute force against the segmentation boundary. |
| New local admin on critical asset | High | New local admin account on a watchlisted critical host (EMS/historian/jump-tier) — checked against `approved-admins`. |
| D4IoT critical (via connector) | High | Defender for IoT high-severity alert, OT sensor side. |
| FortiGate config change | Medium | Any config change on the OT boundary firewall. |
| Windows brute force | Medium | 4625 failure burst pattern. |
| OT telemetry silence (per-device) | Medium | One OT source went quiet while the pipeline heartbeat is otherwise healthy — catches partial failures heartbeat-loss can't see. |
| After-hours critical access | Low | Interactive logon to a critical asset outside 06:00-20:00 — exists to be *seen and confirmed*, not assumed malicious. |

Also know:
- **2 automation rules**: auto-tag-and-floor-severity for anything OT-tagged
  (ensures OT incidents never silently sit below High), and auto-close for
  Informational-classified incidents (with classification recorded — reviewed
  weekly per SOC-OPERATIONS.md).
- **3 hunting queries**: new OT network talker, rare outbound OT traffic, auth
  pattern outside baseline. Run weekly per the SOC-OPERATIONS routine — these
  don't create incidents on their own, they're analyst-driven.
- **Dovetail SOC Overview workbook**: pipeline health and ingestion volume live at
  the top, deliberately — in a diode architecture, that panel *is* the first line
  of detection, not an afterthought below the incident list.
- **Watchlists**: `critical-assets` and `approved-admins` — three rules join
  against them. A stale watchlist means a rule silently stops working with no
  error. See SOP-5.

---

## Module 4 — OT/ICS Threat Fundamentals (diode architecture)

Read `docs/LEC-REFERENCE-ARCHITECTURE.md` in full — it's short and it's the mental
model for every OT enclave. Core idea to internalize before your first OT shift:

**A hardware data diode means the SOC cannot probe inbound.** No pinging the
sensor, no polling the TAP, no health-checking the egress server from the cloud
side. Every failure mode has to be *inferred from absence*, which is why two
separate "silence" detections exist and why they mean different things:

- **Forwarder heartbeat loss** = the whole pipeline might be down. Base-rate cause
  in a place like Monrovia is uplink outage, not attack — but you still treat it as
  an availability incident and, if uplink is confirmed fine and the box itself is
  down, escalate to potential tamper. The egress server is the single asset every
  attacker in this architecture would most want dark.
- **OT telemetry silence (per device)** = the pipeline is fine but one source went
  quiet — sensor fault, TAP failure, or someone reconfigured logging at the source.

If you only remember one line from this module: **pipeline health is the first
detection, not a supporting metric.**

---

## Module 5 — Tabletop Scenarios

Run these live against the dev enclave where possible (inject the test CEF event
per `docs/DEPLOY-INITIAL-ENVIRONMENT.md` Phase 9A, or stop the dev forwarder for
Phase 9B) rather than purely on paper.

**Scenario A — Forwarder heartbeat loss.**
Stop the dev forwarder. Confirm: (1) incident fires within ~15 min, (2) it appears
in the parent-tenant multi-workspace queue, (3) you correctly identify it as an
availability incident pending onsite confirmation, not an assumed attack, per the
triage guide in `SOC-OPERATIONS.md`. Restart the forwarder; confirm no gap in
`CommonSecurityLog` after recovery.

**Scenario B — FortiGate admin auth failures escalating to success.**
(Paper exercise — don't actually hammer a real FortiGate.) Given a burst of failed
admin logins from a source inside the jump-host subnet, followed by one successful
login from the same source: walk the triage guide. Correct call: assume boundary
compromise, elevate via PIM to Responder, snapshot the FortiGate config, engage the
client's OT lead per the escalation policy. If the source were external instead —
correct call: that's a segmentation-design failure finding regardless of outcome,
external FortiGate admin access "should be impossible by design."

**Scenario C — New local admin, no change-calendar match.**
Given an incident with no matching maintenance window and the account not on
`approved-admins`: correct call is the incident **stays open** until a human at the
client confirms in writing. "Probably maintenance" is explicitly not an accepted
closure reason per SOC-OPERATIONS.md — make the trainee say why, out loud, before
moving on.

---

## Certification checklist — before solo on-call

- [ ] Can name the standards frame (NIST CSF 2.0 six functions, IEC 62443-2-4's
      relevance to Dovetail's role, Liberia's current no-statutory-notification
      status) without prompting.
- [ ] Completed Module 1 hands-on (Lighthouse, PIM activation cycle, audit log check)
      against a non-production enclave.
- [ ] Can correctly identify the source enclave for an incident from the queue
      without opening it first.
- [ ] Can name all 8 analytics rules, their severities, and what each catches,
      unprompted.
- [ ] Has run all three tabletop scenarios and reached the correct triage call on
      each without prompting.
- [ ] Has read `02-soc-sops.md` in full and can explain SOP-4 (isolation check) from
      memory.
- [ ] Knows where the escalation chain and client contact sheet live
      (`05-escalation-matrix.md` + the private ops vault — never this repo).
