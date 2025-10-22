Param(
    [string]$Url = "https://tenant.sharepoint.com/sites/site"
)

if ($null -eq (Get-Command Set-PnPTraceLog -ErrorAction SilentlyContinue)) {
    Write-Host "Last inn PnP.PowerShell modulen før du kjører skriptet!" -ForegroundColor Yellow
    exit 0
}

Start-Transcript -Path "$PSScriptRoot\Logs\FixExisting-$((Get-Date).ToString('yyyy-MM-dd-HH-mm')).txt"
$ErrorActionPreference = "Stop"
Set-PnPTraceLog -Off

$Uri = [System.Uri]$Url
$TenantAdminUrl = "https://" + $Uri.Authority.Replace(".sharepoint.com", "-admin.sharepoint.com")

try {
    Write-Host "Kobler til konfigurasjonsside for å hente liste over områder"
    Connect-PnPOnline -Url $TenantAdminUrl -Interactive -ClientId da6c31a6-b557-4ac3-9994-7315da06ea3a

    $ctx = Get-PnPContext
    $ctx.Load($ctx.Web.CurrentUser)
    $ctx.ExecuteQuery()
    $CurrentUser = $ctx.Web.CurrentUser.LoginName

    $HubSite = Get-PnPTenantSite -Identity $Url
    $HubSiteId = $HubSite.HubSiteId.Guid
    $AllSitesInHub = Get-PnPHubSiteChild -Identity $HubSiteId
    $SitesToProcess = @()

    if ($AllSitesInHub.length -gt 0) {
        Write-Host "Prosesserer $($AllSitesInHub.length) områder"
                
        $i = 0

        $AllSitesInHub | ForEach-Object {
            $i = $i + 1
            $TargetUrl = $_

            $Percentage = [math]::Round(($i * 100) / $AllSitesInHub.length)
            Write-Progress -Activity "Tilegner rettigheter for $CurrentUser på $($AllSitesInHub.length) områder" -Status "$Percentage% Ferdig" -PercentComplete $Percentage -CurrentOperation "Prosesserer $TargetUrl"

            try {
                $CurrentSite = Get-PnPTenantSite -Identity $TargetUrl
                if ($CurrentSite.LockState -eq "Unlock") {
                    Set-PnPTenantSite -Identity $TargetUrl -Owners $CurrentUser
                    $SitesToProcess += $TargetUrl
                }
            }
            catch {
                Write-Host "`tEn feil oppsto ved oppdatering av område $TargetUrl" -ForegroundColor Red
            }            
        }
        
        $i = 0
        $SitesToProcess | ForEach-Object {
            $i = $i + 1
            $TargetUrl = $_
            Write-Host "Prosesserer $TargetUrl"

            $Percentage = [math]::Round(($i * 100) / $SitesToProcess.length)
            Write-Progress -Activity "Prosesserer $($SitesToProcess.length) områder" -Status "$Percentage% Ferdig" -PercentComplete $Percentage -CurrentOperation "Prosesserer $TargetUrl"

            try {
                Connect-PnPOnline -Url $TargetUrl -Interactive -ClientId da6c31a6-b557-4ac3-9994-7315da06ea3a

                $List = Get-PnPList -Identity "Beslutningslogg" -ErrorAction SilentlyContinue
                if ($null -ne $List) {
                    $GtcPhaseProjectXml = '<Field ID="{e250dc6a-a894-4a34-b82d-4cb386bd941f}" DisplayName="Fase i prosjekt" Name="GtcPhaseProject" Type="Choice" Group="Kolonner for Prosjektportalen (Prosjekt)" Description="Legg in fase beslutningen er gjort i" FillInChoice="FALSE" StaticName="GtcPhaseProject"><Default>Utrede</Default><CHOICES><CHOICE>Utrede</CHOICE><CHOICE>Reguleringsplan</CHOICE><CHOICE>Byggeplan</CHOICE><CHOICE>Bygge</CHOICE><CHOICE>Overlevere DOV</CHOICE></CHOICES></Field>'
                    $GtcPhaseProject = Add-PnPFieldFromXml -FieldXml $GtcPhaseProjectXml
                    
                    Add-PnPFieldToContentType -Field "GtcPhaseProject" -ContentType "Prosjektloggelement"
                    
                    $View = Get-PnPView -List "Beslutningslogg" -Identity "Alle elementer"
                    $View.ViewFields.Add("GtcPhaseProject")
                    $View.Update()
                    Invoke-PnPQuery
                }
                else {
                    Write-Host "`tListen Beslutningslogg finnes ikke på $TargetUrl" -ForegroundColor Yellow
                }

            }
            catch {
                Write-Host "`tFeilmelding: $($Error[0].Exception.Message)" -f Red
            }
        }
    }
    else {
        Write-Host "Ingen områder å prosessere" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "En uforventet feil oppsto: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Stop-Transcript
}