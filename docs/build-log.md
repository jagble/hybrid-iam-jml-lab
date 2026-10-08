# Build Log

My notes while building this project. Each step covers what I did, why, and anything that broke along the way.

**Parts**
- [1.1 Plan and design](#11-plan-and-design)
- [1.2 Build the domain](#12-build-the-domain)
- [1.3 Admin tiering and access model](#13-admin-tiering-and-access-model)
- [1.4 Hybrid identity](#14-hybrid-identity)
- [1.5 Lifecycle automation (JML engine)](#15-lifecycle-automation)
- [1.6 Security review](#16-security-review)

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
- **Broke:** the free Bastion tier wasn't available on my subscription, and my work network blocks RDP
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
- **Fixed:** nothing was lost (AD saves changes immediately). For long sessions I now move the shutdown time later, then put it back

### Entra Connect Sync (Oct 4)
- Added `t0-jagble` to Enterprise Admins **just for the install**, then removed it (just-in-time access)
- Custom install (not Express) with password hash sync
- No verified domain, so synced users sign in as `@PotomacDefenseSystems.onmicrosoft.com`
- **Synced only:** `People`, `Groups\Role`, `Disabled`
- **Why:** Express would sync everything, including admin and service accounts
- **Result:** all 13 role groups show in Entra as **Source: Windows Server AD**. No resource groups, admin groups or admin accounts synced
- Downloaded the installer on the sync server from Microsoft's portal only, as a one-time exception to "no browsing on Tier 0"
- Deleted a leftover cloud group from another course so the tenant only has PDS objects

---

## 1.5 Lifecycle automation

### Joiner (Oct 4)
- Built `scripts/03-joiner.ps1` in five small pieces: read the HR roster → match people to AD by EmployeeID → decide create or skip → decide groups → create
- Ran every piece **read-only** first and checked the decisions before turning on the part that makes changes (`$DryRun` switch)
- **Results:**
  - 24 accounts created (23 employees, 1 subcontractor), each with a random temporary password that must be changed at first sign-in
  - 2 skipped: Brian (HR says Terminated) and Erin (contract end date passed, even though HR still showed her as Active)
  - Hannah created **disabled** until her start date
  - Program access **denied** for 3 people, with the reason logged: no CUI training, not a US person, not approved by the PM
  - Synced to Entra: `GG-Role-Radar-Engineers` shows exactly Aisha, Ben, Carlos and Jordan
- **Broke:** the server clock was on UTC, so at 9 PM Eastern it already thought it was the next day. Hannah would have been enabled a day early
- **Fixed:** set the server time zone to Eastern before running anything
- **Gap found:** Hannah's account showed as disabled with no reason. Anyone reviewing AD would have to guess whether she was a pre-hire, a leaver or a suspended account
- **Fixed:** added a description to Hannah's account (`Pre-start: account disabled until start date 2026-10-05 (HR)`), then updated the joiner so future pre-start accounts get it automatically
- **Broke:** a leftover test account from the helpdesk test was still in People
- **Fixed:** deleted it before syncing to Entra
- **Learned:** synced groups are read-only in Entra (you can't add members there). AD is the source of truth, and changes flow up
- Script drafted with LLM help; I reviewed it, ran each piece, and verified the results in ADUC and Entra

### Mover (Oct 6)
- Built `scripts/04-mover.ps1`. It compares every existing account to HR and fixes three kinds of drift: start date arrived, program changed, job-role (birthright) groups wrong
- Same safety pattern as the joiner: every piece ran read-only first, and a `$DryRun` switch controls changes
- **Start date:** Hannah's start date arrived, so the mover enabled her and cleared the "Pre-start" note
  - It only re-enables accounts **it** disabled (the "Pre-start" note). Any other disabled account gets flagged for review, since security may have disabled it on purpose
- **Program transfer, done by hand first:** Aisha moved from Radar to Shipboard, and the Shipboard PM hadn't approved her yet
  - In ADUC, I changed her program attribute and removed Radar. I did **not** grant Shipboard yet
  - Then I ran the mover read-only to check my manual work
- **Broke:** I removed the wrong group by hand (`GG-Role-Engineers`, her birthright group, instead of Radar)
- **Caught:** the mover flagged that she still had Radar, but **missed** the lost Engineers group, because it only compared program groups
- **Fixed:** added a birthright check, confirmed it flagged the missing group, then restored it by hand. The birthright check also confirmed the other 23 accounts matched HR
- **PM approval, done by the script:** changed `ProgramApproved` to Yes in HR. The mover added her to `GG-Role-Shipboard-Engineers`, and a second run found nothing left to fix
- **Broke (my edit):** while adding the enable step, I replaced the line that checks the start date. The script failed to parse, which was lucky, because it would have enabled future hires early. Fixed by replacing the whole file instead of editing lines
- **Bug:** the first version reported Program Managers as "no program access." PMs own a program, but program data access is for engineers only. Fixed by checking the department
- **Managers:** linked all 23 people who have a manager in HR (by ManagerID → EmployeeID, never by name). Managers are who approve and review their team's access, so access reviews depend on this field
- **Verified in Entra** after a sync: Aisha is gone from `GG-Role-Radar-Engineers` and in `GG-Role-Shipboard-Engineers`, and Hannah shows as Enabled. No changes were made in the cloud by hand
- **Broke:** my manual sync failed with "Sync is already running." The automatic cycle had started when the server booted. Checked `Get-ADSyncScheduler`, waited, and re-ran it
- **Design choice:** removals run before adds, so a failure partway through leaves someone with too little access, not too much
- **Learned:** manual changes need a check afterward, and a check is only as good as what it compares

### Manual joiner and leaver (Oct 6)
- Before automating the leaver, I did the full process **by hand** to learn what each step is for
- **Manual joiner:** created Brian Keller and Erin Walsh in ADUC as if they'd been hired years ago (they're the leaver test cases). Set every field the joiner script sets: logon name, office, title, department, company, manager, `employeeID`, `employeeType`, `division` and birthright + program groups
  - Verified both against the HR roster with a read-only check. Erin correctly got `GG-Role-Subcontractors` instead of `GG-Role-Engineers`
- **Manual leaver (Erin):** her contract ended 2026-09-30, but HR still showed her as Active
  1. Screenshotted her groups first (record for audit or rehire), then removed all role groups
  2. Disabled the account and reset the password to a random value
  3. Description: who disabled it, when and why
  4. Cleared her manager, so she drops out of her manager's reviews
  5. Moved her to `PDS\Disabled`
  6. **Revoked her sessions in Entra**, without waiting for the sync
- **Verified in Entra:** Account status Disabled, 0 group memberships
- **Learned:**
  - *Locked out* (too many bad passwords, a helpdesk unlock) is not the same as *disabled* (an admin turned the account off). I mixed these up at first
  - Disabling in AD doesn't end cloud sessions right away. Entra only learns at the next sync, and existing tokens keep working, so revoking sessions closes that gap
  - `Disabled` is in the sync scope on purpose. If the account left the sync scope, Entra would delete the cloud account instead of showing it as disabled

### Graph access for the engine (Oct 6)
- The leaver needs to revoke Entra sessions with no person signing in, so the engine got its own identity: app registration `PDS-JML-Engine`
- **Certificate, not a client secret.** Self-signed certificate created on FRD-DC-01 with a **non-exportable** private key, so the key can't be copied off the server. 6-month expiry, so rotation is forced. Only the public `.cer` was uploaded to Entra. 0 client secrets
- **Least privilege:** removed the default delegated `User.Read` and granted only two application permissions:
  - `User.Read.All` (find the person by employeeId)
  - `User.RevokeSessions.All` (sign them out)
  - If the certificate were stolen, an attacker could read the user list and sign people out. They couldn't create admins, reset passwords or delete anyone. Broad permissions like `Directory.ReadWrite.All` were the easy option and the wrong one
- Installed only `Microsoft.Graph.Authentication` (not the full Graph SDK) on the DC. This is the second controlled internet exception on Tier 0: one signed Microsoft module from the official PowerShell Gallery
- **Verified:** signed in as the app (`AuthType: AppOnly`, exactly two scopes) and looked up a user by employeeId
- **Broke:** the first lookup by employeeId returned **nothing, with no error**, even though the user existed and employeeId was synced (checked by listing users)
- **Fixed:** filtering on employeeId is an *advanced query* in Graph. It needs a `ConsistencyLevel: eventual` header plus `$count=true`
- **Learned:** an empty result can look exactly like "this person doesn't exist." In a leaver, that silent miss would leave someone signed in, so the engine must treat "not found in Entra" as an error to report, never as "nothing to do"

### Leaver + exposure window (Oct 6)
- Built `scripts/05-leaver.ps1`: same steps as my manual leaver for Erin, in a deliberate order
  - **Cut access first:** disable, scramble password, revoke Entra sessions (via Graph)
  - **Clean up after:** record groups, remove groups, description, clear manager, move to `Disabled`
  - If the script failed halfway, the person would be locked out with cleanup left, not cleaned up but still able to sign in
- Leavers = HR status Terminated **or** end date passed (catches contractors HR forgot to terminate)
- Every step is timestamped to a CSV log in `C:\PDS\logs\`. "Not found in Entra" is logged as an **ERROR**, not skipped
- **Dry run:** Brian processed, and Erin skipped as "already offboarded," so the script respected my manual work
- **Setup for the test:** gave Brian a known password and signed in as him. Security defaults forced MFA registration with no skip, so I didn't register a fake user on my phone. Entra still logged the attempt as **Interrupted** (password accepted, stopped at MFA setup)
- **Measured timeline (real run):**

| Time | Event | After leaver |
|---|---|---|
| 06:25:50 | Sign-in as Brian: password **accepted** (Interrupted at MFA setup) | before |
| 06:35:50 | Last scheduled sync before the leaver ran | before |
| **06:36:57** | Leaver: AD disabled, password scrambled | 0 s |
| 06:36:58 | Entra sessions revoked via Graph | 1 s |
| 06:38:05 | Sign-in attempt failed (50126, invalid password), most likely a typo on my part | 68 s |
| 06:38:16 | Sign-in with the old password **accepted**, stopped only by MFA registration (50072) | **79 s** |
| 06:40:01 | Entra: `AccountEnabled` true → false (forced delta sync) | 3 min 4 s |

- **Results:**
  - Existing sessions: killed in **1 second**
  - Old password: **still accepted in the cloud at 79 seconds**. The new password hash hadn't synced yet, and the only thing that stopped the sign-in was MFA
  - **I first misread this.** I saw the 68-second "invalid password" failure and assumed the password was dead. The full sign-in list showed a successful password check 11 seconds later. One log entry isn't the whole story, so read the full list before drawing a conclusion
  - Account shown as disabled in Entra: **3 min 4 s** with a forced sync. On the 30-minute schedule (last sync 06:35:50), it would have been **~29 minutes**
- **Learned:**
  - MFA was the compensating control that actually held during the gap. Without it, a fired employee's password would have worked for at least 79 seconds
  - "Disabled in AD" is not "out of the cloud." There are three separate clocks: sessions (revoke), password (hash sync) and account state (full sync)
  - A synced user's enabled state can't be changed in Entra directly, because AD is the source of truth, so the fix for the last clock is triggering a sync, not editing the cloud
- **Next improvement:** have the leaver trigger a delta sync on FRD-SYNC-01 itself, so the ~29 minute window doesn't depend on someone remembering

### Separation of duties (Oct 7)
- Rule from the role map: nobody holds both `GG-Role-Finance` and `GG-Role-AccountsPayable` (one person could create a fake vendor and approve its invoice)
- **Manual review first:** added Maria Lopez (AP Clerk) to Finance as a "helpdesk mistake," then found her by comparing the Members tabs of both groups, checked the exceptions register, and removed Finance (AP is her job per HR)
- **Then automated it:** `scripts/06-sod-check.ps1`
  - Finds anyone in both groups (`-Recursive`, so nesting can't hide a conflict)
  - Checks `data/sod-exceptions.csv`. An exception only counts if it's not expired, 14 days or shorter, and approved by someone other than the person or their own manager
  - No valid exception: keeps the group that matches their job in HR, removes the other, and raises an alert. If it can't tell which is their job, it flags REVIEW and changes nothing
  - Alerts go to a CSV (for auditors) and the Windows Application event log, source `PDS-JML` (for a SIEM): 5001 denied, 5002 allowed by exception, 5003 review
- **Tests:**

| Test | Exception | Result |
|---|---|---|
| Maria added to Finance | none | **DENIED**, Finance removed, event 5001 |
| Maria added to Finance | approved by Security (Monica Hayes), 7 days, compensating control | **ALLOWED**, kept, warning 5002 |
| Maria added to Finance | approved by her own manager (CFO) | **DENIED**, Finance removed, event 5001 |

- **Broke:** twice the script said "No conflicts" after I thought I'd added Maria to Finance in ADUC. The change hadn't saved. Re-added with PowerShell and confirmed membership before testing
- **Learned:**
  - This is a **detective + corrective** control, not a preventive one. AD has no setting that blocks the combination, so a conflict can exist between runs. That's why the check needs a schedule
  - Two logs tell the full story: the Security log (4728/4729) shows *who changed the group and when*; the PDS-JML events show *what the control decided*
  - With a corrective control live, every run acts, so test setups have to happen right before the run being tested
- **Known limitation:** the mover doesn't read the exceptions register, so its next run would remove an approved exception group. In production, exceptions would be granted and tracked through the same system (an IGA tool) so the controls agree

### Leaver triggers its own sync (Oct 7)
- Added a step to the leaver: if anyone was offboarded, it runs `Start-ADSyncSyncCycle -PolicyType Delta` on FRD-SYNC-01 through PowerShell Remoting
- If the sync can't start (already running, server off), the leaver logs it and moves on. The 30-minute schedule is the fallback, and a failed sync never undoes the offboarding
- Closes the ~29-minute "account still enabled in Entra" gap I measured, without relying on someone remembering to force a sync

### Scheduled engine with a gMSA (Oct 7)
- The engine now runs every day as a scheduled task, with nobody signed in
- **Who it runs as:** a group Managed Service Account, `gmsa-jml`. Nobody knows its password: AD generates it and rotates it every 30 days, and only `FRD-DC-01$` can retrieve it. Not my admin account (that would put a Domain Admin password in a task) and not a Domain Admin
  - Created a KDS root key first. I backdated it 10 hours as a lab shortcut, since there's only one DC to replicate to. In production I'd create it and wait
  - `gmsa-jml` lives in `PDS\ServiceAccounts`, which is outside the sync scope, so it never appears in Entra
- **Rights granted to a group (`GG-Svc-JML-Engine`), not the account**, so the gMSA can be swapped later without redoing anything:

| Right | Scope | Why |
|---|---|---|
| Create, delete, manage user accounts | `People`, `Disabled` | Joiner creates, mover edits, leaver disables and moves |
| Modify group membership | `Groups\Role` only | Every script changes role groups |
| Log on as a batch job | Default Domain Controllers Policy | Required to run as a scheduled task on a DC |
| Modify | `C:\PDS\logs` | Write logs |
| Read private key | Graph certificate (certlm) | Sign in to Graph as PDS-JML-Engine |
| Remote Management Users + ADSyncOperators | FRD-SYNC-01 | Trigger a delta sync |

  - It has no admin rights anywhere and can't touch admin accounts, admin groups, resource groups, servers or GPOs
- **Broke:** the Delegation wizard's picker can't find gMSAs, even with the "Computers" object type and the `$` suffix. **Fixed:** delegated to a group and added the gMSA to the group with PowerShell. That's the better pattern anyway
- **Broke:** I ran the role-group delegation on `PDS\Groups` instead of `PDS\Groups\Role`. That would have let the engine change **resource group** membership (like `DL-Share-Radar-CUI-Modify`), a back door around the CUI checks. **Fixed:** removed the entries in Security → Advanced, redid it on `Role`, and confirmed with `Get-Acl` that nothing was left on `Groups`
- **Scripts are now dry-run by default.** Each one has `param([switch]$Apply)`. Run by hand, it only prints. Only the wrapper `run-jml.ps1` passes `-Apply`, and only the scheduled task runs the wrapper
- `run-jml.ps1` runs joiner → mover → leaver → SoD, records everything with `Start-Transcript` to a dated log, writes `whoami` at the top as proof of who ran it, and keeps going if one script fails
- **Schedule:** daily at 8:00 PM. In production it'd be early morning before the workday, but the lab VMs are off most of the day to save money
- **First run:** `LastTaskResult 0`, `RunAs User: PDS\gmsa-jml$`. All four scripts ran, including Graph sign-in with the certificate

### Scale test: 340 people (Oct 7)
- Generated a 340-person roster (my original 26 + 314 new) and a "next morning" version with 22 HR changes, plus an answer key of expected results. Generated with LLM help
- **Day 1 (306 new hires):**
  - 306 accounts created, 6 of them disabled until a future start date, 33 program access denials. AD count afterward: **330 accounts in People, 6 disabled**, exactly as expected
  - The mover then set **306 managers** (329 of 330 people have one; the CEO doesn't)
- **Broke (the big one): my "dry run" wasn't dry.** Before the run, I did a dry-run pre-check of the joiner to count CREATE decisions. The joiner was the one script that never got the `-Apply` switch (it still said `$DryRun = $false`), so the "pre-check" **created all 306 accounts as me**
  - Found it because the task's PowerShell process had used **0.8 seconds of CPU in 45 minutes**, far too little to have created 306 accounts, and the new accounts' **owner** was `PDS\Domain Admins`, not `gmsa-jml$`
  - The task, started while my run was still going, sat waiting on something with no one to answer. The mover never started (manager count frozen at 23)
  - **Fixed:**
    - Added the switch to the joiner
    - Verified all four scripts expose `-Apply` with `Get-Command` *without running them*
    - Added `-NonInteractive` to the task, so anything that ever prompts fails immediately with an error instead of hanging
    - Re-ran: the mover set all 306 managers as the gMSA in about 2 minutes
  - **Learned:** verify the safety switch itself before trusting it. Unattended jobs need `-NonInteractive`. Object ownership in AD shows who really created something
- **Day 2 (HR changes overnight), run by the gMSA. Every result matched the answer key:**

| Change | People | Result |
|---|---|---|
| New hires | 5 | 5 created, 2 disabled until future start dates |
| Program transfer, approved | 4 | old program group removed, new one added |
| Program transfer, not approved yet | 2 | old group removed, no new access |
| Engineering → Program Management | 2 | program group + Engineers removed, ProgramManagers added, new manager |
| Manager change | 2 | manager updated |
| Terminated / contract ended | 8 | disabled, sessions revoked, groups removed, moved to Disabled. All 8 found in Entra, 0 errors |
| Sync | 1 | `SYNC triggered on FRD-SYNC-01 for 8 leaver(s)`. ADSyncOperators was enough; the gMSA didn't need ADSyncAdmins |

- **Speed:** the 8 leavers took about 4 seconds, and the sync was triggered 5 seconds later
- **Scaling note:** the engine looks up AD one person at a time (thousands of requests for 340 people). That's fine at this size, but at 10,000+ people I'd load all users once at the start and look them up in memory

---

## 1.6 Security review

### Hidden Domain Admin + privileged access review (Oct 7)
- **Scenario:** a "previous admin" left a privilege path behind. I created `IT-Legacy-Tools` in the default `Users` container, put **Tyler Nguyen** (a normal helpdesk user) in it, and nested it into **Domain Admins**. Opening Domain Admins → Members only shows a boring group name, and Tyler's own Member Of tab doesn't mention Domain Admins
- **Built `scripts/07-privileged-access-review.ps1` (read-only by design):**
  - Expands 12 privileged groups (Domain/Enterprise/Schema Admins, Administrators, Account/Server/Backup/Print Operators, DnsAdmins, GPO Creator Owners, Key Admins) **recursively, keeping the path**, so nesting can't hide anyone
  - Compares every account to an approved Tier 0 list with a reason for each
  - Flags AdminSDHolder leftovers (`adminCount=1` on accounts that are no longer privileged)
  - Shows last logon for approved accounts, and saves a CSV report
- **Findings:**

| # | Finding | Severity | Fix |
|---|---|---|---|
| 1 | `Domain Admins <- IT-Legacy-Tools <- Tyler Nguyen`, plus the same path into **Administrators** (Domain Admins is nested there) | Critical | Removed the nesting, deleted the group |
| 2 | **Standing** Enterprise Admins + Schema Admins: the built-in Administrator (`pdsbootstrap`) is placed there automatically when the forest is created. I didn't plant this; my "Enterprise Admins is just-in-time" design wasn't actually true | High | Removed it from both. Both groups are now empty until needed |
| 3 | AdminSDHolder orphan: Tyler kept `adminCount=1` and blocked inheritance after being removed | Medium | Re-enabled inheritance, cleared `adminCount` |

- **Investigated before cleaning up:** queried the Security log for event **4728** (member added to a security group) filtered to Domain Admins. That gave the full history of every Domain Admins addition:
  1. 10/2 3:37 PM, `ANONYMOUS LOGON` → pdsbootstrap. Expected: this is domain creation itself
  2. 10/2 4:47 PM, pdsbootstrap → my Tier 0 account. Expected
  3. **10/7 9:55 PM, t0-jagble → IT-Legacy-Tools.** The finding
  - **Learned:** "ANONYMOUS LOGON added someone to Domain Admins" looks alarming but is normal at domain creation, so context comes before alarm. Thousands of 4728s from the scale test buried this one event, so a filtered query (basically a SIEM rule: *alert on any Domain Admins addition*) found it in seconds
- **AdminSDHolder, seen live:** triggered SDProp manually (`runProtectAdminGroupsTask`) instead of waiting an hour. Tyler got `adminCount=1` and **inheritance blocked**. Removing him from the group did **not** undo either one
- **Proved the impact as the helpdesk (`t2-jagble`):**

| Test | Result |
|---|---|
| Reset Derek Hall (normal user, control) | ✅ Allowed |
| Reset Tyler (orphan) | ⛔ **Access is denied** |
| Reset Tyler after re-enabling inheritance + clearing `adminCount` | ✅ Allowed |

  - Why it matters: an ex-admin the helpdesk can't support turns every lockout into a Tier 0 escalation. Enough of those and admins start "just doing it themselves," which erodes the tiering model
- **Final review:** no findings, Enterprise Admins + Schema Admins empty, no orphans. The break-glass account was last used 10/2 (domain build), as expected
- **Limits and next steps:**
  - My script approves an *account* for every privileged group. A better version approves account + group pairs (break-glass in Domain Admins: OK; standing Enterprise Admins: not OK)
  - It only sees privilege granted through **group membership**. Rights granted directly on objects, like the Entra Connect account's directory replication rights, need a graph tool like BloodHound to see
