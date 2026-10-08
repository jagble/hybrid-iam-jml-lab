<#
  07-privileged-access-review.ps1  -  PDS privileged access review (1.6 security review)

  What it does:  READ-ONLY. Expands every privileged AD group (including nested groups) down to the
                 actual accounts, compares them to the approved Tier 0 list, and reports:
                   1. FINDING  - an account with privileged access that isn't approved, with the full path
                   2. ORPHAN   - an account still marked adminCount=1 that's no longer in any privileged group
                                 (AdminSDHolder leftover: inheritance stays off, so delegation like helpdesk resets breaks)
                   3. Approved accounts, with last logon (break-glass accounts should almost never sign in)
                 Writes a CSV report to C:\PDS\logs\. Changes nothing in AD.
  Limits:        Only sees privilege granted through GROUP membership. Rights granted directly on objects
                 (ACLs, e.g. the Entra Connect account's replication rights) need a tool like BloodHound.

  Drafted with LLM assistance; reviewed, tested and run by Josh Agble.
#>

$Approved = @{
    "t0-jagble"    = "Tier 0 admin (Josh Agble)"
    "pdsbootstrap" = "Built-in Administrator (RID 500), break-glass only"
}
$PrivGroups = "Enterprise Admins", "Domain Admins", "Schema Admins", "Administrators", "Account Operators",
              "Server Operators", "Backup Operators", "Print Operators", "DnsAdmins", "Group Policy Creator Owners",
              "Key Admins", "Enterprise Key Admins"
$Report = "C:\PDS\logs\privileged-review-$(Get-Date -Format yyyy-MM-dd_HHmm).csv"
$Rows   = @()

# Walk a group's membership, remembering the path, so nested access shows HOW someone got in
function Get-MemberPaths($Group, $Path, $Seen) {
    foreach ($m in Get-ADGroupMember -Identity $Group) {
        $p = "$Path <- $($m.Name)"
        if ($m.objectClass -eq "group") {
            if ($Seen.ContainsKey($m.distinguishedName)) { continue }   # avoid loops in circular nesting
            $Seen[$m.distinguishedName] = $true
            Get-MemberPaths $m.distinguishedName $p $Seen
        } else {
            [pscustomobject]@{ Sam = $m.SamAccountName; Class = $m.objectClass; Path = $p }
        }
    }
}

"=== 1. Who holds privileged access (direct or nested) ==="
$privSams = @{}
foreach ($g in $PrivGroups) {
    $grp = Get-ADGroup -Filter "Name -eq '$g'"
    if (-not $grp) { continue }
    foreach ($x in Get-MemberPaths $grp.DistinguishedName $g @{}) {
        $privSams[$x.Sam] = $true
        if ($Approved.ContainsKey($x.Sam)) { $status = "OK"; $note = $Approved[$x.Sam] }
        else { $status = "FINDING"; $note = "not on the approved Tier 0 list" }
        "{0,-8} {1}   ({2})" -f $status, $x.Path, $note
        $Rows += [pscustomobject]@{ Check = "Privileged membership"; Status = $status; Account = $x.Sam; Detail = $x.Path; Note = $note }
    }
}

"`n=== 2. AdminSDHolder leftovers (adminCount=1 but no longer privileged) ==="
$orphans = Get-ADUser -LDAPFilter "(adminCount=1)" | Where-Object { -not $privSams.ContainsKey($_.SamAccountName) -and $_.SamAccountName -ne "krbtgt" }
if (-not $orphans) { "none" }
foreach ($o in $orphans) {
    "ORPHAN   $($o.SamAccountName)   (adminCount=1, permission inheritance likely still off)"
    $Rows += [pscustomobject]@{ Check = "AdminSDHolder orphan"; Status = "ORPHAN"; Account = $o.SamAccountName; Detail = $o.DistinguishedName; Note = "clear adminCount and re-enable inheritance" }
}

"`n=== 3. Approved accounts: last logon ==="
foreach ($sam in $Approved.Keys) {
    $a = Get-ADUser $sam -Properties LastLogonDate, PasswordLastSet, PasswordNeverExpires
    "{0,-14} last logon: {1}   password set: {2}   never expires: {3}" -f $sam, $a.LastLogonDate, $a.PasswordLastSet, $a.PasswordNeverExpires
    $Rows += [pscustomobject]@{ Check = "Approved account"; Status = "INFO"; Account = $sam; Detail = "LastLogon $($a.LastLogonDate); PwdSet $($a.PasswordLastSet)"; Note = $Approved[$sam] }
}

$Rows | Export-Csv $Report -NoTypeInformation
"`nReport saved: $Report"
