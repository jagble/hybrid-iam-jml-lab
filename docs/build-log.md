# Build Log

My notes while building this project. Each step covers what I did, why, and anything that broke along the way.

**Parts**
- [1.1 Plan and design](#11-plan-and-design)
- [1.2 Build the domain](#12-build-the-domain)
- [1.3 Admin tiering and access model](#13-admin-tiering-and-access-model)
- [1.4 Hybrid identity](#14-hybrid-identity)
- 1.5 Lifecycle automation (JML engine), *in progress*
- 1.6 Security review, *coming up*

---

## 1.1 Plan and design

### Repo setup (Oct 2)
- Created the repo on GitHub
- Added a `.gitignore` so passwords and keys can never be uploaded

### Directory design (Oct 2)
- Wrote `docs/01-directory-design.md`
- Main decision: admin accounts live in their own OUs so the helpdesk can never reset an admin's password
- **Learned:** the sync server is Tier 0, because it can read every password hash

### Role map (Oct 2)
- Wrote `docs/02-role-map.md`
- Split access into **birthright** (by job role, day one) and **conditional** (program data, only after checks)
- Programs: Radar, Satellite and Shipboard
- **Why:** copying a coworker's access ("make her like Bob") gives people access they don't need
- **Broke:** my first draft gave every engineer program data on day one, tied programs to OUs, and let one person hold both Finance and Accounts Payable
- **Fixed:**
  - Program access needs an assignment, CUI training, US-person status and program manager approval
  - Program is an account attribute, so moving programs is an attribute change, not an account move
  - Finance + AP is blocked by default (one person could create a fake vendor and approve its invoice). Exceptions need outside approval, a time limit and a compensating control

### HR roster (Oct 2)
- Created `data/hr-roster.csv`: 26 fictional people, standing in for an HR export (like Workday)
- Accounts match HR records by **EmployeeID, never by name**, since names change and repeat
- Planted 6 test cases: missing CUI training, non-US person on a program, unapproved program access, future start date, terminated employee, and an expired contractor HR still shows as Active
- Generated with LLM help; I chose the test cases

---

## 1.2 Build the domain

### Budget and DC VM (Oct 2)
- Set an Azure budget: $75, with alerts at $25 / $50 / $75 plus a forecast alert
- Built `FRD-DC-01` with nightly auto-shutdown
- **Broke:** three deployment failures in a row:
  1. B2s not offered in the region
  2. `QuotaExceeded`: 0 cores for the Bsv2 family, and free trials can't request increases
  3. B2s blocked for my subscription even though its family showed quota
- **Fixed:** pulled the quota report, found families with available cores, and deployed `D2nlds_v6` (~$0.23/hr). Raised the budget to match
- **Learned:** a VM size has to pass three gates (region capacity, size restrictions, family quota). Also, check a resource's region on its Overview page instead of trusting the wizard. Mine was in East US, not East US 2 like I thought

### Securing admin access (Oct 2)
- RDP was open to the whole internet when the VM was created, so I removed that rule
- **Broke:** the free Bastion tier wasn't available on my subscription, and RDP wasn't available on my current pc as I was away from home.
- **Fixed:** used paid Bastion for one session and deleted it after. Now RDP is allowed only from my home IP, and VMs are stopped after every session

### Promoting the domain controller (Oct 2)
- Made the DC's IP (`172.16.0.4`) static **in Azure**, not inside Windows
- Installed AD DS and created the forest `ad.potomacdefense.internal` (NetBIOS `PDS`)
- Validated: domain names, DC + Global Catalog, core services running, DNS resolving
- Added a DNS forwarder to Azure DNS (`168.63.129.16`) and pointed the network's DNS at the DC
- **Broke:** promotion set the DC's DNS to `127.0.0.1` inside Windows, overriding Azure
- **Fixed:** switched it to automatic so DNS is managed in one place
- **Note:** the "can't create DNS delegation" warning is expected, since `.internal` has no parent zone

### OU structure (Oct 2)
- Created all 21 OUs from the design doc, with deletion protection on
- **Why:** OUs are where delegation and Group Policy apply. Built-in `Users`/`Computers` are containers, not OUs, so PDS doesn't use them

---

## 1.3 Admin tiering and access model

### Tiered admin accounts (Oct 2–3)
- Created `t0-jagble` (Domain Admins), `t1-jagble` and `t2-jagble`, each in its own tier's Admins OU
- Separate passwords, tier shown in the display name, and the owner in the description (`josh.agble`, EmployeeID 100110)
- Moved all admin work off the built-in account
- **Why:** a stolen lower-tier password can't unlock a higher tier, and offboarding can find every account a person owns
- **Broke:** the first admin account showed as just "Josh Agble," which looks identical to my normal account
- **Fixed:** renamed to `Josh Agble (Tier 0/1/2)`

### Admin groups and role/resource groups (Oct 3)
- Admin groups: `GG-T1-ServerAdmins`, `GG-T2-WorkstationAdmins`, `GG-T2-Helpdesk`
- 13 role groups (Global) and 4 resource groups (Domain Local), created with `scripts/02-create-groups.ps1`
- Nested role groups into resource groups (AGDLP), e.g. `GG-Role-Radar-Engineers` → `DL-Share-Radar-CUI-Modify`
- **Why:** rights go on groups, not people, so access changes are one membership change
- Nothing is nested into Domain Admins, since that's how hidden admin paths form
- Script drafted with LLM help; I reviewed, ran and verified it

### Helpdesk delegation (Oct 3)
- Delegated **only** "Reset user passwords" on `People` to `GG-T2-Helpdesk`
- **Why:** the helpdesk needs resets but must never reach admin accounts, which live outside `People`
- Tested **as `t2-jagble`**, not as myself:

| Test | Target | Result |
|---|---|---|
| 1 | Normal user in `People` | ✅ Allowed |
| 2 | `t1-jagble` (Tier 1 admin) | ⛔ Access is denied |

- **Broke:** Test 1 said "cannot find object," because I'd typed the test account's name without the period
- **Fixed:** corrected the name, re-ran it, and deleted the test account after

---

## 1.4 Hybrid identity

### Sync server (Oct 3–4)
- Built `FRD-SYNC-01` with **no inbound ports**. I reach it only through the DC (jump server)
- Static IP, joined to the domain with Tier 0 credentials, moved to `Tier0\Servers`
- **Why:** Entra Connect can read every password hash, so it's Tier 0 and gets its own server instead of sharing the DC
- **Broke:** the 11 PM auto-shutdown cut off my session
- **Fixed:** nothing was lost (AD saves changes immediately), and I moved shutdown later for late nights

### Entra Connect Sync (Oct 4)
- Added `t0-jagble` to Enterprise Admins **just for the install**, then removed it (just-in-time access)
- Custom install (not Express) with password hash sync
- No verified domain, so synced users sign in as `@PotomacDefenseSystems.onmicrosoft.com`
- **Synced only:** `People`, `Groups\Role`, `Disabled`
- **Why:** Express would sync everything, including admin and service accounts
- **Result:** all 13 role groups show in Entra as **Source: Windows Server AD**. No resource groups, admin groups or admin accounts synced
- Downloaded the installer on the sync server from Microsoft's portal only, as a one-time exception to "no browsing on Tier 0"
- Deleted a leftover cloud group from another course so the tenant only has PDS objects
