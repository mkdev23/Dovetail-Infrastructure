# Dovetail SOC — Standard Operating Procedures

**Status:** Production v1.0, 2026-07-16.
**Relationship to `dovetail-infra/docs/SOC-OPERATIONS.md`:** that doc already owns
severity/SLA definitions, the daily/weekly routine, and the three High-severity
triage guides (forwarder heartbeat loss, FortiGate admin auth failures, new local
admin on critical asset) — **this doc does not duplicate those**, it adds the
procedures that don't exist there yet: tenant onboarding, tenant offboarding,
regulatory notification, and a cross-tenant isolation check woven into every
triage action. Read that doc first; this one assumes it.

Architecture context for everything below: `01-mssp-architecture.md` (includes the
full Liberia/ECOWAS regulatory landscape referenced in SOP-6).

**Standards frame:** each SOP below is tagged against the **NIST CSF 2.0** function(s)
it primarily serves (Govern, Identify, Protect, Detect, Respond, Recover — per
NIST SP 800-61 Rev. 3) plus the specific ISO/IEC or IEC 62443 clause it operationalizes,
where one applies directly.

---

## SOP-1 — Enclave Onboarding

**CSF 2.0:** Govern, Identify, Protect · **Standard:** IEC 62443-2-4 (service-provider
engagement scoping), ISO/IEC 27001 A.5.18 (access rights provisioning)
**Trigger:** new client signs, or a new dev/demo enclave is needed.
**Owner:** Dovetail SOC Engineer, with the client's designated Owner for step 2.

1. Confirm the three Dovetail Entra groups (SOC Analysts / Responders / Engineers)
   already exist in the Dovetail parent tenant and their object IDs are current in
   `lighthouse/lighthouse.parameters.json`. (One-time, already done — verify, don't
   recreate.)
2. **Lighthouse registration** — an account holding **Owner in the enclave
   subscription** (client's designated Owner for production; Dovetail for dev/demo)
   runs, from Cloud Shell or their workstation:
   ```bash
   az deployment sub create --location southafricanorth \
     --template-file lighthouse/lighthouse.json \
     --parameters lighthouse/lighthouse.parameters.json
   ```
3. **Verify both directions before proceeding** (see architecture doc §7):
   - Dovetail tenant → Service Providers → My customers shows the new enclave.
   - Enclave tenant → Service Providers shows the Dovetail offer.
   - If either is missing after ~2 minutes, stop and recheck the four IDs in the
     param file — this fails silently otherwise.
4. Copy `enclaves/_template.bicepparam` → `enclaves/enclave-<name>.bicepparam`, fill
   in `enclaveName`, `profile` (`ot` or `it`), and enclave-specific values.
5. Deploy: `./scripts/deploy-enclave.ps1 -Enclave <name> -SubscriptionId <sub> -WhatIf`
   to review, then without `-WhatIf` to apply.
6. Connect **Sentinel Repositories** to this GitHub repo on the new workspace
   (Content management → Repositories → Add new). Confirm the correct content packs
   land per the enclave's `profile`.
7. Deploy watchlists: `./scripts/deploy-watchlists.ps1 -Enclave <name> -SubscriptionId <sub>`
   — three baseline analytics rules stay dormant until this runs. Not optional.
8. Build/connect the forwarder (cloud VM twin for dev/demo, or physical Arc-connected
   box for production per `docs/LEC-REFERENCE-ARCHITECTURE.md`).
9. Validate: `./scripts/validate-enclave.ps1 -Enclave <name> -SubscriptionId <sub>` —
   every line must PASS, including forwarder heartbeat (allow 5-10 min after VM boot).
10. **Proof of the full chain, not just the deploy**: stop the forwarder, confirm the
    heartbeat-loss incident fires and appears in the Dovetail parent tenant's
    multi-workspace queue. This is the single test that proves ingestion → detection
    → Lighthouse → cross-tenant visibility, end to end. Restart the forwarder after.
11. Log the new enclave in the ops tracker (private vault, not this repo) with go-live
    date, profile, and primary client contact.

**Onboarding is not done until step 10 passes.** A deploy that succeeds but hasn't
proven end-to-end visibility is an unverified deploy.

---

## SOP-2 — Enclave Handoff (production go-live)

**CSF 2.0:** Govern, Protect · **Standard:** IEC 62443-2-4 (bounded engagement —
Dovetail's standing access ends at handoff), ISO/IEC 27001 A.5.18 (access rights review)
**Trigger:** a production enclave (built and validated per SOP-1) is ready to hand
control to the client.

1. Confirm the customer's designated rep is set as **subscription Owner** (they may
   already be, if they ran step 2 of SOP-1 themselves).
2. Create a **break-glass account** in the enclave tenant with emergency access;
   seal its credentials with the customer (physical or vault handoff, per their
   preference — not Dovetail's to hold long-term).
3. **Remove Dovetail's direct Owner role assignment** from the enclave subscription.
   From this point forward Dovetail's *only* path into this tenant is the Lighthouse
   delegation — no standing account, no exception.
4. If the client has their own IT/OT staff who need visibility, assign them via
   `enclaveReaderGroupId` (an Entra group **in the enclave tenant**) — `rbac.bicep`
   scopes them to the enclave resource group only.
5. **Walk the client through**:
   - Their Service Providers blade (proof Dovetail's access is delegated and named,
     not a hidden account).
   - Their own audit log of Dovetail PIM elevations (proof every Responder/Engineer
     action is visible to them, not just Dovetail).
6. Confirm the enclave now appears correctly attributed in whatever client-facing
   status reporting exists (see `05-escalation-matrix.md` for comms templates).
7. Update the ops tracker: status → live, handoff date, break-glass location noted
   (not the credentials themselves).

---

## SOP-3 — Enclave Offboarding (contract termination)

**CSF 2.0:** Govern, Recover · **Standard:** ISO/IEC 27001 A.5.18 (access rights
revocation on termination), ISO/IEC 27037 (evidence retention principles applied
to the export step below)
**Status: procedure defined, not yet rehearsed.** Exercise this once against a
disposable dev/demo enclave before it's ever run against a real client — the same
discipline that validated onboarding via the dev tenant dry run. Update this SOP
with anything that doesn't work as written.

1. Confirm termination is authorized (contract end date reached, or explicit
   written client request) — this is a client-relationship decision, not a SOC
   technical call. Do not initiate on inference alone.
2. **Export what needs to survive the workspace**, applying the same ISO/IEC 27037
   evidence principles as `SOC-OPERATIONS.md`'s closure procedure (identify,
   collect/acquire, preserve): incident history (export via Sentinel's native
   export, not manual copy), any client-specific tuning notes, watchlist state as
   of termination. Record what was exported, when, and by whom in the ops
   tracker entry created in step 7 — this record is itself the chain-of-custody
   artifact for the offboarding event. Client's data retention preference governs
   where the export goes (their own storage, or a sealed Dovetail archive per
   contract terms); if the contract is silent on retention period, default to the
   same interval as `retentionDays` was set to in that enclave's `bicepparam` and
   flag the gap to Jay/Divyash to close in future contracts.
3. **Revoke the Lighthouse delegation**: delete the
   `Microsoft.ManagedServices/registrationAssignments` resource in the enclave
   subscription (this is the reverse of the SOP-1 step 2 deployment — it removes
   Dovetail's delegated access without touching anything client-owned).
4. Confirm removal in **both** verification blades (architecture doc §7):
   - Dovetail tenant → My customers no longer lists the enclave.
   - Enclave tenant → Service Providers no longer lists Dovetail.
5. If an `enclaveReaderGroupId` was assigned (SOP-2 step 4), that's client-owned
   RBAC — leave it; it's theirs to clean up or keep.
6. Disconnect Sentinel Repositories from the workspace if the client is keeping
   Sentinel without Dovetail (avoids Dovetail's content changes continuing to land
   in a tenant Dovetail no longer monitors).
7. Update the ops tracker: status → offboarded, date, reason, export location.
8. Internal: confirm no lingering PIM eligibility, group memberships, or credentials
   reference the terminated enclave.

---

## SOP-4 — Cross-Tenant Isolation Check (apply on every triage action)

**CSF 2.0:** Protect, Detect · **Standard:** ISO/IEC 27001 A.8.2 (privileged
access rights — scope verification before use)
This is not a separate workflow — it's three checks layered onto the daily
triage routine and the three High-rule triage guides already in
`SOC-OPERATIONS.md`. Do these **before** acting on any incident from the
multi-workspace queue:

1. **Confirm the enclave.** The incident's workspace name
   (`law-dc-<enclave>-prod`) tells you which client this is. Read it before you
   read anything else in the incident. Acting on the wrong client's incident,
   even harmlessly, is a confidentiality failure.
2. **Confirm your elevation is scoped to that enclave only.** If the incident
   requires Responder or Contributor action, your PIM activation is per-subscription
   — verify you elevated into *this* enclave's subscription, not a stale elevation
   from a prior incident in a different enclave.
3. **No cross-pollination.** Never copy indicators, watchlist entries, hostnames, or
   any client-identifying detail from one enclave's incident into another enclave's
   notes, ticket, or communication thread — including inside Dovetail's own internal
   tooling. Tenant-per-enclave isolation is a technical control; don't defeat it with
   a shared notes doc.

---

## SOP-5 — Watchlist Maintenance

**CSF 2.0:** Identify, Protect · **Standard:** ISO/IEC 27019 (asset inventory
for energy-sector OT environments)
Expands the weekly routine in `SOC-OPERATIONS.md` into a repeatable procedure.
Three baseline analytics rules join against `critical-assets` — a stale watchlist
makes them blind without any error or warning.

1. Weekly, per enclave: pull current `critical-assets.csv` from Sentinel, diff
   against known reality (new critical hosts added? decommissioned hosts still
   listed? EO 163 asset-inventory changes for OT enclaves?).
2. Any change → PR against `content/` in this repo (never a console-only edit —
   console edits don't propagate to other enclaves and are lost on redeploy).
3. After merge: `./scripts/deploy-watchlists.ps1 -Enclave <name> -SubscriptionId <sub>`
   per affected enclave.
4. Confirm in Sentinel → Watchlist blade that the update landed.
5. Same procedure for `approved-admins.csv` when admin rosters change.

---

## SOP-6 — Incident Notification & Regulatory Reporting

**CSF 2.0:** Respond, Govern · **Standard:** ISO/IEC 27035-2 (notification
principles); status against Liberian statute tracked below, not a fixed standard.

Governs *who outside the incident-response chain* gets told about an incident and
under what authority — distinct from SOP-4 (who's allowed to act) and the internal
escalation chain in `05-escalation-matrix.md` (who inside Dovetail is told).

1. **Client notification** is always contract-driven: follow the SOW/MSA's
   notification clause for the affected enclave (timing, severity threshold,
   channel). Use the templates in `05-escalation-matrix.md`. This applies
   regardless of the regulatory status below — the client relationship comes
   first either way.
2. **Regulatory/statutory notification — current status (verify before acting):**
   Liberia has no enacted general data protection law and no national CERT/CSIRT
   as of 2026-07-16 — there is **no statutory Liberian authority to notify today**.
   Full sourcing: `01-mssp-architecture.md` §8. **Do not tell a client "we are
   legally required to report this to a Liberian authority"** — that's currently
   false. If a client or their counsel raises the question, route it to
   Jay/Divyash, not an on-call judgment call.
3. **Standing watch list** — re-check quarterly (or immediately if news breaks):
   - Cybercrime Act of 2025 — presidential signature/enactment status
   - National Cybersecurity Act — adoption status
   - Critical Infrastructure Act/Regulation — adoption status
   - Sectoral energy cybersecurity rules — adoption status
   - Establishment of a national Data Protection Authority or CERT/CSIRT
   The moment any of these change status, this SOP needs a **status flip, not a
   rewrite** — the procedural shape (contract-first, then statutory if/when one
   applies) stays the same; only step 2's "no statutory authority" conclusion
   changes.
4. **Cross-border data note**: because enclave workspaces run in Azure South
   Africa North, a regulatory notification obligation — once one exists — may
   implicate both Liberian and South African frameworks. Flag this explicitly to
   counsel when step 3 changes status; don't assume Liberian law alone governs.
