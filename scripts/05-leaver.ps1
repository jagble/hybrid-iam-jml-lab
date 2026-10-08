<#
  05-leaver.ps1  -  PDS Leaver (part 3 of the JML engine)

  What it does:  Finds people HR says have left (Status = Terminated, or contract end date passed)
                 and offboards their accounts: cut access first, then clean up, and log every step.
  Where to run:  FRD-DC-01, signed in as PDS\t0-jagble
  Safety:        Dry run by default; -Apply makes real changes. Safe to re-run: already-offboarded accounts are skipped.
  Cloud access:  Signs in to Graph as the PDS-JML-Engine app with a certificate (no secrets).
                 The IDs are identifiers, not secrets; the real values live only on the server.

  Drafted with LLM assistance; reviewed, tested and run by Josh Agble.
#>

param([switch]$Apply)
$DryRun = -not $Apply      # dry run unless -Apply is passed (the scheduled task passes it)
$Roster     = Import-Csv "C:\PDS\data\hr-roster.csv"
$Today      = (Get-Date).Date
$DisabledOU = "OU=Disabled,OU=PDS,DC=ad,DC=potomacdefense,DC=internal"
$LogFile    = "C:\PDS\logs\leaver-$(Get-Date -Format yyyy-MM-dd).csv"
$TenantId   = "<DIRECTORY-TENANT-ID>"        # set on the server; identifiers, not secrets, but kept out of the public repo
$ClientId   = "<PDS-JML-ENGINE-CLIENT-ID>"
$CertThumb  = "<CERTIFICATE-THUMBPRINT>"
Add-Type -AssemblyName System.Web

if ($DryRun) { "*** DRY RUN: nothing will be changed ***" }
else { New-Item -ItemType Directory -Path "C:\PDS\logs" -Force | Out-Null }

Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Certificate (Get-Item "Cert:\LocalMachine\My\$CertThumb") -NoWelcome

function Write-Log($Name, $EmpId, $Step, $Detail) {
    $entry = [pscustomobject]@{ Time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); EmployeeID = $EmpId; Name = $Name; Step = $Step; Detail = $Detail }
    "$($entry.Time)  $Name : $Step  $Detail"
    if (-not $DryRun) { $entry | Export-Csv $LogFile -Append -NoTypeInformation }
}

$Processed = 0
foreach ($p in $Roster) {
    $leaving = ($p.Status -eq "Terminated") -or ($p.EndDate -and [datetime]$p.EndDate -lt $Today)
    if (-not $leaving) { continue }

    $name = "$($p.FirstName) $($p.LastName)"
    $u = Get-ADUser -Filter "employeeID -eq '$($p.EmployeeID)'" -Properties MemberOf
    if (-not $u) { "$name : SKIP, no account in AD"; continue }
    if (-not $u.Enabled -and $u.DistinguishedName -like "*,$DisabledOU") { "$name : SKIP, already offboarded"; continue }

    $reason = if ($p.Status -eq "Terminated") { "HR status Terminated (last day $($p.EndDate))" } else { "contract ended $($p.EndDate)" }
    Write-Log $name $p.EmployeeID "START" $reason

    # ---- 1. Cut access: disable + random password ----
    if (-not $DryRun) {
        Disable-ADAccount -Identity $u
        $pw = ConvertTo-SecureString ([System.Web.Security.Membership]::GeneratePassword(24, 5)) -AsPlainText -Force
        Set-ADAccountPassword -Identity $u -Reset -NewPassword $pw
    }
    Write-Log $name $p.EmployeeID "DISABLED" "AD account disabled, password reset to random"

    # ---- 2. Cut cloud access: revoke Entra sessions ----
    $r = Invoke-MgGraphRequest -Method GET -Headers @{ ConsistencyLevel = "eventual" } `
         -Uri "https://graph.microsoft.com/v1.0/users?`$filter=employeeId eq '$($p.EmployeeID)'&`$count=true&`$select=id,userPrincipalName"
    if ($r.value.Count -ne 1) {
        Write-Log $name $p.EmployeeID "ERROR" "found $($r.value.Count) Entra matches - REVOKE SESSIONS BY HAND"
    } else {
        if (-not $DryRun) { Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($r.value[0].id)/revokeSignInSessions" | Out-Null }
        Write-Log $name $p.EmployeeID "REVOKED" "Entra sessions for $($r.value[0].userPrincipalName)"
    }

    # ---- 3. Clean up: record groups, then remove them ----
    $groups = $u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' }
    Write-Log $name $p.EmployeeID "GROUPS-BEFORE" ($groups -join '; ')
    if (-not $DryRun) { foreach ($dn in $u.MemberOf) { Remove-ADGroupMember -Identity $dn -Members $u -Confirm:$false } }
    Write-Log $name $p.EmployeeID "GROUPS-REMOVED" "$(@($groups).Count) groups"

    # ---- 4. Clean up: description, manager, move ----
    $desc = "Leaver: $reason. Disabled $(Get-Date -Format yyyy-MM-dd) by JML engine"
    if (-not $DryRun) {
        Set-ADUser -Identity $u -Description $desc
        Set-ADUser -Identity $u -Clear manager
        Move-ADObject -Identity $u.DistinguishedName -TargetPath $DisabledOU
    }
    Write-Log $name $p.EmployeeID "MOVED" "description set, manager cleared, moved to Disabled"
    Write-Log $name $p.EmployeeID "DONE" ""
    $Processed++
}

# ---- 5. Don't wait for the 30-minute schedule: push the changes to Entra now ----
if (-not $DryRun -and $Processed -gt 0) {
    try {
        Invoke-Command -ComputerName FRD-SYNC-01 -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta } -ErrorAction Stop | Out-Null
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  SYNC triggered on FRD-SYNC-01 for $Processed leaver(s)"
    } catch {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  SYNC NOT started: $($_.Exception.Message). The scheduled cycle will pick it up within 30 minutes."
    }
}

Disconnect-MgGraph | Out-Null
