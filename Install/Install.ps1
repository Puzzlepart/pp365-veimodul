Param(
  [Parameter(Mandatory = $true, HelpMessage = "URL to the Prosjektportalen hub site")]
  [string]$Url,
  [Parameter(Mandatory = $false, HelpMessage = "Skip search configuration")]
  [switch]$SkipSearchConfiguration,
  [Parameter(Mandatory = $false, HelpMessage = "Client ID of the Entra Id application used for interactive logins. Defaults to the multi-tenant Prosjektportalen app")]
  [string]$ClientId = "da6c31a6-b557-4ac3-9994-7315da06ea3a",
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

#region Setting variables based on input from user
[System.Uri]$Uri = $Url.TrimEnd('/')
$ManagedPath = $Uri.Segments[1]
$Alias = $Uri.Segments[2]
$AdminSiteUrl = (@($Uri.Scheme, "://", $Uri.Authority) -join "").Replace(".sharepoint.com", "-admin.sharepoint.com")
$TemplatesBasePath = "$PSScriptRoot/Templates"
#endregion

if ($null -eq (Get-Command Connect-PnPOnline) -or (Get-Command Connect-PnPOnline).Version -lt [version]"3.1.0") {
    Write-Host "[ERROR] Correct PnP.PowerShell module not found. Please install it from PowerShell Gallery or do not use -SkipLoadingBundle." -ForegroundColor Red
    exit 0
}

$LogFilePath = "$PSScriptRoot/Install_Log_$([datetime]::Now.ToString("yy-MM-ddThh-mm-ss")).txt"
Start-PnPTraceLog -Path $LogFilePath -Level Debug

Write-Host "Installing Prosjektportalen veimodul version {{VERSION}}" -ForegroundColor Cyan

#region Print installation user
Connect-PnPOnline -Url $AdminSiteUrl -ClientId $ClientId -ErrorAction Stop -WarningAction Ignore
$CurrentUser = Get-PnPProperty -Property CurrentUser -ClientObject (Get-PnPContext).Web
Write-Host "[INFO] Installing with user [$($CurrentUser.Email)]"
#endregion

#region Search Configuration 
if (-not $SkipSearchConfiguration.IsPresent) {
  StartAction("Uploading search configuration")
  Try {
    Connect-PnPOnline -Url $AdminSiteUrl -ClientId $ClientId -ErrorAction Stop -WarningAction Ignore
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
Connect-PnPOnline -Url $Url -ClientId $ClientId -ErrorAction Stop
Invoke-PnPSiteTemplate -Path "$($TemplatesBasePath)/veimodul.pnp" -ErrorAction Stop -WarningAction Ignore
EndAction
#endregion

#region Configure tillegg and standardinnhold
StartAction("Configuring tillegg and standardinnhold")
try {

  Connect-PnPOnline -Url $Url -ClientId $ClientId -ErrorAction Stop

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
  Write-Host "[WARNING] Failed to configure tillegg and standardinnhold: $($_.Exception.Message)" -ForegroundColor Yellow
} finally {
  EndAction
}
#endregion

#region Logging installation
Write-Host "[INFO] Logging installation entry" 
Connect-PnPOnline -Url $Url -ClientId $ClientId -ErrorAction Stop
$LastInstall = Get-PnPListItem -List "Installasjonslogg" -Query "<View><Query><OrderBy><FieldRef Name='Created' Ascending='False' /></OrderBy></Query></View>" | Select-Object -First 1 -Wait
$PreviousVersion = "N/A"
$PreviousChannel = "main"
if ($null -ne $LastInstall) {
  $PreviousVersion = $LastInstall.FieldValues["InstallVersion"]
  $PreviousChannel = $LastInstall.FieldValues["InstallChannel"]
}
$CustomizationInfo = "Prosjektportalen veimodul {{VERSION}}"
$InstallStartTime = (Get-Date -Format o)
$InstallEndTime = (Get-Date -Format o)

$InstallEntry = @{
  Title            = $CustomizationInfo;
  InstallStartTime = $InstallStartTime; 
  InstallEndTime   = $InstallEndTime; 
  InstallVersion   = $PreviousVersion;
  InstallChannel   = $PreviousChannel;
  InstallCommand   = $MyInvocation.Line.Substring(2);
}

if ($null -ne $CurrentUser.Email) {
  $InstallEntry.InstallUser = $CurrentUser.Email
}

## Logging installation to SharePoint list
$InstallLogOutput = Add-PnPListItem -List "Installasjonslogg" -Values $InstallEntry -ErrorAction SilentlyContinue

#endregion

Write-Host "Installation of veimodulen complete!" -ForegroundColor Green