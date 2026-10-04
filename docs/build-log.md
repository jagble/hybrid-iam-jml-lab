# Build Log

My notes while building this project.

## Step 1 - Repo setup (Oct 2)
- Created the repo on GitHub
- Added a .gitignore so passwords and keys can never be uploaded

## Step 1b - Directory design (Oct 2)
- Wrote the directory design doc
- Main decision: admin accounts live in their own folders so the helpdesk can never reset an admin's password
- Learned: the sync server is Tier 0 because it can read every password

## Step 2 — Role map

**Did:** Wrote `docs/02-role-map.md`. Split access into birthright (by job role) and conditional (program data). Defined the checks for program data, the Finance/AP separation-of-duties conflict, and an exception process. Created programs Radar, Satellite and Shipboard so the names describe the work.

**Why:** Copying a coworker's access ("make her like Bob") gives people access they don't need. A role map makes day-one access predictable and keeps program data need-to-know.

**Broke:** My first draft gave every engineer the program CUI share on day one and tied program membership to an OU. It also let one person hold both Finance and Accounts Payable.

**Fixed:**
- Program access now requires a program assignment, CUI training, US-person status (for export-controlled data) and program manager approval.
- Program comes from an account attribute instead of an OU, so moving between programs is an attribute change, not an account move.
- Finance + AP is a toxic combination: one person could create a fake vendor and approve its invoice. The JML engine denies it by default. Exceptions need approval from outside the conflict, a time limit and a compensating control.

## Step 3 — Synthetic HR roster (Oct 2)

Did: Created data/hr-roster.csv with 26 fictional PDS people. It stands in for an HR system export (like Workday) and is the source of truth the JML engine will read.

Why: In a real company, HR decides who works there and IAM reacts. Every column maps to an access decision: EmployeeID for matching, WorkerType for OU placement, Department/JobTitle for birthright groups, Program/CUITraining/USPerson/ProgramApproved for program access, and StartDate/EndDate/Status for lifecycle.

Design choices:

Accounts are matched to HR records by EmployeeID, never by name. Names change (marriage) and repeat.
Six planted test cases: missing CUI training, non-US person on a program, program access not approved, future start date, terminated employee, and a subcontractor whose contract ended but HR still shows Active.
Generated with LLM assistance; the test cases were chosen deliberately.

##Step 4 — Budget and domain controller VM (Oct 2)

Did: Set an Azure budget ($75, alerts at $25 / $50 / $75 plus a forecast alert), then built FRD-DC-01 in Azure with nightly auto-shutdown.

Why: Cloud VMs bill by the hour. The budget alerts me before a forgotten VM becomes a surprise.

Broke: Three deployment failures in a row:

B2s not offered in East US.
QuotaExceeded: my free-trial subscription has 0 cores for the Bsv2 family. Free trials can't request quota increases.
B2s blocked for my subscription even though its family showed quota.

Fixed: Exported the subscription quota report, identified families with available cores, and deployed D2nlds_v6 (2 vCPU / 4 GB, about $0.23/hr). Raised the budget to match the real cost. Later found the VM was actually in East US, not East US 2 as I'd assumed.

Lesson: A size has to pass three separate gates (regional capacity, subscription size restrictions, family quota). And confirm a resource's region on its Overview page instead of trusting what I picked in the wizard.

## Step 5 — Securing admin access to the VM (Oct 2)

Did: Removed public RDP access open to the internet. Used Azure Bastion temporarily, then switched to RDP allowed only from my home IP.

Why: RDP open to "Any" gets password-guessing attempts within minutes, and this server became the domain controller.

Broke: The free Bastion Developer tier wasn't available on my subscription, and my work network blocks outbound RDP.

Fixed: Used Bastion Basic for one session (it bills hourly even when VMs are off, so I deleted it at the end of the session). Now RDP is allowed only from my home IP, and VMs are stopped (deallocated) after each session.

## Step 6 — Promoting the first domain controller (Oct 2)

Did:

Confirmed hostname, IP and disks, then set the DC's private IP (172.16.0.4) to static in Azure, not inside Windows.
Installed AD DS and promoted the server: new forest ad.potomacdefense.internal, NetBIOS name PDS, AD database on C:.
Validated: domain names, DC + Global Catalog, NTDS/DNS/Netlogon running, domain resolves to 172.16.0.4.
Added DNS forwarder 168.63.129.16 (Azure DNS) and set the virtual network's DNS server to the DC.

Why: Every domain-joined machine finds AD through DNS, so the DC's IP must never change and every VM must use it for DNS.

Broke: After promotion, the DC's DNS was set to 127.0.0.1 inside Windows, overriding the Azure network setting.

Fixed: Switched the NIC to obtain DNS automatically so DNS is managed in one place (Azure). Verified it now shows 172.16.0.4.

Note: The "cannot create DNS delegation" warning is expected. .internal has no parent zone to delegate from.

## Step 7 — OU structure (Oct 2)

Did: Created the 21-OU structure from docs/01-directory-design.md under PDS, with accidental-deletion protection on.

Why: OUs are where delegation and Group Policy apply. Splitting by tier and object type (not department) keeps admin accounts out of reach of helpdesk delegation. PDS accounts don't use the default Users/Computers containers, which can't take Group Policy or delegation.

## Step 8 — Tiered admin accounts (Oct 2–3)

Did: Created t0-jagble (Tier0\Admins, member of Domain Admins), t1-jagble (Tier1\Admins) and t2-jagble (Tier2\Admins). Each has its own password, a display name showing the tier, and a description linking it to its owner (josh.agble, EmployeeID 100110). Switched all admin work from the built-in account to t0-jagble.

Why: Normal accounts never hold admin rights, and a stolen lower-tier credential can't unlock a higher tier. The owner link lets offboarding find every account a person has, not just their normal one.

Broke: The first admin account kept the display name "Josh Agble," which would look identical to my normal account in pickers and logs.

Fixed: Renamed and set display names to Josh Agble (Tier 0/1/2).

## Step 9 — Admin groups and role/resource groups (Oct 3)

Did:

Admin groups: GG-T1-ServerAdmins, GG-T2-WorkstationAdmins, GG-T2-Helpdesk, with the tier accounts as members.
13 role groups (Global) in Groups\Role and 4 resource groups (Domain Local) in Groups\Resource, created with scripts/02-create-groups.ps1.
Nested role groups into resource groups (AGDLP), e.g. GG-Role-Radar-Engineers → DL-Share-Radar-CUI-Modify.

Why: Rights go on groups, never on individual people, so adding or removing someone is one membership change. AGDLP keeps resource permissions stable while role membership changes.

Notes:

No group is nested into Domain Admins. Nested privileged groups are how hidden admin paths form.
The script was drafted with LLM assistance; I reviewed and ran it and verified the results in ADUC.

##Step 10 — Helpdesk password-reset delegation (Oct 3)

Did: Used the Delegate Control wizard on PDS\People to give GG-T2-Helpdesk only "Reset user passwords and force password change at next logon."

Why: The helpdesk needs password resets but must never reach admin accounts. Delegating on People only, combined with admin accounts living outside People, enforces that boundary.

Tested (running as t2-jagble, not as myself):

Test	Target	Result
1	test.helpdesk in People\Employees	✅ Allowed
2	t1-jagble in Tier1\Admins	⛔ Access is denied

Broke: Test 1 first failed with "Cannot find an object with identity," because I'd left the period out of the test account's logon name.

Fixed: Corrected the logon name to test.helpdesk (both logon name fields) and re-ran. Deleted the test account afterward.

## Step 11 — Entra Connect server (Oct 3–4)

Did:

Built FRD-SYNC-01 with no inbound ports open to the internet. It's reachable only by RDP from the DC (jump server pattern).
Set its private IP to static in Azure.
Joined it to the domain using Tier 0 credentials and moved it from Computers to Tier0\Servers.

Why: Entra Connect can read every password hash and write to Entra ID, so it's Tier 0. It gets its own server instead of running on the DC, so the DC only does one job.

Broke: The 11 PM auto-shutdown ended my session mid-work.

Fixed: Nothing was lost, since AD changes save immediately. Moved auto-shutdown later for late sessions.

## Step 12 — Entra Connect Sync (Oct 4)

Did:

Temporarily added t0-jagble to Enterprise Admins (required to create the AD connector account), then removed it right after the install.
Installed Entra Connect Sync (Custom, not Express) with password hash sync.
Continued without a verified UPN suffix, since ad.potomacdefense.internal isn't a public domain. Synced users get @PotomacDefenseSystems.onmicrosoft.com sign-in names.
OU filtering: synced only People, Groups\Role and Disabled.

Why: Express settings would sync everything, including admin and service accounts. Custom OU filtering enforces the sync scope from the design doc.

Result: All 13 role groups appear in Entra with Source: Windows Server AD. No resource groups, tier admin groups or admin accounts were synced.

Notes:

Controlled exception: downloaded the installer on the Tier 0 sync server from the Entra admin center (Microsoft's portal only, no other browsing).
Deleted a leftover cloud-only group from a separate course so the tenant only contains PDS objects.
Enterprise Admins membership was granted only for the install (just-in-time).
