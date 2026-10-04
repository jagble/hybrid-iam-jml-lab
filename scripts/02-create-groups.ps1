$base   = "OU=PDS,DC=ad,DC=potomacdefense,DC=internal"
$roleOU = "OU=Role,OU=Groups,$base"
$resOU  = "OU=Resource,OU=Groups,$base"

# ROLE groups (Global scope): who people are
$roles = [ordered]@{
  "GG-Role-AllStaff"            = "Every employee and subcontractor: email, VPN, intranet"
  "GG-Role-Engineers"           = "Engineering birthright tools"
  "GG-Role-ProgramManagers"     = "Program managers; approve program access"
  "GG-Role-Finance"             = "Approve invoices. SoD conflict with AccountsPayable"
  "GG-Role-AccountsPayable"     = "Create vendors. SoD conflict with Finance"
  "GG-Role-HR"                  = "HR system and personnel files"
  "GG-Role-Contracts"           = "Contract files and customer portal"
  "GG-Role-Helpdesk"            = "Ticketing system. No admin rights"
  "GG-Role-Security"            = "Security logs (read)"
  "GG-Role-Subcontractors"      = "Email and VPN only"
  "GG-Role-Radar-Engineers"     = "Conditional: assigned to Radar and all checks passed"
  "GG-Role-Satellite-Engineers" = "Conditional: assigned to Satellite and all checks passed"
  "GG-Role-Shipboard-Engineers" = "Conditional: assigned to Shipboard and all checks passed"
}
foreach ($name in $roles.Keys) {
  New-ADGroup -Name $name -GroupScope Global -GroupCategory Security -Path $roleOU -Description $roles[$name]
}

# RESOURCE groups (Domain Local scope): what can be accessed
$resources = [ordered]@{
  "DL-Share-Radar-CUI-Modify"     = "Modify on Radar CUI share"
  "DL-Share-Satellite-CUI-Modify" = "Modify on Satellite CUI share"
  "DL-Share-Shipboard-CUI-Modify" = "Modify on Shipboard CUI share"
  "DL-Share-Engineering-Read"     = "Read on engineering share"
}
foreach ($name in $resources.Keys) {
  New-ADGroup -Name $name -GroupScope DomainLocal -GroupCategory Security -Path $resOU -Description $resources[$name]
}

# AGDLP: nest each role group into its resource group
Add-ADGroupMember "DL-Share-Radar-CUI-Modify"     -Members "GG-Role-Radar-Engineers"
Add-ADGroupMember "DL-Share-Satellite-CUI-Modify" -Members "GG-Role-Satellite-Engineers"
Add-ADGroupMember "DL-Share-Shipboard-CUI-Modify" -Members "GG-Role-Shipboard-Engineers"
Add-ADGroupMember "DL-Share-Engineering-Read"     -Members "GG-Role-Engineers"
