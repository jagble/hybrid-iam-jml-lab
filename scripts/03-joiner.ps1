<#
  03-joiner.ps1  -  PDS Joiner (part 1 of the JML engine)

  What it does:  Reads the HR roster and creates AD accounts for people who don't have one yet.
                 Skips people who have left, keeps future hires disabled, and applies the role map:
                 birthright groups for everyone, program groups only when all checks pass.
  Where to run:  FRD-DC-01, signed in as PDS\t0-jagble
  Safety:        Set $DryRun = $true to only print decisions without changing anything.
                 Safe to re-run: anyone who already has an account (matched by EmployeeID) is skipped.

  Built in five pieces (read roster -> match by ID -> skip/create decision -> groups -> create).
  Drafted with LLM assistance; reviewed, tested and run by Josh Agble.
#>

$DryRun   = $false     # $true = print only. $false = really create accounts.
$Roster   = Import-Csv "C:\PDS\data\hr-roster.csv"
$Today    = (Get-Date).Date
$Domain   = "ad.potomacdefense.internal"
$PeopleOU = "OU=People,OU=PDS,DC=ad,DC=potomacdefense,DC=internal"
Add-Type -AssemblyName System.Web          # lets us generate random passwords

# Birthright group for each department (from docs/02-role-map.md)
$DeptGroups = @{
    "Engineering"        = "GG-Role-Engineers"
    "Program Management" = "GG-Role-ProgramManagers"
    "Finance"            = "GG-Role-Finance"
    "Human Resources"    = "GG-Role-HR"
    "Contracts"          = "GG-Role-Contracts"
    "Security"           = "GG-Role-Security"
}

foreach ($p in $Roster) {
    $name = "$($p.FirstName) $($p.LastName)"
    $sam  = ("$($p.FirstName).$($p.LastName)").ToLower()      # naming standard: first.last

    # Match on EmployeeID, never on name. Skip anyone who left.
    $existing = Get-ADUser -Filter "employeeID -eq '$($p.EmployeeID)'"
    if ($existing) { "$name : SKIP, already has an account"; continue }
    if ($p.Status -eq "Terminated") { "$name : SKIP, HR says Terminated"; continue }
    if ($p.EndDate -and [datetime]$p.EndDate -lt $Today) { "$name : SKIP, end date $($p.EndDate) has passed"; continue }

    # Birthright: everyone gets AllStaff, plus one group for their job (order matters: AP before Finance)
    $groups = @("GG-Role-AllStaff")
    if     ($p.WorkerType -eq "Subcontractor")          { $groups += "GG-Role-Subcontractors" }
    elseif ($p.JobTitle   -eq "Accounts Payable Clerk") { $groups += "GG-Role-AccountsPayable" }
    elseif ($p.JobTitle   -eq "Helpdesk Technician")    { $groups += "GG-Role-Helpdesk" }
    elseif ($DeptGroups.ContainsKey($p.Department))     { $groups += $DeptGroups[$p.Department] }

    # Conditional: engineers on a program need ALL checks to pass, or no program data
    if ($p.Program -and $p.Department -eq "Engineering") {
        $failed = @()
        if ($p.CUITraining     -ne "Yes") { $failed += "no CUI training" }
        if ($p.USPerson        -ne "Yes") { $failed += "not a US person" }
        if ($p.ProgramApproved -ne "Yes") { $failed += "not approved by PM" }
        if ($failed.Count -eq 0) { $groups += "GG-Role-$($p.Program)-Engineers" }
        else { "$name : PROGRAM ACCESS DENIED for $($p.Program) ($($failed -join ', '))" }
    }

    # Future start date = create the account but keep it disabled
    $startsLater = [datetime]$p.StartDate -gt $Today
    $state = if ($startsLater) { "DISABLED until $($p.StartDate)" } else { "enabled" }
    "$name : CREATE, $state -> $($groups -join ', ')"

    if ($DryRun) { continue }      # dry-run mode: print only

    # ---------- Create the account ----------
    $ou     = if ($p.WorkerType -eq "Subcontractor") { "OU=Subcontractors,$PeopleOU" } else { "OU=Employees,$PeopleOU" }
    $tempPw = ConvertTo-SecureString ([System.Web.Security.Membership]::GeneratePassword(16, 3)) -AsPlainText -Force   # never shown or saved

    New-ADUser -Name $name -GivenName $p.FirstName -Surname $p.LastName -DisplayName $name `
        -SamAccountName $sam -UserPrincipalName "$sam@$Domain" -EmployeeID $p.EmployeeID `
        -Department $p.Department -Title $p.JobTitle -Office $p.Office -Company "Potomac Defense Systems" `
        -Path $ou -AccountPassword $tempPw -ChangePasswordAtLogon $true -Enabled (-not $startsLater) `
        -OtherAttributes @{ employeeType = $p.WorkerType }

    if ($p.Program) { Set-ADUser $sam -Division $p.Program }       # store Program (used later for ABAC)
    if ($startsLater) { Set-ADUser $sam -Description "Pre-start: account disabled until start date $($p.StartDate) (HR)" }   # say WHY it's disabled
    foreach ($g in $groups) { Add-ADGroupMember -Identity $g -Members $sam }
}
