# LEC Reference Architecture → Factory Mapping
How the LEC Option B (Hybrid All-Azure) proposal infrastructure maps onto this
repo. This is the template for any OT/utility enclave — LEC is enclave zero.

## Data path (proposal → Sentinel)

```
[Substation OT]                    [Control Room OT]
 Garland P1G TAP ──┐                Garland P1G TAP ──┐
                   ▼                                  ▼
          Defender for IoT sensor          Defender for IoT sensor
          (passive, local analysis)        (passive, local analysis)
                   │                                  │
                   └───────────┬──────────────────────┘
                               ▼
                    FortiGate OT boundary FW ── CEF syslog ──┐
                               │                             ▼
                        [IT / DMZ zone]              Egress server (FWD-SRV-01)
                    EMS / historian / jump ──────►   rsyslog disk buffer + AMA
                    (MDE agents, WinSec 4xxx)                │
                               │                             ▼
                               │              ═══ Waterfall data diode ═══
                               │                  (hardware one-way, TX-only laser)
                               ▼                             │
                     MDE cloud (native) ─────────┐           ▼
                                                 ▼    DCE (southafricanorth)
                                          Sentinel workspace: law-dc-lec-prod
                                                 │
                                                 ▼
                              Dovetail SOC (Lighthouse, multi-workspace queue)
```

## Component → factory mapping

| LEC proposal component | Factory element |
|---|---|
| Defender for IoT sensors (TAP-fed) | `modules/connectors.bicep` — D4IoT connector + incident-creation rule (`profile = 'ot'`) |
| FortiGate OT boundary firewall | CEF DCR (`dcr-dc-<enclave>-cef`) + FortiGate analytics rules + boundary hunting queries |
| Egress server behind data diode | `modules/forwarder.bicep` (cloud twin for dev/demo); prod = physical Ubuntu via Azure Arc, same rsyslog buffer config |
| MDE on EMS/historian/jump hosts | MDE connector + incident rule; WinSec DCR for 4xxx events |
| Tenable.io (IT VA) | Out of factory scope — feeds via Tenable connector later; OT VA is native D4IoT |
| Asset inventory (EO 163 §60-day) | `content/watchlists/critical-assets.csv` — seeded from proposal asset list, joined by 3 analytics rules |

## Diode-specific SOC implications (why two "silence" detections exist)
A hardware unidirectional gateway means the SOC **cannot probe inbound**. You
cannot ping the sensor, poll the TAP, or health-check the egress server from
the cloud side. Detection of pipeline failure must be inferred from absence:

1. **Forwarder heartbeat loss** (High) — whole pipeline down: egress server,
   diode TX, or uplink. In Monrovia, uplink outage is the base-rate cause;
   the rsyslog 8GB disk buffer means data drains on recovery, but the SOC is
   blind in real time — treat as an availability incident regardless.
2. **OT telemetry silence per device** (Medium) — heartbeat healthy but one
   source went quiet: TAP failure, sensor fault, or someone reconfigured
   logging at the source. This one catches partial failures the heartbeat
   rule can't see.

Anything that can't be reached must be inferred; anything inferred needs a
baseline. Keep `critical-assets.csv` accurate or both mechanisms degrade.

## Prod forwarder build (physical egress server)
1. Ubuntu 22.04 LTS, 64GB+ disk (8GB rsyslog buffer + headroom).
2. Apply `/etc/rsyslog.d/10-dovetail-buffer.conf` — identical content to the
   cloud-init block in `modules/forwarder.bicep`.
3. Onboard via Azure Arc from the enclave subscription:
   ```bash
   wget https://aka.ms/azcmagent -O install_linux_azcmagent.sh && bash install_linux_azcmagent.sh
   azcmagent connect --resource-group "dc-lec-sentinel-rg" \
     --tenant-id "<enclave-tenant>" --subscription-id "<enclave-sub>" \
     --location "southafricanorth"
   ```
4. Add the AMA extension and DCR associations to the Arc machine (same three
   DCRs the cloud twin uses; swap the `scope` in a copy of the association
   resources or run `az monitor data-collection rule association create`
   against the Arc resource ID).
5. Validate: `./scripts/validate-enclave.ps1` heartbeat check covers Arc
   machines automatically once AMA reports in.

Note: Arc onboarding requires **outbound** 443 only — compatible with the
diode posture as long as the Arc/AMA egress path is on the diode's transmit
side. Confirm with the diode vendor that HTTPS session establishment is
handled by their TX proxy (Waterfall/Owl both support this pattern).
