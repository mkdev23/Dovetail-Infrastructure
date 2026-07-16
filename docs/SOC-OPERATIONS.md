# Dovetail SOC — Operations Runbook
**Status: Production v1.0 (2026-07-16).** Baseline operating model for enclaves
deployed by this factory. Written for a two-analyst reality (Jay + Divyash at
launch); scales to shifts later. Standards-aligned per the section below — legal/
regulatory content is flagged for counsel review where noted, everything else is
this repo's operational source of truth.

Fuller architecture, training, playbook, and escalation-matrix detail (including
the full Liberia/ECOWAS regulatory landscape) lives in the companion suite at
`workspace/dovetail/soc-ops/` (OpenClaw workspace, not this repo) — this doc stays
self-contained for day-to-day shift use and cross-references that suite rather than
duplicating it.

## Standards alignment

This runbook is organized against **NIST CSF 2.0**'s six functions (Govern,
Identify, Protect, Detect, Respond, Recover) and **NIST SP 800-61 Rev. 3** (final,
April 2025 — the current incident-response guidance, superseding the older Rev 2
PICERL lifecycle). Because Dovetail delivers OT/ICS security as a service to a
national utility, two more standards are directly on point and cited throughout:

- **IEC 62443-2-4** — security program requirements for IACS service providers.
  This is the standard that describes what Dovetail *is* (an external service
  provider with delegated access to industrial control system environments); the
  tenant-per-enclave + Lighthouse JIT model in this repo is built to satisfy it.
- **ISO/IEC 27019:2017** — ISMS controls specific to the energy utility sector.
  Directly applicable to the LEC enclave.

General baseline: **ISO/IEC 27001:2022** (ISMS) / **ISO/IEC 27035-1/-2:2023**
(incident management). Mapping below is a working cross-reference, not a formal
audit artifact — treat it as a starting point for any future certification effort,
not a substitute for one.

| Runbook section | CSF 2.0 function(s) | Standard(s) |
|---|---|---|
| Severity & SLA table | Detect, Respond | NIST SP 800-61r3, ISO 27035-1 |
| Daily/weekly routine | Detect, Protect | NIST CSF 2.0, ISO 27019 |
| Triage guides (High rules) | Detect, Respond | NIST SP 800-61r3, IEC 62443-2-4 |
| Escalation / OT approval gate | Respond, Govern | IEC 62443-2-4 (service-provider authority limits) |
| Evidence & closure (below) | Respond, Recover | ISO/IEC 27037 |

## Liberia regulatory awareness (condensed — verify with counsel before any client-facing compliance claim)

As of 2026-07-16: Liberia has **no enacted general data protection law** (a bill
has been under legislative review; no national Data Protection Authority exists
yet). Liberia **is a signatory to the ECOWAS Supplementary Act on Personal Data
Protection (A/SA.1/01/10)**, legally binding regionally but not yet domestically
implemented — treat it as the anticipatory baseline, not enforced law. A
**Cybercrime Act of 2025** has passed both legislative chambers and was forwarded
for presidential signature; **confirm current enactment status before citing it as
law**. **No Liberian national CERT/CSIRT exists** — there is no statutory national
channel to report an incident into today. Practical consequence: **notification
obligations for this engagement run through the client SOW/MSA, not Liberian
statute**, until that statutory regime is actually in force. Full landscape,
sources, and the data-residency note (Sentinel workspaces run in Azure South
Africa North, outside Liberia) are in `workspace/dovetail/soc-ops/01-mssp-architecture.md`
— this paragraph is the operational summary, not the full research.

## Severity & response SLAs
| Severity | Meaning here | Acknowledge | Examples |
|---|---|---|---|
| High | OT boundary or pipeline integrity at risk | 30 min | FortiGate admin brute force, forwarder heartbeat loss, new local admin on EMS tier, D4IoT critical |
| Medium | Suspicious, needs same-day eyes | 4 h | FortiGate config change, Windows brute force, per-device telemetry silence |
| Low | Confirm-and-close pattern | Next business day | After-hours logon to critical asset |
| Informational | Auto-closed by automation rule | — | Logged for hunting only |

Automation enforces two of these: OT-related incidents are tagged and floored
at High; Informational is auto-closed with classification recorded.

## Daily routine (15–20 min when quiet)
1. Multi-workspace incident queue — triage anything new, oldest first.
2. Dovetail SOC Overview workbook, top row first: heartbeat and ingestion
   volume. **In a diode architecture, pipeline health IS the first detection.**
3. FortiGate deny table — scan for new source/destination pairs.
4. Confirm overnight after-hours logons against the maintenance schedule.

## Weekly routine
- Run the three hunting queries (new OT talker, rare outbound, new auth pairs).
- Reconcile `critical-assets.csv` against reality; PR any changes, re-run
  `deploy-watchlists.ps1` per enclave. Stale watchlist = blind rules.
- Review auto-closed Informational sample (10 random) — confirm the auto-close
  rule isn't eating signal.

## Triage guides (High rules)
**Forwarder heartbeat loss** — base-rate cause is uplink outage. (1) Confirm
via out-of-band channel with onsite contact. (2) If uplink: availability
incident, monitor for buffer drain on recovery, verify no gap in
`CommonSecurityLog` timestamps afterward. (3) If the box itself is down and
uplink is fine: treat as potential tamper until the onsite contact confirms
cause — the egress server is the single point every attacker in this
architecture would want dark.

**FortiGate admin auth failures** — (1) Source inside jump-host subnet?
Compare against approved-admins. (2) Any 4624/successful FortiGate login from
same source after the failures? If yes, assume compromise of the boundary:
elevate via PIM, snapshot FortiGate config, engage client OT lead. (3) External
source: should be impossible by design — that's a segmentation failure finding
regardless of outcome.

**New local admin on critical asset** — validate against change calendar and
approved-admins watchlist. No match = incident stays open until a human at the
client confirms in writing. Don't accept "probably maintenance."

## Escalation
1. On-call Dovetail analyst (rotation TBD — currently Jay/Divyash alternating)
2. Client OT/IT lead (per-enclave contact sheet — maintain in the private ops
   vault, not this repo)
3. For OT-affecting containment actions: **client operations approves, Dovetail
   advises.** The SOC never initiates changes that could affect generation or
   distribution. Sentinel Responder scope enforces this technically; this line
   makes it policy, and it's the same human-in-the-loop authority limit
   **IEC 62443-2-4** expects of an IACS service provider — Dovetail is never the
   accountable party for an action affecting the client's physical process.

Full per-severity RACI, internal escalation chain, and client communication
templates: `workspace/dovetail/soc-ops/05-escalation-matrix.md`. This section
stays a summary; that doc is the source of truth for the full matrix.

## Incident notification path
The `pb-dc-<enclave>-notify` playbook POSTs High/Medium incidents to the
per-enclave webhook. Point it at Teams for the launch team; the payload is
plain JSON (`enclave`, `incident`) so it can also feed an internal triage/
enrichment pipeline later without changing the Sentinel side.

Regulatory notification (as opposed to internal/client alerting above) is
**contract-driven today, not statute-driven** — see the Liberia regulatory
awareness section above. Don't improvise a "we're legally required to report
this to X" claim mid-incident; if that question comes up, it routes to
Jay/Divyash, not the on-call analyst's judgment call.

## Evidence handling & incident closure

Applies ISO/IEC 27037 digital-evidence principles (identification, collection,
acquisition, preservation) proportionate to a two-analyst SOC — this is not a
forensic-lab procedure, but it has to survive a client or, eventually, a
Liberian Cybercrime Act prosecution asking "how do you know that's what
happened."

For anything collected as evidence during triage (query results, exported logs,
screenshots, FortiGate config snapshots, etc.):
1. **Identify** — note what was collected, from where (workspace/table/resource
   ID), and when (UTC timestamp), in the incident comments before you act on it
   further.
2. **Collect/acquire** — prefer exporting via Sentinel's native tools
   (`CommonSecurityLog` export, incident timeline export) over manual copy-paste;
   native export preserves source timestamps and query context.
3. **Preserve** — don't overwrite or re-run a query that could change (e.g., a
   watchlist join after the watchlist itself changes) without saving the
   original result first. If a hash or checksum is meaningful for the artifact
   type (e.g., an exported config file), record it.
4. **Chain-of-custody note** — one line per artifact: what, who collected it,
   when, why it was needed for the classification decision. This lives in the
   incident comments, not a separate system, so it stays attached to the
   incident record.

Every closed incident still has: classification set, one-line comment with the
evidence that justified closure (per the above, not just an assertion), and (if
a rule was noisy) a linked PR to `content/` tuning it. Tuning lives in git, never
as console-only edits — console edits don't propagate to other enclaves and die
in redeploys.
