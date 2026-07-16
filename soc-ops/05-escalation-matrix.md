# Dovetail SOC — Escalation Matrix & Client Communication Templates

**Status:** Production v1.0, 2026-07-16. Expands the escalation stub in
`dovetail-infra/docs/SOC-OPERATIONS.md` into a full per-severity RACI and adds
client-facing templates that don't exist in the repo yet. Per-client contact
details live in the private ops vault, never in this repo or this doc — every
template below uses placeholders.

**SLA defensibility check (NIST SP 800-61r3 / ISO/IEC 27035-1):** neither standard
mandates specific numeric response times — both require that response-time
objectives be risk-tiered, documented, and consistently applied. The severity/SLA
table in `SOC-OPERATIONS.md` (High: 30 min acknowledge, Medium: 4h, Low: next
business day, Informational: auto-closed) satisfies that bar as written; this doc
doesn't change the numbers, it makes the RACI and notification path around them
explicit — which is the part that wasn't yet documented anywhere.

---

## RACI by severity

| Severity | Responsible | Accountable | Consulted | Informed |
|---|---|---|---|---|
| **High** (OT boundary / pipeline at risk) | On-call Dovetail analyst | Client Operations (for any action affecting generation/distribution) | Client OT/IT lead | Jay/Divyash (internal), client stakeholder per contact sheet |
| **Medium** | On-call Dovetail analyst | Dovetail (classification/response); Client Operations only if containment touches OT | Client OT/IT lead if OT-adjacent | Jay/Divyash |
| **Low** | On-call Dovetail analyst | Dovetail | — | Logged, surfaced in daily routine only |
| **Informational** | Automation (auto-close) | Dovetail (weekly sample review) | — | — |

**The one rule that overrides all of the above:** for any action that could affect
OT generation or distribution — **client operations approves, Dovetail advises.**
The SOC never initiates a change with that blast radius unilaterally. Sentinel
Responder role scope enforces this technically (see `01-mssp-architecture.md` §3);
this table makes it policy, and it's the same line already in
`SOC-OPERATIONS.md` — restated here as an explicit RACI so the "who approves what"
question never gets improvised mid-incident.

## Internal escalation chain

1. **On-call Dovetail analyst** — first responder, all severities. Rotation is
   currently informal (Jay/Divyash alternating) — formalize once headcount grows
   past two; track the actual schedule in the ops vault, not here.
2. **Jay / Divyash** — escalation point for anything the on-call analyst can't
   resolve alone, any High-severity confirmed incident, or any judgment call on
   whether client notification is needed.
3. **Client OT/IT lead** — per-enclave contact, maintained in the private ops
   vault. Engaged directly for any OT-boundary High incident per the RACI above.
4. **External comms decision** (e.g., does this need to go beyond the OT/IT lead
   to client leadership) is made by Jay/Divyash, not the on-call analyst alone.

## Regulatory notification status (summary — full procedure in SOP-6)

Client notification (above) is always contract-driven. Separately: as of
2026-07-16, Liberia has no enacted data protection law and no national CERT/CSIRT,
so there is **no statutory Liberian authority in this RACI to notify today** — see
`02-soc-sops.md` SOP-6 for the full procedure and the standing watch list
(Cybercrime Act signature, Critical Infrastructure Act, sectoral energy rules,
national DPA/CERT establishment). If any of those change status, SOP-6 gets a
regulatory-notification row added to the RACI table above — don't add one
speculatively here first.

## Lighthouse access revocation on offboarding

Full procedure lives in `02-soc-sops.md` SOP-3 — referenced here because it's also
an escalation-adjacent control: if a client relationship terminates for-cause
(not routine contract end), access revocation (SOP-3 step 3: delete the
`registrationAssignments` resource) should happen **immediately**, ahead of the
rest of the offboarding checklist, and should be treated as a High-priority
internal action with Jay/Divyash sign-off, not a routine SOP step.

---

## Client communication templates

Placeholders in `{braces}`. Payload fields available from the existing
`pb-dc-<enclave>-notify` playbook are `enclave` and `incident` — templates below
are written to be fillable from that data plus the analyst's own triage notes.

### Template 1 — High/Medium incident notification (initial)

```
Subject: [Dovetail SOC] {severity} incident — {enclave} — {short_description}

{client_contact_name},

Our SOC identified a {severity} severity incident in your environment at
{incident_time} UTC.

What we saw: {one_line_technical_summary}
Current status: {investigating | confirmed | contained}
Requested from you: {specific_ask_or_none}

We'll follow up within {sla_window per SOC-OPERATIONS.md severity table} with an
update. If this requires action on your side that could affect operations, we will
not proceed without your explicit approval — see below.

— Dovetail SOC
```

### Template 2 — Status update (in-progress incident)

```
Subject: [Dovetail SOC] Update — {incident_id} — {enclave}

{client_contact_name},

Update on the incident reported at {original_report_time}:

Findings since last update: {summary}
Current classification: {classification}
Next step: {what_dovetail_is_doing} / {what_we_need_from_you, if anything}

{If OT-affecting action is being considered:}
This may require an action on your side ({proposed_action}). Per our engagement
model, Dovetail advises and your operations team approves any action affecting
generation or distribution — we need your go/no-go before proceeding.
```

### Template 3 — Closure / RCA

```
Subject: [Dovetail SOC] Closed — {incident_id} — {enclave}

{client_contact_name},

This incident is now closed.

Classification: {final_classification}
Root cause: {summary}
Evidence supporting closure: {one_line, per SOC-OPERATIONS.md "Evidence handling & incident closure"}
Any follow-up recommended: {tuning PR filed? watchlist update needed? none}

Full detail available on request.

— Dovetail SOC
```

### Template 4 — Onboarding welcome (new enclave, ties to SOP-1/SOP-2)

```
Subject: Welcome to Dovetail SOC — {enclave} is live

{client_contact_name},

Your environment is now monitored by Dovetail SOC. A few things worth knowing:

- Access is delegated via Azure Lighthouse — nothing standing, everything logged
  in your own tenant. You can see it any time under Service Providers.
- Your team can review every elevated (Responder/Engineer) action we take under
  your tenant's audit log.
- Escalation contact on our side: {on_call_contact}.
- For anything affecting your operations directly, we always ask before we act.

— Dovetail SOC
```

---

## What's still missing (flag before first real use)

- No formal on-call rotation schedule beyond "Jay/Divyash alternating" — needs a
  real schedule once headcount changes.
- SOP-3 (offboarding) is unrehearsed — the revocation-on-termination escalation
  path above inherits that same "not yet proven live" caveat.
- Per-client contact sheets don't exist in a structured format yet (referenced as
  "the ops vault" throughout this suite) — creating that structure is a natural
  next task, not scoped into TASK-117.
