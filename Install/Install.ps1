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

#region Print installation user
Connect-PnPOnline -Url $AdminSiteUrl -Interactive -ErrorAction Stop -WarningAction Ignore
$CurrentUser = Get-PnPProperty -Property CurrentUser -ClientObject (Get-PnPContext).Web
Write-Host "[INFO] Installing with user [$($CurrentUser.Email)]"
Disconnect-PnPOnline
#endregion

#region Search Configuration 
if (-not $SkipSearchConfiguration.IsPresent) {
  Try {
    Connect-PnPOnline -Url $AdminSiteUrl -Interactive -ErrorAction Stop -WarningAction Ignore
    Set-PnPSearchConfiguration -Scope Subscription -Path "$PSScriptRoot/SearchConfiguration.xml" -ErrorAction SilentlyContinue   
    Disconnect-PnPOnline
  }
  Catch {
    Write-Host "[WARNING] Failed to import Search Configuration: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}
#endregion


#region Apply Template
StartAction("Applying veimodul template")
Connect-PnPOnline -Url $Url -Interactive -ErrorAction Stop
Invoke-PnPSiteTemplate -Path "$($TemplatesBasePath)/veimodul.pnp"
Disconnect-PnPOnline
EndAction
#endregion
