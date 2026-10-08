# JML Runbook — Potomac Defense Systems

> **Summary:** How to handle a joiner, mover and leaver by hand in Active Directory and Entra ID, how to handle an SoD exception, and what the automated engine does for each step. Use the manual steps when the engine is down, for a one-off urgent request, or to check the engine's work.

> **About this lab:** Potomac Defense Systems is a fictional company. All people and data are made up.

**Source of truth:** the HR roster (`data/hr-roster.csv`). IAM reacts to HR, never the other way around.
**Match on EmployeeID, never on name.**
**Tools:** ADUC (`dsa.msc`) as `t0-jagble` for engine-level work, the Entra admin center, and PowerShell on FRD-DC-01.

---

## 1. Joiner

**Trigger:** a new row in the HR roster.

| # | Manual step (ADUC) | Engine (`03-joiner.ps1`) |
|---|---|---|
| 1 | Check HR: Status is Active, and the end date (contractors) hasn't passed | Same check; skips Terminated and expired rows |
| 2 | Search AD by **EmployeeID** to make sure they don't already have an account | `Get-ADUser -Filter "employeeID -eq ..."`; skips if found |
| 3 | Create the user in `People\Employees` or `People\Subcontractors`. Logon name `first.last`, UPN `first.last@ad.potomacdefense.internal` | Same OU rule and naming standard |
| 4 | Random temporary password, **must change at next logon** | 16-character random password, never shown or saved |
| 5 | Fill in office, title, department, company, manager | Same (the mover links the manager) |
| 6 | Attribute Editor: `employeeID`, `employeeType`, `division` (program) | Same |
| 7 | Birthright groups: `GG-Role-AllStaff` + one job-role group (see role map) | Same rules: Subcontractor → AP Clerk → Helpdesk → department |
| 8 | Program group **only if** CUI training = Yes, US person = Yes, PM approved = Yes | Same three checks; logs the reason when denied |
| 9 | Future start date: **disable** the account and set the description `Pre-start: account disabled until start date YYYY-MM-DD (HR)` | Same |

**Verify:** the account appears in Entra after the next sync (or force one, section 5). Synced groups show "Source: Windows Server AD".

## 2. Mover

**Trigger:** HR changes department, title, program, manager or approval, or a start date arrives.

| Change | Manual step | Engine (`04-mover.ps1`) |
|---|---|---|
| Start date arrived | Enable the account **only if** its description starts with `Pre-start`. Clear the description | Same. Any other disabled account is flagged **REVIEW** and left alone |
| Program transfer | Update `division`. **Remove the old program group first.** Add the new one only when all three checks pass for the **new** program | Same order: UPDATE, REMOVE, then ADD or NO ACCESS |
| Department / title change | Remove the old job-role group, add the new one | Birthright check: REMOVE "not part of their job", ADD "birthright for their job" |
| Manager change | Organization tab → Manager | SET MANAGER, matched by ManagerID → EmployeeID |

**Always remove before you add.** A half-finished change should leave too little access, not too much.

**Verify:** run `04-mover.ps1` with no switches (dry run). If your manual work was right, it reports nothing to change except known NO ACCESS cases.

## 3. Leaver

**Trigger:** HR status = Terminated, **or** a contractor's end date has passed (even if HR still says Active).

Order matters: **cut access first, clean up second.**

| # | Manual step | Engine (`05-leaver.ps1`) |
|---|---|---|
| 1 | Disable the AD account | `Disable-ADAccount` |
| 2 | Reset the password to a long random value nobody knows | 24-character random password |
| 3 | **Entra admin center → Users → the person → Revoke sessions.** Don't wait for sync | Graph: find by employeeId (advanced query), `POST /users/{id}/revokeSignInSessions`. Not found = **ERROR**, revoke by hand |
| 4 | Screenshot or record their groups, then remove all role groups | Logs GROUPS-BEFORE, then removes them |
| 5 | Description: `Leaver: <reason>. Disabled <date> by <who>` | Same, "by JML engine" |
| 6 | Clear the manager | Same |
| 7 | Move to `PDS\Disabled` (stays in sync scope, so Entra shows **disabled**, not deleted) | Same |
| 8 | Force a delta sync (section 5) | Triggers it on FRD-SYNC-01 automatically |

**Verify in Entra:** Account status **Disabled**, Group memberships **0**. Sign-in logs for the person show failures after the leaver ran.

**Why step 3 can't wait:** disabling in AD doesn't sign anyone out of the cloud. Measured in this lab: the old password still worked in the cloud 79 seconds after the leaver ran, and Entra showed the account as disabled only after the next sync (~29 minutes on the default schedule).

## 4. Separation of duties exception

**Rule:** nobody holds both `GG-Role-Finance` and `GG-Role-AccountsPayable`.

To grant a temporary exception (for example, covering for someone on leave):
1. Approval from someone **outside the person's management chain** (for example, Security). The person and their own manager can't approve it
2. **14 days maximum**
3. A **compensating control**, for example "CFO reviews every vendor payment this person approves"
4. Add a row to `data/sod-exceptions.csv`: `EmployeeID,Rule,ApprovedBy,ApprovedOn,Expires,Control`
5. **Delete the row when it ends.** An expired row is treated as no exception

**Engine (`06-sod-check.ps1`):** valid exception → ALLOWED, event 5002 (Warning) every run. No valid exception → DENIED, the group that isn't their job is removed, event 5001 (Error). Can't tell which group is their job → REVIEW, event 5003, nothing removed.

**Known limitation:** the mover doesn't read the exceptions register, so it removes an approved exception group as job-role drift. Until the register lives in an IGA tool, grant exceptions knowing the next mover run will undo them.

## 5. Common tasks

```powershell
# Force a sync to Entra now (from FRD-DC-01)
Invoke-Command -ComputerName FRD-SYNC-01 -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta }

# Dry run any engine script (prints decisions, changes nothing)
C:\PDS\scripts\04-mover.ps1

# Run the whole engine for real, the same way the schedule does
Start-ScheduledTask -TaskName "PDS JML Engine"

# Read the newest engine log
Get-Content (Get-ChildItem C:\PDS\logs\jml-run-*.log | Sort-Object LastWriteTime | Select-Object -Last 1)
```

**Engine facts:**
- Runs daily at 8:00 PM as `PDS\gmsa-jml$`, with `-NonInteractive`
- Rights come from the group `GG-Svc-JML-Engine`
- Logs are in `C:\PDS\logs`
- The Graph certificate expires **2027-04-06**. Create a new one, upload it to the `PDS-JML-Engine` app, grant the group read on the key, update the thumbprint, and **then** delete the old one
