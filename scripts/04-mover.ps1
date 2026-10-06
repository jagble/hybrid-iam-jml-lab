$DryRun = $true      # $true = print only. $false = really make changes.
$Roster = Import-Csv "C:\PDS\data\hr-roster.csv"
$Today  = (Get-Date).Date
$ProgramGroups = "GG-Role-Radar-Engineers", "GG-Role-Satellite-Engineers", "GG-Role-Shipboard-Engineers"
$BirthrightGroups = "GG-Role-AllStaff", "GG-Role-Subcontractors", "GG-Role-AccountsPayable", "GG-Role-Helpdesk",
    "GG-Role-Engineers", "GG-Role-ProgramManagers", "GG-Role-Finance", "GG-Role-HR", "GG-Role-Contracts", "GG-Role-Security"
$DeptGroups = @{ "Engineering"="GG-Role-Engineers"; "Program Management"="GG-Role-ProgramManagers"; "Finance"="GG-Role-Finance";
    "Human Resources"="GG-Role-HR"; "Contracts"="GG-Role-Contracts"; "Security"="GG-Role-Security" }

foreach ($p in $Roster) {
    $u = Get-ADUser -Filter "employeeID -eq '$($p.EmployeeID)'" -Properties Description, Division, MemberOf, Manager
    if (-not $u) { continue }                                          # no account = joiner's job
    if ($p.Status -ne "Active") { continue }                           # left = leaver's job
    if ($p.EndDate -and [datetime]$p.EndDate -lt $Today) { continue }  # contract over = leaver's job

    # ---- 1. Disabled account + start date has arrived ----
    if (-not $u.Enabled -and [datetime]$p.StartDate -le $Today) {
        if ($u.Description -like "Pre-start*") {
            "$($u.Name) : ENABLE, start date $($p.StartDate) has arrived"
            if (-not $DryRun) {
                Enable-ADAccount -Identity $u
                Set-ADUser -Identity $u -Clear description
            }
        } else {
            "$($u.Name) : REVIEW, disabled for another reason ($($u.Description)), not touching it"
        }
    }

    # ---- 2. Program change ----
    $want = $null
    if ($p.Program -and $p.Department -eq "Engineering" -and $p.CUITraining -eq "Yes" -and
        $p.USPerson -eq "Yes" -and $p.ProgramApproved -eq "Yes") {
        $want = "GG-Role-$($p.Program)-Engineers"
    }
    $have = $u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' } | Where-Object { $_ -in $ProgramGroups }

    if ("$($u.Division)" -ne $p.Program) {
        "$($u.Name) : UPDATE program '$($u.Division)' -> '$($p.Program)'"
        if (-not $DryRun) {
            if ($p.Program) { Set-ADUser $u -Division $p.Program } else { Set-ADUser $u -Clear division }
        }
    }
    foreach ($g in $have) {
        if ($g -ne $want) {
            "$($u.Name) : REMOVE $g"
            if (-not $DryRun) { Remove-ADGroupMember -Identity $g -Members $u -Confirm:$false }
        }
    }
    if ($want -and $want -notin $have) {
        "$($u.Name) : ADD $want"
        if (-not $DryRun) { Add-ADGroupMember -Identity $want -Members $u }
    }
    elseif ($p.Program -and $p.Department -eq "Engineering" -and -not $want) {
        "$($u.Name) : NO ACCESS to $($p.Program) yet (checks not met)"
    }

    # ---- 3. Birthright (job role) ----
    $wantB = @("GG-Role-AllStaff")
    if     ($p.WorkerType -eq "Subcontractor")          { $wantB += "GG-Role-Subcontractors" }
    elseif ($p.JobTitle   -eq "Accounts Payable Clerk") { $wantB += "GG-Role-AccountsPayable" }
    elseif ($p.JobTitle   -eq "Helpdesk Technician")    { $wantB += "GG-Role-Helpdesk" }
    elseif ($DeptGroups.ContainsKey($p.Department))     { $wantB += $DeptGroups[$p.Department] }
    $haveB = $u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' } | Where-Object { $_ -in $BirthrightGroups }

    foreach ($g in $haveB) {
        if ($g -notin $wantB) {
            "$($u.Name) : REMOVE $g (not part of their job)"
            if (-not $DryRun) { Remove-ADGroupMember -Identity $g -Members $u -Confirm:$false }
        }
    }
    foreach ($g in $wantB) {
        if ($g -notin $haveB) {
            "$($u.Name) : ADD $g (birthright for their job)"
            if (-not $DryRun) { Add-ADGroupMember -Identity $g -Members $u }
        }
    }

    # ---- 4. Manager (from HR's ManagerID) ----
    if ($p.ManagerID) {
        $mgr = Get-ADUser -Filter "employeeID -eq '$($p.ManagerID)'"
        if (-not $mgr) { "$($u.Name) : MANAGER $($p.ManagerID) has no account, can't link" }
        elseif ($u.Manager -ne $mgr.DistinguishedName) {
            "$($u.Name) : SET MANAGER -> $($mgr.Name)"
            if (-not $DryRun) { Set-ADUser $u -Manager $mgr }
        }
    }
}
