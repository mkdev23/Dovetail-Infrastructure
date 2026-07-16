# Dovetail SOC — Multi-Tenant MSSP Architecture Reference

**Status:** Production v1.0, 2026-07-16. Reference doc for the rest of the SOC
Operations suite (`02-soc-sops.md`, `03-training-guide.md`, `04-playbooks.md`,
`05-escalation-matrix.md`) — they link back here rather than re-explaining the model.
This is also the **single full treatment of the Liberia/ECOWAS regulatory landscape**
(§9) — `dovetail-infra/docs/SOC-OPERATIONS.md` carries only a condensed pointer to it.

**Standards this suite is written against:** NIST CSF 2.0 (six functions: Govern,
Identify, Protect, Detect, Respond, Recover) and NIST SP 800-61 Rev. 3 (final,
April 2025) as the general incident-response spine; ISO/IEC 27001:2022 /
27002:2022 for ISMS controls; IEC 62443-2-4 (security program requirements for
IACS service providers — describes what Dovetail *is*) and ISO/IEC 27019:2017
(energy-sector ISMS controls) for the OT/utility-specific layer. Cited inline
below where a specific control or clause justifies a specific design choice —
this is a working cross-reference, not a certification audit artifact.

**Source of truth:** this doc summarizes and operationalizes what's already built in
the `dovetail-infra` repo ("Sentinel Enclave Factory," LP-39). Where this doc and the
repo disagree, the repo wins — re-sync this doc. Primary sources: `README.md`,
`docs/DEPLOY-INITIAL-ENVIRONMENT.md`, `docs/LEC-REFERENCE-ARCHITECTURE.md`,
`lighthouse/lighthouse.json`, `modules/rbac.bicep`.

---

## 1. The model in one paragraph

Dovetail is a **multi-tenant MSSP**: one Dovetail-parent Entra tenant holds the SOC
team and nothing else (no workspace, no logs — management plane only). Every client
is its own **enclave** — a fully separate Azure tenant + subscription, hard-isolated
from every other enclave (**Option A: tenant-per-enclave**). Dovetail never holds a
standing account inside a client's tenant; instead, each enclave delegates a scoped
slice of access back to Dovetail via **Azure Lighthouse**. Detection content (analytics
rules, automation rules, hunting queries, workbooks, watchlists) is pushed to every
enclave from one private GitHub repo via **Sentinel Repositories** — one PR updates
every enclave that pulls that content pack.

This gives three simultaneous properties a client conversation should lead with:
- **Isolation** — a compromise or misconfiguration in one enclave cannot expose
  another enclave's data. There is no cross-tenant trust to accidentally traverse.
- **Consistency** — every enclave runs the same tested detection content, deployed
  the same way, versioned in git.
- **Auditability** — Dovetail's access into a client tenant is never silent or
  standing at the privileged tier; it's JIT, MFA-gated, and logged in the *client's*
  own tenant, visible to the client at any time.

## 2. Tenant map

| Tenant | Holds | Who's in it | Notes |
|---|---|---|---|
| **Dovetail parent** | SOC Entra groups, Lighthouse delegation *definitions* only | Dovetail staff (Jay, Divyash, future hires) | No Sentinel workspace lives here. This is where analysts sign in and where the multi-workspace incident queue is viewed *from*. |
| **Enclave tenant** (one per client, e.g. `enclave-lec`) | The client's Sentinel workspace, LAW, DCE/DCRs, connectors, forwarder | Client-owned subscription; Dovetail has **delegated**, not native, access | `dev` and `demo` enclaves are Dovetail-owned tenants used for testing/sales — architecturally identical to a production client enclave. |

Repo convention: `enclaveName` is a lowercase slug ≤12 chars (`lec`, `dev`, `demo`),
used to derive resource group, workspace (`law-dc-<enclave>-prod`), and DCR names.
Confirmed enclaves as of this writing: `enclave-dev`, `enclave-demo`, `enclave-lec`
(pre-staged prod, OT profile, physical Arc-connected forwarder).

## 3. Access model — Entra groups → Lighthouse roles

Control basis: **ISO/IEC 27001:2022 Annex A.5.15** (access control), **A.5.18**
(access rights — grant, review, revoke), **A.8.2** (privileged access rights), and
**A.8.5** (secure authentication). The Reader/Responder/Engineer split below is
this repo's concrete implementation of those controls — permanent access is
never privileged, privileged access is never permanent.

Defined once in the Dovetail parent tenant, granted per-enclave by running
`lighthouse/lighthouse.json` against each enclave subscription:

| Dovetail group | Lighthouse role in each enclave | Elevation |
|---|---|---|
| **SOC Analysts** | Sentinel Reader | **Permanent** — always-on read/triage visibility |
| **SOC Responders** | Sentinel Responder | **PIM-eligible**, JIT, MFA required, max 8h activation (`PT8H`), logged in the enclave tenant |
| **SOC Engineers** | Sentinel Contributor | **PIM-eligible** — content/connector work, same JIT/MFA/8h/audit constraints |
| **PIM Approvers** (optional) | — | If populated, Responder/Engineer elevation requires an approval; empty = elevation still happens but isn't gated, only logged |

Key property: **Reader is the only standing access anywhere in a client tenant.**
Anything that can act on an incident (Responder) or touch content/connectors
(Engineer) requires an explicit, time-boxed, MFA'd elevation that the client can see
in their own audit log. This is the technical backbone of the "Dovetail advises,
client operations approves" governance line used in escalation policy
(`05-escalation-matrix.md`).

Enclave-local staff (a client's own IT/OT team, where applicable) get the mirror
image: `modules/rbac.bicep` grants an Entra group **inside the enclave tenant**
Sentinel Reader (or Responder, if they work incidents themselves), scoped to that
one resource group only. They have zero visibility into other enclaves or into the
Dovetail parent tenant — there's no cross-tenant trust for it to ride on even if this
were misconfigured.

## 4. Content delivery — what an enclave actually receives

Detection content is not copy-pasted per client; it's pulled by each enclave's
Sentinel instance from the shared repo via **Content management → Repositories**.
What an enclave receives is governed by two params in its `enclaves/<name>.bicepparam`
file:

- **`profile`** — `ot` (OT/ICS customers like LEC: FortiGate, Defender for IoT, CEF
  diode telemetry) or `it` (identity/endpoint/SaaS-only customers, e.g. a ministry
  with no OT). Today this param mainly gates connector deployment
  (`defenderForIotSubscriptionId` required when `ot`).
- **content packs (planned, not yet live)** — as of 2026-07-16, `content/` is a flat
  folder and every enclave's Sentinel Repositories connection pulls the same 8
  analytics rules, 2 automation rules, and 3 hunting queries regardless of `profile`
  — including OT-specific rules (FortiGate, diode telemetry) on IT-only enclaves,
  where they'll simply never fire. A restructure into `baseline/` (vertical-neutral,
  every enclave) + `profiles/ot|it/` (profile-matched) + `verticals/health|utility/`
  (demo-only re-titled workbooks, no new detections) is scoped in the repo's
  `CLAUDE.md` but **not yet implemented**. Until it lands, don't tell a client "you
  only get relevant detections" — today everyone gets everything in `content/`.

This is a factory, not bespoke-per-client engineering: **adding an enclave is one
param file + one deploy command.** If a change requires manual per-client console
edits, it's being done wrong — file it as a repo issue, don't hand-tune in the portal
(console edits don't propagate to other enclaves and are lost on redeploy).

## 5. Enclave lifecycle — build → handoff → (eventually) offboard

This build→handoff→offboard progression, and the hard rule that Dovetail's
*direct* Owner access is removed at handoff (table below), is this repo's
concrete implementation of **IEC 62443-2-4**'s security-program requirements for
an IACS service provider: bounded engagement scope, no standing privileged
access to the client's operational environment past the build phase, and a
defined, auditable offboarding path. For an OT client like LEC, this is the
standard a client's own security review will most likely measure Dovetail
against — lead with it in any security-posture conversation.

| Stage | Subscription Owner | Dovetail access | Notes |
|---|---|---|---|
| **Build** | Dovetail (Jay/Divyash), or the customer's Owner runs the one-time Lighthouse deployment | Full — Dovetail stands the workspace up | Dev/demo stay Dovetail-owned indefinitely; production enclaves are transitional. |
| **Handoff** (production only) | **Customer rep** | Delegated only, via Lighthouse | Dovetail's *direct* Owner role assignment is **removed** at handoff — everything past this point is JIT/audited, no exceptions. A break-glass account is created and its credentials sealed with the customer. |
| **Steady state** | Customer | Delegated, JIT | Client can see the **Service Providers** blade (their tenant) showing the Dovetail offer, and their own audit log of every Dovetail PIM elevation. |
| **Offboard / contract end** | Customer | None | See `02-soc-sops.md` SOP-3. Not yet exercised in this repo/factory — first-draft procedure, needs a live rehearsal. |

Full step-by-step onboarding and handoff checklists live in `02-soc-sops.md`
(SOP-1 and SOP-2) — this section is the *why*, that doc is the *how*.

## 6. Cross-tenant reporting — how Dovetail actually sees everything at once

Analysts never sign into individual enclave tenants to triage. Signed into the
**Dovetail parent tenant**, Microsoft Sentinel's **multi-workspace incident queue**
aggregates every enclave workspace Dovetail has Lighthouse-delegated Reader access
to, into one pane. This is the single mechanism that makes "one SOC, many clients"
operationally real, and it's the thing to demo to prove the whole chain works: kill
a forwarder in an enclave, watch the heartbeat-loss incident appear in the parent
queue (`docs/DEPLOY-INITIAL-ENVIRONMENT.md` Phase 9B is the scripted version of this
proof).

Practical consequence for analysts: **every incident in that queue names its
workspace** (`law-dc-<enclave>-prod`), and that name is the only thing standing
between "this is LEC's incident" and "this is the demo enclave's incident." See the
cross-tenant isolation check in `02-soc-sops.md` SOP-4 — confirming the enclave
before acting is a checklist item, not an assumption.

## 7. Verification points (use these to confirm delegation is live, not just deployed)

- **Dovetail tenant → Service Providers → My customers**: lists every enclave
  subscription Dovetail is delegated into.
- **Enclave tenant → Service Providers**: lists the Dovetail offer
  ("Dovetail Cyber - Managed Security Operations") from the client's side.
- A wrong Entra group ID in `lighthouse.parameters.json` **fails silently** — the
  Lighthouse deployment succeeds but grants nothing useful. Always check both blades
  after onboarding a new enclave, not just that the `az deployment sub create`
  command returned 0.

## 8. Liberia & regional regulatory landscape (research current as of 2026-07-16 — verify with local counsel before any client-facing compliance claim)

Dovetail operates out of Liberia and its flagship client (LEC) is a Liberian
national utility, so this section is written as an operational reference, not a
legal opinion. **Every claim below needs local-counsel verification before it's
repeated to a client or used to justify a compliance posture.**

**Data protection.** Liberia has **no enacted general data protection law** as of
this writing. A Data Protection and Privacy bill has been under legislative
review; Liberia has **no national Data Protection Authority**. Liberia **is a
signatory to the ECOWAS Supplementary Act on Personal Data Protection**
(A/SA.1/01/10, adopted 2010) — this is legally binding at the regional level and
strongly influenced by the EU's old Data Protection Directive, but Liberia has
**not yet implemented it domestically** (no national DPA, no domestic statute
giving it direct effect). Treat the ECOWAS Act as the anticipatory baseline —
building toward it now is cheap insurance against the domestic law landing later
with a similar shape — not as a rule currently enforced against Dovetail or LEC.
Sources: [dataguidance.com](https://www.dataguidance.com/jurisdictions/liberia),
[Liberian Observer, House Reviews Privacy Bill](https://www.liberianobserver.com/politics/house-reviews-privacy-data-protection-bill/article_6675211a-e8bc-43c6-8e04-e73cbf26278a.html),
[ECOWAS Act text](https://www.statewatch.org/media/documents/news/2013/mar/ecowas-dp-act.pdf).

**Cybercrime law.** A **Cybercrime Act of 2025** passed the House of
Representatives and received Senate concurrence (January 2026), and was
forwarded to President Boakai for signature. **Confirm current signature/
enactment status before citing it as law** — this doc's research did not find
confirmation of presidential signature as of 2026-07-16. Once in force, it
includes measures addressing unauthorized computer access, critical
infrastructure protection, and inter-agency coordination on cyber offences —
directly relevant to how a security incident against LEC could eventually be
prosecuted. Sources: [allAfrica](https://allafrica.com/stories/202601160269.html),
[Liberian Observer](https://www.liberianobserver.com/news/senate-concurrence-clears-path-for-cybercrime-act-of-2025/article_23810644-5064-41a7-831d-01cace2bb8a8.html).

**National cybersecurity strategy & critical infrastructure.** Liberia's Ministry
of Posts & Telecommunications has published a **National Cybersecurity Strategy
2025-2029**, targeting a primary National Cybersecurity Act, a Critical
Infrastructure Act/Regulation, and sectoral cybersecurity rules (energy
explicitly named) on a roadmap that — as of this writing — has likely slipped
against its original quarterly targets. **Treat this as a roadmap to monitor, not
current law.** The Liberia Telecommunications Authority's existing ICT Policy
requires stakeholders to secure critical telecom infrastructure and support
incident reporting/recovery, but does not extend explicit sector-specific
requirements to energy/electricity today. Sources:
[MOPT strategy document](https://mopt.gov.lr/wp-content/uploads/2026/02/Liberia_National-Cyber-Security-Strategy-2025-2029.docx.pdf),
[LTA cybersecurity page](https://lta.gov.lr/cyber-security/).

**No national CERT/CSIRT.** Liberia does not currently operate a national
Computer Emergency Response Team. There is **no statutory national channel** to
report a cyber incident into today — the reporting relationship for the LEC
engagement is Dovetail → client, governed by contract, not Dovetail → a Liberian
national authority. Source: [ITU national CIRT directory](https://www.itu.int/en/ITU-D/Cybersecurity/Pages/national-CIRT.aspx).

**Practical conclusion.** Until Liberia's statutory regime is actually in force,
**incident notification, breach reporting, and data-handling obligations for
this engagement are defined by the SOW/MSA with the client, not by Liberian
statute.** This is not a gap to hide — state it plainly to clients: Dovetail
follows international standards (ISO 27001, NIST CSF 2.0, IEC 62443) and
contractual commitments now, and is positioned to adopt Liberia's domestic
regime the moment it's enacted, having already built toward the ECOWAS baseline.
Maintain a standing watch on: Cybercrime Act signature, National Cybersecurity
Act adoption, Critical Infrastructure Act/Regulation, sectoral energy rules, and
any national DPA establishment — review quarterly, update this section and
`SOC-OPERATIONS.md`'s condensed pointer together when any of these change status.

**Data residency.** Enclave workspaces deploy to Azure **South Africa North**
(`docs/DEPLOY-INITIAL-ENVIRONMENT.md`, `README.md`) — client log/telemetry data
leaves Liberia and is processed/stored in South Africa. This is **not a legal
blocker today** (no Liberian data-localization requirement in force), but for a
national-utility client it's worth explicit disclosure in the SOW rather than
leaving implicit, and becomes a live question the moment Liberia's Data
Protection Act or Critical Infrastructure Act pass — re-review this specific
point first when either does.

## 9. Open items / not yet true

- Production offboarding (full contract-termination revocation) has a written
  procedure (`02-soc-sops.md` SOP-3) but **no live rehearsal yet** — treat it as
  draft until exercised once, the same way the dev/demo dry run validated onboarding.
- RTX 6000 inference infra and the four AI agents (SentinelSleuth, TriageForge,
  ResponseWarden, ContinuityMarshal) referenced in `04-playbooks.md` are **design
  target, not deployed** — GOALS.md milestone M3/M4, both NOT STARTED as of
  2026-07-16. Don't represent them as live capability to a client.
