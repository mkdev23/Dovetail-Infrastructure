# Dovetail SOC — Operations Runbook
Baseline operating model for enclaves deployed by this factory. Written for a
two-analyst reality (Jay + Divyash at launch); scales to shifts later.

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
   makes it policy.

## Incident notification path
The `pb-dc-<enclave>-notify` playbook POSTs High/Medium incidents to the
per-enclave webhook. Point it at Teams for the launch team; the payload is
plain JSON (`enclave`, `incident`) so it can also feed an internal triage/
enrichment pipeline later without changing the Sentinel side.

## What "done" looks like for a triaged incident
Every closed incident has: classification set, one-line comment with the
evidence that justified closure, and (if a rule was noisy) a linked PR to
`content/` tuning it. Tuning lives in git, never as console-only edits —
console edits don't propagate to other enclaves and die in redeploys.
