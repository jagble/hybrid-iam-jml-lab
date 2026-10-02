# Directory Design: Potomac Defense Systems (PDS)

| | |
|---|---|
| **Author** | Jordan Carter, IAM Engineer |
| **Status** | Approved for build (Project 1, Step 3 onward) |
| **Scope** | On-prem Active Directory structure, admin tiering, naming standards, Entra ID sync scope |

## 1. Context

Potomac Defense Systems is a defense and space contractor with about 300 employees and 40 subcontractors across Fredericksburg (HQ), Dahlgren and Chantilly. Engineers and analysts are staffed on government programs (fictional codenames KESTREL, HARBOR and ANVIL), and access to program data is granted on a need-to-know basis. Program data is CUI (simulated), and export-controlled data may only be accessed by US persons. Access today is granted by copying a coworker's permissions, so nobody can say who should have what. This design replaces that with a structure built around security boundaries.

All people, accounts and data are fictional and synthetic. Nothing in this lab is classified.

## 2. Domain

**Domain:** `ad.potomacdefense.internal`
**Hosting:** domain controller and Entra Connect sync server run as Azure VMs.

**Known lab deviations:**
- PDS does not own a public domain, so synced users receive `@<tenant>.onmicrosoft.com` sign-in names in Entra ID. In production, the AD domain would be a subdomain of an owned domain (for example `ad.potomacdefense.com`) with a matching UPN suffix.
- Contractors handling CUI often run Microsoft's government clouds (GCC High). This lab uses the commercial cloud.

## 3. OU structure

OUs exist for three reasons only: Group Policy, delegation, and sync scope. Each OU below states which one it serves.

```
ad.potomacdefense.internal
├── Domain Controllers      # Default OU. DCs stay here; Default Domain Controllers Policy applies
└── PDS
    ├── Tier0
    │   ├── Admins          # t0- accounts. Not synced
    │   ├── Groups          # Groups that grant Tier 0 rights
    │   └── Servers         # Entra Connect sync server. Tier 0 hardening GPO
    ├── Tier1
    │   ├── Admins          # t1- accounts. Not synced
    │   ├── Groups          # Groups that grant Tier 1 rights
    │   └── Servers         # File server, ProgramHub app and SQL servers. Server baseline GPO
    ├── Tier2
    │   ├── Admins          # t2- helpdesk accounts. Not synced
    │   ├── Groups          # Groups that grant Tier 2 rights
    │   └── Workstations    # Staff laptops. Workstation baseline GPO
    ├── People              # Synced to Entra ID
    │   ├── Employees       # Helpdesk password-reset delegation
    │   └── Subcontractors  # Helpdesk password-reset delegation. Expiry date mandatory
    ├── Groups
    │   ├── Role            # GG-Role-* groups that hold people. Synced
    │   └── Resource        # DL-* groups that receive permissions. Not synced
    ├── ServiceAccounts     # svc-* accounts. GPO denies interactive and RDP logon. Not synced
    └── Disabled            # Leavers, 30-day hold. Synced so the cloud account stays disabled, not deleted. No helpdesk rights
```

Office and program are **not** OUs. They don't change Group Policy, delegation or sync scope, so they're stored as account attributes and expressed as group membership.

**Attributes that drive access:**

| Attribute | Example | Used for |
|---|---|---|
| `Office` | Dahlgren | Location reporting |
| `Department` | Engineering | Role-group assignment (Project 2) |
| Program assignment | KESTREL | Need-to-know program access |
| US-person status | Yes / No | Export-controlled data access |

Program and US-person status are stored in AD extension attributes and become the basis for attribute-based dynamic groups in Project 3 (ABAC). Access follows the attributes automatically, so a person who leaves a program or lacks US-person status loses or never receives that access.

## 4. Admin tier model

| Tier | Contains | Administered by | Admin account | May sign in to |
|---|---|---|---|---|
| 0 | Domain controllers, AD, Entra Connect sync server, Tier 0 groups | IAM / identity team | `t0-jcarter` | Tier 0 systems only |
| 1 | File server, ProgramHub app and SQL servers | Infrastructure team | `t1-jcarter` | Tier 1 servers only |
| 2 | Workstations, standard user accounts | Helpdesk | `t2-jcarter` | Workstations only |

**Rule:** a higher-tier account never signs in to a lower-tier system, so its credential can't be stolen from a more exposed machine. Daily accounts (`jordan.carter`) hold no admin rights anywhere.

The Entra Connect sync server is Tier 0 even though it isn't a domain controller. Its service account can read every user's password hash, and it can write to Entra ID, so compromising it compromises both directories.

## 5. Naming standards

| Object | Pattern | Example | Notes |
|---|---|---|---|
| User | `first.last` | `jordan.carter` | Collisions add a middle initial (`jordan.m.carter`). Max 20 characters |
| Admin account | `t<tier>-<initial><last>` | `t0-jcarter` | Tier visible in the name and in logs |
| Service account | `svc-<app>-<purpose>` | `svc-programhub-sql` | Owner recorded in the description field |
| Computer | `<site>-<type>-<nn>` | `FRD-LT-014`, `DAH-LT-007`, `AZ-DC-01` | Max 15 characters (NetBIOS limit) |
| Role group | `GG-Role-<role>` | `GG-Role-Kestrel-Engineers` | Global group; holds users |
| Resource group | `DL-<type>-<resource>-<access>` | `DL-Share-Kestrel-CUI-Modify` | Domain local; holds role groups; receives permissions |
| Admin group | `GG-T<tier>-<function>` | `GG-T2-Helpdesk` | Lives in its tier's Groups OU |

## 6. Entra ID sync scope

**Synced:** `People` (Employees and Subcontractors), `Groups\Role`, and `Disabled`. These are the identities and groups that need cloud access. Disabled syncs so a leaver's cloud account stays intact but disabled for the 30-day hold, instead of being deleted the moment it leaves sync scope.

**Not synced:** every `Admins` OU, `ServiceAccounts`, and `Groups\Resource`. Privileged and non-human accounts have no business in the cloud, so they can't be attacked or abused from there. Cloud administration uses separate cloud-only admin accounts (Project 3). Resource groups only grant on-prem permissions.

## 7. Requirements traceability

| # | Requirement | How the design meets it |
|---|---|---|
| 1 | Three offices, three programs | Attributes and role groups, not OUs |
| 2 | Subcontractors separable; access ends at contract end | `People\Subcontractors` OU; mandatory AD expiry date; the JML engine (Project 2) also disables the account in Entra, because the AD expiry date does not carry over to Entra by default |
| 3 | Service accounts isolated, no interactive logon | `ServiceAccounts` OU with a deny-logon GPO; never synced |
| 4 | Leavers held 30 days before deletion | `Disabled` OU, synced; deletion after 30 days handled in Project 2 |
| 5 | Helpdesk resets standard users only | Password-reset delegation on `People\Employees` and `People\Subcontractors` only; admin and service accounts sit outside those OUs |
| 6 | Separate admin accounts per tier | `Tier*\Admins` OUs, `t<tier>-` naming, tier logon restrictions (Step 6) |
| 7 | Only identities that need the cloud get synced | Sync scope in section 6 |
| 8 | Program data is need-to-know; export-controlled data is US persons only | Program and US-person attributes (section 3), enforced with dynamic groups in Project 3 |

## 8. Decision log

| Decision | Choice | Reason |
|---|---|---|
| Top-level OU split | By tier and object type, not department | Delegation applies to everything in an OU. Mixing admin accounts into department OUs would let helpdesk reset admin passwords, a privilege-escalation path |
| Subcontractors | Own sub-OU under People | Lets reports, cleanup and future delegation target them without touching employees |
| Contract end enforcement | AD expiry date plus a disable in Entra | AD expiry alone doesn't stop cloud sign-in |
| Disabled OU sync | Synced | Keeps the cloud account and its data for the 30-day hold; removing it from scope would delete it in Entra |
| Sync server tier | Tier 0 | It can read all password hashes and write to Entra ID |
| Program and export access | Attributes, not OUs or manual groups | Access follows the person's attributes, so it's granted and removed automatically |

## 9. Lab deviations and open items

- **Non-routable domain:** `.internal` means onmicrosoft.com sign-in names (section 2).
- **Commercial cloud:** production CUI environments typically use GCC High (section 2).
- **One admin, all tiers:** Jordan Carter holds `t0`, `t1` and `t2` accounts because the lab has one administrator. In production, different people hold different tiers.
- **No physical workstations:** the `Workstations` OU exists for design completeness; the lab has no client machines yet.
- **No privileged access workstation:** a hardened admin-only machine for Tier 0 work is the production standard; noted, not built.
- **Open:** convert `svc-programhub-sql` to a group Managed Service Account (gMSA) so AD rotates its password. gMSA names have a shorter length limit, so it would need a shorter name. Decide in Step 5.
