<#
.SYNOPSIS
Builds a release package for Prosjektportalen 365 veimodul

.DESCRIPTION
Builds a release package for Prosjektportalen 365 veimodul. The release package contains all files needed to install Prosjektportalen 365 veimodul in a PP365 installation.
#>

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

$StopWatch = [Diagnostics.Stopwatch]::StartNew()
$global:StopWatch_Action = $null
#endregion

#region Paths
$START_PATH = Get-Location
$ROOT_PATH = "$PSScriptRoot/.."
$PNP_TEMPLATES_BASEPATH = "$ROOT_PATH/Templates"
$GIT_HASH = git log --pretty=format:'%h' -n 1
$RELEASE_NAME = "pp365-veimodul-1.1.0.$($GIT_HASH)"
if ($USE_CHANNEL_CONFIG) {
    $RELEASE_NAME = "$($RELEASE_NAME)"
}
$RELEASE_PATH = "$ROOT_PATH/release/$($RELEASE_NAME)"
#endregion

Write-Host "[Building release $RELEASE_NAME]" -ForegroundColor Cyan

#region Creating release folder
$RELEASE_FOLDER = New-Item -Path "$RELEASE_PATH" -ItemType Directory -Force
$RELEASE_PATH = $RELEASE_FOLDER.FullName

StartAction("Creating release folder release/$($RELEASE_FOLDER.BaseName)")
$RELEASE_PATH_TEMPLATES = (New-Item -Path "$RELEASE_PATH/Templates" -ItemType Directory -Force).FullName
$PNP_TEMPLATES_DIST_BASEPATH = "$ROOT_PATH/.dist/Templates"
EndAction
#endregion  

Set-Location $PSScriptRoot
StartAction("Building Portfolio PnP template")
Convert-PnPFolderToSiteTemplate -Out "$RELEASE_PATH_TEMPLATES/Veimodul.pnp" -Folder "$PNP_TEMPLATES_BASEPATH/Veimodul" -Force
EndAction

#region Copying source files
StartAction("Copying Install.ps1 and script source files")

Copy-Item -Path "$PSScriptRoot/Install.ps1" -Destination $RELEASE_PATH -Force
Copy-Item -Path "$PSScriptRoot/SearchConfiguration.xml" -Destination $RELEASE_PATH -Force
EndAction
#endregion

#region Compressing release to a zip file
rimraf "$($RELEASE_PATH).zip"
Add-Type -Assembly "System.IO.Compression.FileSystem"
[IO.Compression.ZipFile]::CreateFromDirectory($RELEASE_PATH, "$($RELEASE_PATH).zip")  
$StopWatch.Stop()
Write-Host "Done building release $RELEASE_NAME in $($StopWatch.ElapsedMilliseconds/1000)s" -ForegroundColor Green
Set-Location $START_PATH

#endregion
