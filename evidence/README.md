# Evidence

Real output from the lab, named by build section so each item maps to the [build log](../docs/build-log.md). IP addresses, locations, my admin sign-in name and the certificate thumbprint are cropped or blacked out.

## Logs (`logs/`)

| File | What it shows |
|---|---|
| `jml-run-*.log` | Scale test day 2, run by the scheduled task as `PDS\gmsa-jml$` |
| `leaver-*.csv` | Timestamped leaver steps |
| `sod-alerts.csv` | SoD decisions: denied, allowed by exception, denied |
| `privileged-review-*.csv` | Final privileged access review: no findings |

## 1.3 Admin tiering
**Role groups with their purpose in the description**
![](screenshots/1.3-role-groups.png)
**Helpdesk (t2) resets a normal user, and is denied on a Tier 1 admin**
![](screenshots/1.3-helpdesk-delegation-test.png)

## 1.4 Hybrid identity
**OU filtering: only People, Groups/Role and Disabled sync**
![](screenshots/1.4-entra-connect-ou-filtering.png)
**Role groups in Entra, Source: Windows Server AD**
![](screenshots/1.4-entra-groups-source-ad.png)

## 1.5 Lifecycle automation
**Joiner run: birthright groups, program access only when every check passes**
![](screenshots/1.5-joiner-run.png)
**Mover: PM approval arrives, the script grants Shipboard, the next run finds nothing to fix**
![](screenshots/1.5-mover-approval-run.png)
**Entra after the transfer: Aisha in Shipboard, gone from Radar**
![](screenshots/1.5-entra-shipboard-members.png)
![](screenshots/1.5-entra-radar-members.png)
**Manual leaver: sessions revoked in Entra, then account disabled with 0 groups**
![](screenshots/1.5-manual-leaver-erin-revoke.png)
![](screenshots/1.5-manual-leaver-erin-disabled.png)
**Graph app: two application permissions, certificate only, no client secrets**
![](screenshots/1.5-graph-app-permissions.png)
![](screenshots/1.5-graph-app-certificate.png)
**Leaver run, timestamped**
![](screenshots/1.5-leaver-run.png)
**Sign-ins around the leaver run, and the moment Entra learned the account was disabled**
![](screenshots/1.5-brian-signin-logs.png)
![](screenshots/1.5-brian-audit-accountenabled.png)
**Measured offboarding timeline**
![](screenshots/1.5-leaver-exposure-timeline.png)
**SoD denial in the Windows event log**
![](screenshots/1.5-sod-event-5001.png)
**The engine's service account: delegations, batch logon right, sync operator**
![](screenshots/1.5-gmsa-delegations.png)
![](screenshots/1.5-gmsa-batch-logon-gpo.png)
![](screenshots/1.5-gmsa-adsyncoperators.png)
**Scheduled task ran as the gMSA with result 0**
![](screenshots/1.5-scheduled-task-gmsa-run.png)
**Scale test day 2: every change the engine made, plus the sync it triggered**
![](screenshots/1.5-scale-day2-changes.png)

## 1.6 Security review
**Domain Admins members: a group with a boring name**
![](screenshots/1.6-domain-admins-members.png)
**The review traces the nested path**
![](screenshots/1.6-review-finding.png)
**Every Domain Admins addition, from Security event 4728**
![](screenshots/1.6-event-4728-history.png)
**SDProp stamps adminCount=1 and blocks inheritance**
![](screenshots/1.6-sdprop-admincount.png)
**After removal, the orphan remains**
![](screenshots/1.6-review-orphan.png)
**After the fix: the helpdesk reset works and the review is clean**
![](screenshots/1.6-review-clean-after-fix.png)
