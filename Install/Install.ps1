Param(
  [Parameter(Mandatory = $true, HelpMessage = "URL to the Prosjektportalen hub site")]
  [string]$Url,
  [Parameter(Mandatory = $false, HelpMessage = "Skip search configuration")]
  [switch]$SkipSearchConfiguration,
  [Parameter(Mandatory = $false, HelpMessage = "Do you want to perform an upgrade?")]
  [switch]$Upgrade
)

<#
Starts an action and writes the action name to the console. Make sure to update the $global:ACTIONS_COUNT before
adding a new action. Uses -NoNewline to avoid a line break before the elapsed time is written.
#>
function StartAction($Action) {
  $global:StopWatch_Action = [Diagnostics.Stopwatch]::StartNew()
  Write-Host "$Action... " -NoNewline
}

<#
Ends an action and writes the elapsed time to the console.
#>
function EndAction() {
  $global:StopWatch_Action.Stop()
  $ElapsedSeconds = [math]::Round(($global:StopWatch_Action.ElapsedMilliseconds) / 1000, 2)
  Write-Host "Completed in $($ElapsedSeconds)s" -ForegroundColor Green
}

## TODO: Create install script

#region Setting variables based on input from user
[System.Uri]$Uri = $Url.TrimEnd('/')
$ManagedPath = $Uri.Segments[1]
$Alias = $Uri.Segments[2]
$AdminSiteUrl = (@($Uri.Scheme, "://", $Uri.Authority) -join "").Replace(".sharepoint.com", "-admin.sharepoint.com")
$TemplatesBasePath = "$PSScriptRoot/Templates"
#endregion

# TODO: Replace version from package.json/git-tag
Write-Host "Installing Prosjektportalen veimodul version 1.0.0" -ForegroundColor Cyan

#region Print installation user
Connect-PnPOnline -Url $AdminSiteUrl -Interactive -ErrorAction Stop -WarningAction Ignore
$CurrentUser = Get-PnPProperty -Property CurrentUser -ClientObject (Get-PnPContext).Web
Write-Host "[INFO] Installing with user [$($CurrentUser.Email)]"
#endregion

#region Search Configuration 
if (-not $SkipSearchConfiguration.IsPresent) {
  StartAction("Uploading search configuration")
  Try {
    Connect-PnPOnline -Url $AdminSiteUrl -Interactive -ErrorAction Stop -WarningAction Ignore
    Set-PnPSearchConfiguration -Scope Subscription -Path "$PSScriptRoot/SearchConfiguration.xml" -ErrorAction SilentlyContinue
    EndAction
  }
  Catch {
    EndAction
    Write-Host "[WARNING] Failed to import Search Configuration: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}
#endregion


#region Apply Template
StartAction("Applying veimodul template")
Connect-PnPOnline -Url $Url -Interactive -ErrorAction Stop
Invoke-PnPSiteTemplate -Path "$($TemplatesBasePath)/veimodul.pnp" -ErrorAction Stop
EndAction
#endregion

#region Configure tillegg and standardinnhold
StartAction("Configuring tillegg and standardinnhold")
try {

  Connect-PnPOnline -Url $Url -Interactive -ErrorAction Stop

  $ListContent = Get-PnPListItem -List Listeinnhold
  $Prosjekttillegg = Get-PnPListItem -List Prosjekttillegg
  $Maloppsett = Get-PnPListItem -List Maloppsett
  
  $VeiTemplate = $Maloppsett | Where-Object { $_["Title"] -eq "Veiprosjekt" }
  if ($null -ne $VeiTemplate) {
    $VeiPlanner = $ListContent | Where-Object { $_["Title"] -eq "Planneroppgaver Vei" }
    $VeiPhaseChecklist = $ListContent | Where-Object { $_["Title"] -eq "Fasesjekkpunkter Vei" }
    $VeiDocuments = $ListContent | Where-Object { $_["Title"] -eq "Standarddokumenter Vei" }
    $VeiItems = @()
    $VeiItems += [Microsoft.SharePoint.Client.FieldLookupValue]@{"LookupId" = $VeiPlanner.Id }
    $VeiItems += [Microsoft.SharePoint.Client.FieldLookupValue]@{"LookupId" = $VeiPhaseChecklist.Id }
    $VeiItems += [Microsoft.SharePoint.Client.FieldLookupValue]@{"LookupId" = $VeiDocuments.Id }
    $VeiTemplate["ListContentConfigLookup"] = $VeiItems
      
    $VeiTillegg = $Prosjekttillegg | Where-Object { $_["Title"] -eq "Veimal" }
    $VeiTemplate["GtProjectExtensions"] = [Microsoft.SharePoint.Client.FieldLookupValue]@{"LookupId" = $VeiTillegg.Id }
  
    $VeiTemplate.SystemUpdate()
    $VeiTemplate.Context.ExecuteQuery()
  }
  else {
    Write-Host "[WARNING] Failed to find Veiprosjekt template. Please check the Maloppsett list." -ForegroundColor Yellow
  }
}
catch {
  EndAction
  Write-Host "[WARNING] Failed to configure tillegg and standardinnhold: $($_.Exception.Message)" -ForegroundColor Yellow
}
EndAction
#endregion

#region Logging installation
Write-Host "[INFO] Logging installation entry" 
Connect-PnPOnline -Url $Url -Interactive -ErrorAction Stop
$LastInstall = Get-PnPListItem -List "Installasjonslogg" -Query "<View><Query><OrderBy><FieldRef Name='Created' Ascending='False' /></OrderBy></Query></View>" | Select-Object -First 1 -Wait
$PreviousVersion = "N/A"
if ($null -ne $LastInstall) {
  $PreviousVersion = $LastInstall.FieldValues["InstallVersion"]
}
# TODO: Replace version from package.json/git-tag
$CustomizationInfo = "Prosjektportalen veimodul 1.0.0"
$InstallStartTime = (Get-Date -Format o)
$InstallEndTime = (Get-Date -Format o)

$InstallEntry = @{
  Title            = $CustomizationInfo;
  InstallStartTime = $InstallStartTime; 
  InstallEndTime   = $InstallEndTime; 
  InstallVersion   = $PreviousVersion;
  InstallCommand   = $MyInvocation.Line.Substring(2);
}

if ($null -ne $CurrentUser.Email) {
  $InstallEntry.InstallUser = $CurrentUser.Email
}

## Logging installation to SharePoint list
Add-PnPListItem -List "Installasjonslogg" -Values $InstallEntry -ErrorAction SilentlyContinue >$null 2>&1

#endregion
