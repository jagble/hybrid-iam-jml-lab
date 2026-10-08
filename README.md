# Hybrid IAM Lab: Automated Joiner-Mover-Leaver for AD + Entra ID



I built a hybrid identity environment for a fictional defense contractor, **Potomac Defense Systems (PDS)**

A tiered Active Directory domain synced to Entra ID, a PowerShell engine that creates, changes and removes access from an HR file, and the security controls around it. I tested the environment with **340 employees**, measured how long a terminated employee could still get in, and ran a security review that found a Domain Admin hidden behind a nested group, plus two additional problems that unexpectedly came up.


## What I Built

Each part is a step-by-step walkthrough with annotated screenshots.

| Part | Title | What I Built | Key Takeaway |
|:---:|---|---|---|
| **1.1** | [**Access Model Design: Tiered OUs + RBAC**](parts/1.1-plan-and-design/README.md) | Security-tiered OUs, role model, HR roster, and access rules | Access comes from roles and attributes, not "make her like Bob" |
| **1.2** | [**Active Directory Build in Azure**](parts/1.2-build-the-domain/README.md) | Azure domain controller, DNS, 21 OUs, and budget controls | Three failed VM deployments taught me how Azure quotas really work |
| **1.3** | [**Admin Tiering + Delegated Administration**](parts/1.3-admin-tiering/README.md) | Tier 0/1/2 admin accounts, AGDLP groups, and helpdesk delegation | Tested as the helpdesk: password reset allowed on a user, **Access is denied** on an admin |
| **1.4** | [**Hybrid Identity with Entra Connect Sync**](parts/1.4-hybrid-identity/README.md) | Entra Connect Sync, OU filtering, and Tier 0 protection | Only 3 OUs reach the cloud. Admin accounts never do |
| **1.5** | [**JML Automation: Joiner, Mover, Leaver**](parts/1.5-lifecycle-automation/README.md) | PowerShell JML engine, Graph API, gMSA, SoD checks, and 340-user test | A fired employee's old password still worked at 79 s, and my "dry run" wasn't dry |
| **1.6** | [**Privileged Access Review**](parts/1.6-security-review/README.md) | Privileged group review, nested group analysis, event 4728, and AdminSDHolder checks | Found my planted Domain Admin, plus two problems I didn't plant |



---

## Results

| Area                         | Result                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Identity lifecycle**       | Managed **340 employees**, including 306 created in one run and 22 overnight HR changes, all matching a pre-written answer key |
| **Offboarding**              | Entra sessions revoked in **1 second**. Old password still accepted in the cloud **at 79 seconds**           |
| **Sync improvement**         | Account showed disabled in Entra after **~3 minutes** with a forced sync vs. **~29 minutes** on the default schedule, so the leaver now triggers the sync itself |
| **Secrets**                  | **Zero passwords or client secrets** stored in the automation engine                                         |
| **Automation security**      | Microsoft Graph app uses certificate authentication; automation runs as a gMSA                               |
| **Least privilege**          | Graph app has only **2 permissions**; automation account has no administrative rights                        |
| **Separation of duties**     | **3/3 tests passed** for Finance + Accounts Payable conflicts                                                |
| **Privileged access review** | Found a hidden Domain Admin path, standing Enterprise/Schema Admin membership, and an AdminSDHolder leftover that broke helpdesk resets |


---

## Architecture

```text
 HR roster (CSV)                          Microsoft Entra ID
      │                                    ▲              ▲
      ▼                                    │ sync         │ revoke sessions
 ┌────────────────────────────┐            │ (PHS,        │ (Graph API,
 │ JML engine on FRD-DC-01    │            │ OU-filtered) │ certificate auth)
 │ scheduled task as gMSA     │            │              │
 │ joiner → mover →           │───────────────────────────┘
 │ leaver → SoD check         │            │
 └─────────────┬──────────────┘   ┌────────┴────────┐
               │ creates /        │  FRD-SYNC-01    │
               │ changes /        │  Entra Connect  │
               ▼ disables         │  Sync (Tier 0)  │
 ┌────────────────────────────┐   └────────▲────────┘
 │ Active Directory           │────────────┘ (leaver triggers a delta sync)
 │ ad.potomacdefense.internal │
 │ Tier 0/1/2 OUs, People,    │
 │ role + resource groups     │
 └────────────────────────────┘
```

### Environment

* **Azure VMs**

  * `FRD-DC-01` — Domain Controller
  * `FRD-SYNC-01` — Entra Connect Sync server (has **no inbound ports** and is accessed through the domain controller)
* Active Directory is the **source of truth**
* Password Hash Synchronization (PHS) for cloud sign-in
* Only `People`, `Groups\Role` and `Disabled` sync to Entra. Admin accounts, service accounts and resource groups stay in Active Directory

---

## How It Works

**Joiner:** creates accounts from HR with birthright access by job role. Program (CUI) access is granted only when the person is assigned to the program, has CUI training, is a US person, and has PM approval. Future hires are created disabled.

**Mover:** fixes drift when department, job, program, manager or start date changes. It **removes old access before adding new access**, so a failure leaves too little access, never too much.

**Leaver:** cuts access first (disable, scramble password, revoke Entra sessions through Microsoft Graph), cleans up second (groups, manager, move to `Disabled`), logs every step, then triggers a sync.

**Why the leaver works this way:** during testing, an employee's old password was still accepted in the cloud **79 seconds after offboarding**.

> Disabling an on-premises account does not mean cloud access disappears immediately.

The leaver now triggers a sync itself, cutting the ~29-minute "still enabled in Entra" window to ~3 minutes. Closing the password gap completely needs a Conditional Access block group (see production changes below).

**Security review:** a read-only script expands 12 privileged groups recursively, keeping the full nesting path, and flags AdminSDHolder leftovers. I investigated with Security event 4728 before cleaning up, fixed all three findings, and re-ran the review clean. [Findings report](docs/04-privileged-access-review.md).

---

## Design Decisions

### Use EmployeeID Instead of Names

EmployeeID is used to match:

**HR → AD → Entra → Manager relationships**

Names can change or be duplicated. EmployeeID provides a more reliable identity key.

### Use Attributes for Program Access

Program access is based on employee attributes rather than moving accounts between OUs.

```text
Employee transfers programs
        ↓
Update employee attributes
        ↓
JML engine evaluates access
        ↓
Old access removed
        ↓
New access added
```

### Remove Before Adding

The engine removes outdated access before adding new access. This is a **fail-closed** approach:

> If something fails during the process, the employee should have too little access rather than too much.

### Only Reverse What the Engine Changed

The engine does not blindly re-enable disabled accounts. It only re-enables accounts it disabled itself (marked **Pre-start**). Other disabled accounts are flagged for review, since security may have disabled them on purpose.

### Certificates and gMSAs Instead of Passwords

The Graph app signs in with a certificate whose private key can't be exported, and the engine runs as a group Managed Service Account whose password nobody knows. There is no secret to leak into a script, a chat or GitHub.

### Detective + Corrective Controls

Active Directory cannot prevent a risky group combination. So the SoD check:

1. Detects conflicting access
2. Checks for an approved exception (not expired, 14 days max, not approved by the person or their own manager)
3. Removes the access that doesn't match their job
4. Writes an event log alert a SIEM can pick up

---

## What's in This Repository

| Path                                                                         | Description                                                  |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------ |
| [`parts/`](parts/)                                                           | Six detailed walkthroughs with annotated screenshots         |
| [`docs/01-directory-design.md`](docs/01-directory-design.md)                 | OU structure, admin tiering, AGDLP, and sync scope           |
| [`docs/02-role-map.md`](docs/02-role-map.md)                                 | Birthright access, program access, SoD rules, and exceptions |
| [`docs/03-jml-runbook.md`](docs/03-jml-runbook.md)                           | Manual JML procedures and automated equivalents              |
| [`docs/04-privileged-access-review.md`](docs/04-privileged-access-review.md) | Privileged access review findings                            |
| [`docs/build-log.md`](docs/build-log.md)                                     | Condensed build notes                                        |
| `scripts/03-joiner.ps1`                                                      | Creates users and assigns initial access                     |
| `scripts/04-mover.ps1`                                                       | Updates access when employee information changes             |
| `scripts/05-leaver.ps1`                                                      | Handles offboarding and cloud session revocation             |
| `scripts/06-sod-check.ps1`                                                   | Detects Finance + AP conflicts                               |
| `scripts/07-privileged-access-review.ps1`                                    | Reviews privileged groups and nested access (read-only)      |
| `scripts/run-jml.ps1`                                                        | Runs the complete JML process                                |
| `data/`                                                                      | HR rosters, answer keys, and SoD exception data              |
| `evidence/`                                                                  | Logs, screenshots, and test evidence                         |

---

## Evidence

| Evidence                                | What It Demonstrates                                     |
| --------------------------------------- | -------------------------------------------------------- |
| `evidence/logs/jml-run-*.log`           | JML engine processing joiners, movers, leavers, and sync |
| `evidence/logs/leaver-*.csv`            | Timestamped offboarding activity                         |
| `evidence/logs/sod-alerts.csv`          | SoD decisions and exceptions                             |
| `evidence/logs/privileged-review-*.csv` | Final privileged access review                           |
| [`evidence/`](evidence/README.md)       | Screenshot gallery of the project                        |

---

## What I Would Change for Production

This lab is intentionally built in a personal Azure environment. In a production environment, I would:

* Run the JML engine from a dedicated **Tier 0 management server**
* Use an **IGA platform** such as Entra ID Governance or SailPoint for access requests and approvals
* Add a **Conditional Access block group** so leavers are blocked in the cloud without waiting on sync
* Load AD once per run instead of one lookup per person, for environments with **10,000+ users**
* Send JML and privileged access events to a **SIEM** such as Microsoft Sentinel or Splunk
* Approve privileged access per **account + group pair**, and use **BloodHound** to find ACL-based privilege paths
* Replace direct RDP access with **Azure Bastion or Just-In-Time VM access**
* Store certificates in **Azure Key Vault or an HSM**, with a rotation procedure
* Delete disabled accounts after the required retention period

---

## Skills Demonstrated

**Identity & Access Management**

Active Directory · Microsoft Entra ID · Hybrid Identity · Identity Lifecycle Management · Joiner/Mover/Leaver (JML) · RBAC · Attribute-Based Access Control · Least Privilege · Separation of Duties · Privileged Access Review

**Microsoft & Cloud**

Azure · Entra Connect Sync · Password Hash Synchronization · Microsoft Graph API · App Registrations · Certificate Authentication · Azure VMs

**Automation**

PowerShell · gMSA · Task Scheduler · HR-driven automation · Audit logging · Scripted access reviews

**Security**

Admin Tiering · AGDLP · AdminSDHolder · Windows Security Event Analysis · NIST SP 800-171 alignment

---

## Project Goal

I wanted to build an identity system that controls access across the whole employee lifecycle, from the first day to job changes to the last day, and then prove it works by measuring it, scaling it, and trying to break it.

---

Built by **Josh Agble** · [github.com/jagble](https://github.com/jagble)
