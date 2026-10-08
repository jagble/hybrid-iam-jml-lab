# Privileged Access Review — Findings Report

> **Summary:** A review of who holds Tier 0 power in `ad.potomacdefense.internal`. It found a Domain Admin hidden behind a nested group, standing Enterprise and Schema Admins membership, and an AdminSDHolder leftover that broke helpdesk support. All three were fixed and re-verified.

> **About this lab:** Potomac Defense Systems is a fictional company. Finding 1 was planted on purpose to test the review; findings 2 and 3 were not.

| | |
|---|---|
| **Date** | 2026-10-07 |
| **Reviewer** | Josh Agble |
| **Scope** | Membership of 12 privileged AD groups (direct and nested), AdminSDHolder leftovers, approved Tier 0 accounts |
| **Tool** | `scripts/07-privileged-access-review.ps1` (read-only) + Security event log |
| **Result** | 3 findings: 1 critical, 1 high, 1 medium. All remediated and verified |

## Method

1. Expanded **Enterprise Admins, Domain Admins, Schema Admins, Administrators, Account Operators, Server Operators, Backup Operators, Print Operators, DnsAdmins, Group Policy Creator Owners, Key Admins and Enterprise Key Admins** down to individual accounts, recording the full nesting path
2. Compared every account against the approved Tier 0 list:
   - `t0-jagble`: Tier 0 admin
   - `pdsbootstrap`: built-in Administrator, break-glass only
3. Listed accounts with `adminCount=1` that are no longer in any privileged group
4. For each finding, searched the Security log **before** changing anything

## Findings

### 1. Hidden Domain Admin through a nested group — Critical

- **What:** `Domain Admins <- IT-Legacy-Tools <- Tyler Nguyen`. Through Domain Admins, Tyler is also in Administrators on every domain controller
- **Why it was easy to miss:** Domain Admins → Members shows only a group called `IT-Legacy-Tools`, stored in the default `Users` container. Tyler's own Member Of tab doesn't mention Domain Admins. Tyler is a normal helpdesk user with no admin account
- **Evidence:** Security event **4728** filtered to Domain Admins:

| Time | Changed by | Added | Assessment |
|---|---|---|---|
| 2026-10-02 15:37 | ANONYMOUS LOGON | pdsbootstrap | Expected: domain creation |
| 2026-10-02 16:47 | pdsbootstrap | Josh Agble (Tier 0) | Expected: tiering setup |
| **2026-10-07 21:55** | **t0-jagble** | **IT-Legacy-Tools** | **No change record. Finding** |

- **Fix:** removed `IT-Legacy-Tools` from Domain Admins and deleted the group
- **Verified:** re-ran the review, with no findings

### 2. Standing Enterprise Admins and Schema Admins — High

- **What:** the built-in Administrator (`pdsbootstrap`) was a permanent member of **Enterprise Admins** and **Schema Admins**. Windows adds it automatically when the forest is created
- **Why it matters:** the design says Enterprise Admins is granted just in time. It was removed from my Tier 0 account after the Entra Connect install, but this default membership was never noticed. Anyone who compromises the break-glass account gets forest-wide and schema rights with no extra step
- **Fix:** removed `pdsbootstrap` from both groups. Both are now **empty** and are granted only for the duration of a specific change
- **Verified:** neither group appears in the re-run review

### 3. AdminSDHolder leftover breaks helpdesk support — Medium

- **What:** while Tyler was a Domain Admin, SDProp (which runs every 60 minutes) stamped his account `adminCount=1` and **turned off permission inheritance**. Removing him from the group did not undo either
- **Impact, tested as the helpdesk account `t2-jagble`:**

| Test | Result |
|---|---|
| Reset a normal user (Derek Hall, control) | Allowed |
| Reset Tyler after removal from Domain Admins | **Access is denied** |
| Reset Tyler after the fix | Allowed |

- **Why it matters:** the helpdesk can't support a user who is no longer an admin, so every lockout escalates to Tier 0. Over time admins start doing Tier 2 work with Tier 0 accounts, which is exactly what tiering exists to stop
- **Fix:** re-enabled inheritance on Tyler's account and cleared `adminCount`
- **Verified:** the helpdesk reset succeeded, and the review shows no leftovers

## Final state

- **Domain Admins:** `t0-jagble`, `pdsbootstrap` (break-glass)
- **Enterprise Admins, Schema Admins:** empty
- **AdminSDHolder leftovers:** none
- **Break-glass last sign-in:** 2026-10-02 (domain build)

## Recommendations

1. **Alert on every change to a privileged group.** Events 4728, 4732 and 4756 for these groups should page someone; that's the query used above, turned into a SIEM rule
2. **Run this review on a schedule** (monthly, plus after any admin change), not just once
3. **Approve account + group pairs**, not accounts. Break-glass in Domain Admins is approved; break-glass in Enterprise Admins is not
4. **Clean up AdminSDHolder leftovers** whenever someone leaves a protected group
5. **Look beyond group membership.** Privilege can also come from permissions set directly on objects, such as the Entra Connect account's directory replication rights. A graph tool like BloodHound shows those paths
