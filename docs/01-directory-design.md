# Directory Design — Potomac Defense Systems

> **Summary:** An Active Directory design that organizes accounts by security level instead of department, keeps admin and service accounts separate from everyday users, grants access through roles and attributes instead of copying coworkers, and syncs only what needs the cloud to Entra ID.

> **About this lab:** Potomac Defense Systems is a fictional defense and space contractor I created for my IAM portfolio. Every person, account, program and piece of data is made up, and nothing is classified. The lab runs in my own Microsoft Entra ID tenant and Azure subscription.

**Domain:** `ad.potomacdefense.internal`
**Company:** ~300 employees + 40 subcontractors
**Locations:** Fredericksburg, Dahlgren, Chantilly
**Programs:** Radar (radar sensors), Satellite (satellite ground systems), Shipboard (shipboard combat software)

## 1. OU Structure

```text
ad.potomacdefense.internal
├── Domain Controllers     (built-in OU, DCs stay here)
└── PDS
    ├── Tier0
    │   ├── Admins
    │   ├── Groups
    │   └── Servers
    │
    ├── Tier1
    │   ├── Admins
    │   ├── Groups
    │   └── Servers
    │
    ├── Tier2
    │   ├── Admins
    │   ├── Groups
    │   └── Workstations
    │
    ├── People
    │   ├── Employees
    │   └── Subcontractors
    │
    ├── Groups
    │   ├── Role
    │   └── Resource
    │
    ├── ServiceAccounts
    └── Disabled
```

### What each OU is for

| OU                | Purpose                                                        |
| ----------------- | -------------------------------------------------------------- |
| `Tier0`           | Tier 0 admins and groups, plus the Entra Connect sync server   |
| `Tier1`           | Servers and business applications                              |
| `Tier2`           | Workstations and helpdesk admins                               |
| `People`          | Normal employee and subcontractor accounts                     |
| `Groups`          | Role and resource groups                                       |
| `ServiceAccounts` | Non-human accounts; blocked from interactive logon             |
| `Disabled`        | Departed users during 30-day retention                         |

The OU structure is based on **security boundaries, Group Policy, delegation, and sync scope** rather than department or location.

**Helpdesk rule:** the helpdesk can reset passwords only in `People\Employees` and `People\Subcontractors`. Admin and service accounts live outside those OUs, so the helpdesk can never reset them.

## 2. Administrative Tiering

| Tier       | Purpose                 | Example                      |
| ---------- | ----------------------- | ---------------------------- |
| **Tier 0** | Identity infrastructure | AD, DCs, Entra Connect       |
| **Tier 1** | Server infrastructure   | File/SQL/Application servers |
| **Tier 2** | User environment        | Workstations, helpdesk       |

Each tier has a separate administrator account:

```text
t0-jcarter → Tier 0
t1-jcarter → Tier 1
t2-jcarter → Tier 2
```

Higher-tier credentials are never used on lower-tier systems. Normal user accounts have no administrative privileges.

## 3. Groups & Access

```text
Users
  ↓
GG-Role-*
  ↓
DL-*
  ↓
Resource
```

Example:

```text
GG-Role-Radar-Engineers
        ↓
DL-Share-Radar-CUI-Modify
        ↓
Radar CUI File Share
```

**Global Groups (`GG-Role-*`)** hold users based on their role.

**Domain Local Groups (`DL-*`)** receive permissions to resources.

## 4. Access Attributes

Access is based on attributes rather than creating an OU for every office or program.

```text
Office
Department
Program
US-Person Status
```

Example:

```text
Jordan Carter
├── Department: Engineering
├── Office: Dahlgren
├── Program: Radar
└── US Person: Yes
```

These attributes can later drive dynamic groups and automated access decisions. Program data is need-to-know, and export-controlled data requires US-person status.

## 5. Naming Standards

```text
User:            first.last
Admin:           t<tier>-<initial><last>
Service Account: svc-<app>-<purpose>
Computer:        <site>-<type>-<nn>
Role Group:      GG-Role-<role>
Resource Group:  DL-<type>-<resource>-<access>
```

Examples:

```text
jordan.carter
t0-jcarter
svc-programhub-sql
FRD-LT-014
GG-Role-Radar-Engineers
DL-Share-Radar-CUI-Modify
```

## 6. Entra ID Sync

### Synced

```text
People
├── Employees
└── Subcontractors

Groups
└── Role

Disabled
```

### Not Synced

```text
Tier0\Admins
Tier1\Admins
Tier2\Admins
ServiceAccounts
Groups\Resource
```

The goal is to sync only identities and groups that actually require cloud access while keeping privileged and non-human accounts out of the cloud.

## 7. Why I Made These Choices

| Choice | Why |
| --- | --- |
| OUs split by tier and type, not department | Delegation covers a whole OU. Mixing admins into department OUs would let the helpdesk reset admin passwords |
| Subcontractors get their own OU | Reports, cleanup and policies can target them without touching employees |
| Subcontractor accounts get an AD expiry date **and** get disabled in Entra | The AD expiry date doesn't carry over to Entra by default, so it alone won't stop cloud sign-in |
| `Disabled` OU is synced | Keeps the cloud account disabled, not deleted, during the 30-day hold |
| Entra Connect server is Tier 0 | It can read every password hash and write to Entra ID |
| Program and US-person access come from attributes | Access is granted and removed automatically as attributes change |

## 8. Design Principles

* **Least privilege**
* **Tiered administration**
* **Role-based access**
* **Need-to-know access**
* **Separation of privileged and standard accounts**
* **Automated lifecycle management**
* **Minimal cloud synchronization**

### Example Access Flow

```text
Employee
   ↓
Department / Program / Attributes
   ↓
Role Group
   ↓
Resource Group
   ↓
Resource Access
```

This design replaces manually copying another employee's permissions with a structured IAM model based on **roles, attributes, and security boundaries**.

## 9. Lab Notes

* **Sign-in names:** the lab doesn't own a public domain, so synced users get `@<tenant>.onmicrosoft.com` names in Entra ID. In production the domain would match the company's email domain.
* **Cloud:** contractors handling CUI often use Microsoft's government cloud (GCC High). This lab uses the commercial cloud.
* **One admin:** Jordan Carter holds all three tier accounts because the lab has one administrator. In production, different people hold different tiers.
