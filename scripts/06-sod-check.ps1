<#
  06-sod-check.ps1  -  PDS Separation of Duties check (part of the JML engine)

  What it does:  Looks for people who hold a toxic combination of roles (e.g. Finance + Accounts Payable).
                 No valid exception -> DENY: remove the group that isn't part of their job, and raise an alert.
                 Valid exception    -> ALLOW, but still log a warning every run.
  Exceptions:    C:\PDS\data\sod-exceptions.csv. Valid only if: not expired, max 14 days long,
                 and approved by someone other than the person or their own manager.
  Alerts:        CSV in C:\PDS\logs\ + Windows Application event log (source PDS-JML), so a SIEM can pick them up.
  Safety:        Dry run by default; -Apply makes real changes.

  Drafted with LLM assistance; reviewed, tested and run by Josh Agble.
#>

param([switch]$Apply)
$DryRun = -not $Apply      # dry run unless -Apply is passed (the scheduled task passes it)
$Roster     = Import-Csv "C:\PDS\data\hr-roster.csv"
$Exceptions = Import-Csv "C:\PDS\data\sod-exceptions.csv"
$Today      = (Get-Date).Date
$LogFile    = "C:\PDS\logs\sod-alerts.csv"
$Rules      = @( @{ Name = "Finance + Accounts Payable"; A = "GG-Role-Finance"; B = "GG-Role-AccountsPayable" } )
$DeptGroups = @{ "Engineering"="GG-Role-Engineers"; "Program Management"="GG-Role-ProgramManagers"; "Finance"="GG-Role-Finance";
                 "Human Resources"="GG-Role-HR"; "Contracts"="GG-Role-Contracts"; "Security"="GG-Role-Security" }

if ($DryRun) { "*** DRY RUN: nothing will be changed ***" }
else {
    New-Item -ItemType Directory -Path "C:\PDS\logs" -Force | Out-Null
    if (-not [System.Diagnostics.EventLog]::SourceExists("PDS-JML")) { New-EventLog -LogName Application -Source "PDS-JML" }
}

function Write-Alert($User, $Rule, $Action, $Detail, $EventId, $Type) {
    $entry = [pscustomobject]@{ Time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); EmployeeID = $User.EmployeeID; Name = $User.Name; Rule = $Rule; Action = $Action; Detail = $Detail }
    "$($entry.Time)  $($User.Name) : $Action  [$Rule]  $Detail"
    if (-not $DryRun) {
        $entry | Export-Csv $LogFile -Append -NoTypeInformation
        Write-EventLog -LogName Application -Source "PDS-JML" -EventId $EventId -EntryType $Type `
            -Message "SoD $($Action): $($User.Name) ($($User.EmployeeID)) [$Rule] $Detail"
    }
}

foreach ($rule in $Rules) {
    $inA  = Get-ADGroupMember $rule.A -Recursive | Where-Object objectClass -eq "user" | Select-Object -ExpandProperty SamAccountName
    $inB  = Get-ADGroupMember $rule.B -Recursive | Where-Object objectClass -eq "user" | Select-Object -ExpandProperty SamAccountName
    $both = @($inA | Where-Object { $_ -in $inB })
    if ($both.Count -eq 0) { "No conflicts for [$($rule.Name)]"; continue }

    foreach ($sam in $both) {
        $u = Get-ADUser $sam -Properties EmployeeID
        $p = $Roster | Where-Object EmployeeID -eq $u.EmployeeID

        # ---- 1. Is there a valid exception? ----
        $ex = $Exceptions | Where-Object { $_.EmployeeID -eq $u.EmployeeID -and $_.Rule -eq $rule.Name } | Select-Object -First 1
        if (-not $ex) { $why = "no approved exception" }
        elseif ([datetime]$ex.Expires -lt $Today) { $why = "exception expired $($ex.Expires)" }
        elseif (([datetime]$ex.Expires - [datetime]$ex.ApprovedOn).Days -gt 14) { $why = "exception longer than the 14-day maximum" }
        elseif ($ex.ApprovedBy -in @($u.EmployeeID, $p.ManagerID)) { $why = "approved by self or own manager, needs independent approval" }
        else {
            Write-Alert $u $rule.Name "ALLOWED" "exception approved by $($ex.ApprovedBy) until $($ex.Expires); control: $($ex.Control)" 5002 "Warning"
            continue
        }

        # ---- 2. Deny: keep the group that matches their job (from HR), remove the other ----
        $jobGroup = $null
        if ($p) {
            if     ($p.WorkerType -eq "Subcontractor")          { $jobGroup = "GG-Role-Subcontractors" }
            elseif ($p.JobTitle   -eq "Accounts Payable Clerk") { $jobGroup = "GG-Role-AccountsPayable" }
            elseif ($p.JobTitle   -eq "Helpdesk Technician")    { $jobGroup = "GG-Role-Helpdesk" }
            elseif ($DeptGroups.ContainsKey($p.Department))     { $jobGroup = $DeptGroups[$p.Department] }
        }
        $remove = @(@($rule.A, $rule.B) | Where-Object { $_ -ne $jobGroup })
        if ($remove.Count -ne 1) {
            Write-Alert $u $rule.Name "REVIEW" "$why; can't tell which side is their job, not removing anything" 5003 "Error"
            continue
        }
        Write-Alert $u $rule.Name "DENIED" "$why; removing $($remove[0])" 5001 "Error"
        if (-not $DryRun) { Remove-ADGroupMember -Identity $remove[0] -Members $sam -Confirm:$false }
    }
}
