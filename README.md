# PDS Identity Foundation

**Hybrid Active Directory + Microsoft Entra ID with automated Joiner, Mover, and Leaver (JML) processes**

I built a hybrid identity environment for a fictional defense contractor, **Potomac Defense Systems (PDS)**.

The lab combines:

* Active Directory
* Microsoft Entra ID
* PowerShell automation
* HR-driven identity lifecycle management
* Role-based access control (RBAC)
* Separation of duties (SoD)
* Privileged access reviews
* Secure service accounts and application authentication

I tested the environment with **340 employees**, measured the offboarding process, and performed a security review that successfully found a hidden Domain Admin account.

> **About this lab:** PDS is a fictional defense and space contractor. All people, accounts, programs, and data are fictional. The lab runs in my own Azure subscription and Entra ID tenant. HR data and some initial PowerShell code were created with LLM assistance. I designed the identity controls, executed the scripts, tested the environment, troubleshot failures, and verified the results myself. The six walkthroughs document the full build, including mistakes and fixes.

---

## Results at a Glance

| Area                         | Result                                                                                                              |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **Identity lifecycle**       | Managed **340 employees**, including 306 created in one run and 22 overnight HR changes                             |
| **Offboarding**              | Entra sessions revoked in **1 second**. Old password remained usable in the cloud for **79 seconds** during testing |
| **Sync improvement**         | Entra account showed disabled after **~3 minutes** with a forced sync vs. **~29 minutes** on the default schedule   |
| **Secrets**                  | **Zero passwords or client secrets** stored in the automation engine                                                |
| **Automation security**      | Microsoft Graph app uses certificate authentication; automation runs as a gMSA                                      |
| **Least privilege**          | Graph app has only **2 permissions**; automation account has no administrative rights                               |
| **Separation of duties**     | **3/3 tests passed** for Finance + Accounts Payable conflicts                                                       |
| **Privileged access review** | Found a hidden Domain Admin, unexpected Enterprise/Schema Admin membership, and an AdminSDHolder issue              |

---

## What I Built

The project is divided into six stages:

|                                    Part                                    | What I Built                                                                         | Key Takeaway                                                                      |
| :------------------------------------------------------------------------: | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
|       [**1.1 — Plan & Design**](parts/1.1-plan-and-design/README.md)       | Security-tiered OUs, role model, HR roster, and access rules                         | Access should be based on roles and attributes, not copying another user's access |
|     [**1.2 — Build the Domain**](parts/1.2-build-the-domain/README.md)     | Azure domain controller, DNS, 21 OUs, and budget controls                            | Troubleshot multiple VM deployment and quota issues                               |
|        [**1.3 — Admin Tiering**](parts/1.3-admin-tiering/README.md)        | Tier 0/1/2 admin accounts, AGDLP groups, and helpdesk delegation                     | Helpdesk could manage users but could not manage privileged accounts              |
|      [**1.4 — Hybrid Identity**](parts/1.4-hybrid-identity/README.md)      | Entra Connect Sync, OU filtering, and Tier 0 protection                              | Only approved OUs sync to Entra; admin accounts remain on-premises                |
| [**1.5 — Lifecycle Automation**](parts/1.5-lifecycle-automation/README.md) | PowerShell JML engine, Graph API, gMSA, SoD checks, and 340-user test                | Measured the real-world impact of offboarding delays                              |
|      [**1.6 — Security Review**](parts/1.6-security-review/README.md)      | Privileged group review, nested group analysis, event 4728, and AdminSDHolder checks | Found both planted and previously unknown privilege issues                        |

![Measured offboarding timeline](evidence/screenshots/1.5-leaver-exposure-timeline.png)

---

## Architecture

```text
 HR roster (CSV)                       Microsoft Entra ID
      │                                 ▲            ▲
      ▼                                 │ sync       │ revoke sessions
 ┌─────────────────────────┐            │ (PHS,      │ (Graph API,
 │ JML engine on FRD-DC-01  │            │ OU-filtered)│ certificate auth)
 │ scheduled task as gMSA  │            │            │
 │ joiner → mover →        │──────────────────────────┘
 │ leaver → SoD check      │            │
 └───────────┬─────────────┘   ┌────────┴────────┐
             │ creates /       │  FRD-SYNC-01    │
             │ changes /       │  Entra Connect  │
             ▼ disables        │  Sync (Tier 0)  │
 ┌─────────────────────────┐   └────────▲────────┘
 │ Active Directory         │────────────┘ (leaver triggers a delta sync)
 │ ad.potomacdefense.internal│
 │ Tier 0/1/2 OUs, People,  │
 │ role + resource groups   │
 └─────────────────────────┘
```

### Environment

* **Azure VMs**

  * `FRD-DC-01` — Domain Controller
  * `FRD-SYNC-01` — Entra Connect Sync server
* `FRD-SYNC-01` has **no inbound ports** and is accessed through the domain controller
* Active Directory is the **source of truth**
* Password Hash Synchronization (PHS) is used for Entra synchronization
* Only approved OUs are synchronized to Entra
* Administrative and service accounts remain on-premises

### Entra Sync Scope

Only these areas are synchronized:

* `People`
* `Groups\Role`
* `Disabled`

The following remain in Active Directory:

* Tier 0/1/2 administrative accounts
* Service accounts
* Resource groups

---

## Identity Lifecycle Automation

The JML engine processes employee changes from an HR CSV.

### Joiner

Creates new employees and assigns access based on:

* Department
* Job role
* Program
* Start date
* Required training
* Eligibility requirements

### Mover

Updates access when an employee changes:

* Department
* Job role
* Program
* Manager
* Start date

### Leaver

When an employee leaves, the engine:

1. Disables the AD account
2. Randomizes the password
3. Revokes Entra sessions through Microsoft Graph
4. Removes access managed by the engine
5. Moves the account to the disabled area
6. Triggers an Entra sync
7. Records the actions in an audit log

### Why this matters

During testing, I found that an employee's old password could still work in the cloud **79 seconds after offboarding began**.

That exposed an important identity-management issue:

> Disabling an on-premises account does not automatically mean cloud access disappears immediately.

I changed the process so the leaver workflow **revokes cloud sessions and triggers synchronization immediately**.

---

## Security Controls

### Least Privilege

The automation engine follows least-privilege principles.

* Microsoft Graph application uses only **2 permissions**
* Automation account has **no administrative rights**
* Access is delegated only to the required areas
* Helpdesk permissions are limited to normal user accounts
* Privileged accounts are protected by administrative tiering

### Secure Authentication

The automation engine does not store a service account password.

Instead:

* Microsoft Graph uses **certificate authentication**
* The certificate uses a **non-exportable key**
* The Windows automation process runs as a **group Managed Service Account (gMSA)**
* No password needs to be stored in the PowerShell scripts

### Separation of Duties

The lab includes a Finance + Accounts Payable conflict rule.

The system tests whether a person receives conflicting access and checks for approved exceptions.

Tests included:

* Conflict denied
* Valid exception allowed
* Self-approved exception denied

**Result: 3/3 tests passed**

---

## Privileged Access Review

I created a read-only security review that examines privileged Active Directory access.

The review checks:

* Privileged groups
* Nested group membership
* Group membership paths
* Windows Security Event ID 4728
* AdminSDHolder
* Unexpected administrative access

### Findings

The review successfully found:

* A hidden **Domain Admin** through nested group membership
* Unexpected **Enterprise Admin** membership
* Unexpected **Schema Admin** membership
* An **AdminSDHolder** issue affecting helpdesk password resets

The findings were corrected and the review was run again to verify the environment was clean.

---

## Design Decisions

### Use EmployeeID Instead of Names

EmployeeID is used to match:

**HR → AD → Entra → Manager relationships**

Names can change or be duplicated. EmployeeID provides a more reliable identity key.

### Use Attributes for Program Access

Program access is based on employee attributes rather than moving accounts between OUs.

For example:

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

The engine removes outdated access before adding new access.

This follows a **fail-closed** approach:

> If something fails during the process, the employee should have too little access rather than too much.

### Only Reverse What the Engine Changed

The engine does not blindly re-enable disabled accounts.

It only re-enables accounts that were disabled because they were marked as **Pre-start**.

Other disabled accounts are flagged for review.

### Detective + Corrective Controls

Active Directory cannot prevent every toxic access combination.

Therefore, the SoD process:

1. Detects conflicting access
2. Checks for an approved exception
3. Records the decision
4. Generates an event log alert

The event log can then be monitored by a SIEM.

---

## What's in This Repository

| Path                                                                         | Description                                                  |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------ |
| [`parts/`](parts/)                                                           | Six detailed walkthroughs with screenshots                   |
| [`docs/01-directory-design.md`](docs/01-directory-design.md)                 | OU structure, admin tiering, AGDLP, and sync scope           |
| [`docs/02-role-map.md`](docs/02-role-map.md)                                 | Birthright access, program access, SoD rules, and exceptions |
| [`docs/03-jml-runbook.md`](docs/03-jml-runbook.md)                           | Manual JML procedures and automated equivalents              |
| [`docs/04-privileged-access-review.md`](docs/04-privileged-access-review.md) | Privileged access review findings                            |
| [`docs/build-log.md`](docs/build-log.md)                                     | Condensed build notes                                        |
| `scripts/03-joiner.ps1`                                                      | Creates users and assigns initial access                     |
| `scripts/04-mover.ps1`                                                       | Updates access when employee information changes             |
| `scripts/05-leaver.ps1`                                                      | Handles offboarding and cloud session revocation             |
| `scripts/06-sod-check.ps1`                                                   | Detects Finance + AP conflicts                               |
| `scripts/07-privileged-access-review.ps1`                                    | Reviews privileged groups and nested access                  |
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
* Add a **Conditional Access block group** for immediate cloud blocking of leavers
* Optimize AD queries for environments with **10,000+ users**
* Send JML and privileged access events to a **SIEM** such as Microsoft Sentinel or Splunk
* Use **BloodHound** to identify ACL-based privilege paths
* Replace direct RDP access with **Azure Bastion or Just-In-Time VM access**
* Store certificates in **Azure Key Vault or an HSM**
* Add certificate rotation and expiration procedures
* Delete disabled accounts after the required retention period

---

## Skills Demonstrated

**Identity & Access Management**

Active Directory · Microsoft Entra ID · Hybrid Identity · Identity Lifecycle Management · Joiner/Mover/Leaver (JML) · RBAC · Attribute-Based Access Control · Least Privilege · Separation of Duties · Privileged Access Management

**Microsoft & Cloud**

Azure · Entra Connect Sync · Password Hash Synchronization · Microsoft Graph API · App Registrations · Certificate Authentication · Azure VMs

**Automation**

PowerShell · gMSA · Task Scheduler · HR-driven automation · Audit logging · Automated access reviews

**Security**

Admin Tiering · AGDLP · Privileged Access Reviews · AdminSDHolder · Windows Security Events · SIEM Integration · NIST SP 800-171 alignment

---

## Project Goal

The goal of this project was not simply to build Active Directory.

It was to build and test an **identity system that controls access throughout the employee lifecycle** — from onboarding, to job changes, to offboarding — while applying least privilege, automation, security controls, and measurable verification.
