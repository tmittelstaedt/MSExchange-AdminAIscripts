<#
.SYNOPSIS
    ExchangeMaxScan-DeepScan.ps1  Exchange version fingerprinter

.LICENSE
    SPDX-License-Identifier: BSD-3-Clause

.LEGAL    
    Copyright (c) 2026, Ted Mittelstaedt/Portlandia IT LLC
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, 
       this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.

    3. Neither the name of the copyright holder nor the names of its 
       contributors may be used to endorse or promote products derived from 
       this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9.-]+$')]
    [string]$ExchangeServerFQDN,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$EmailAddress
)

# Ignore invalid SSL certs
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Endpoints to scan
$paths = @(
    "/owa/",
    "/ecp/",
    "/mapi/",
    "/rpc/",
    "/autodiscover/autodiscover.xml"
)

# Directory to save raw responses
$logDir = ".\ExchangeScanLogs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Save-Response {
    param($url, $content)
    $safeName = ($url -replace '[^a-zA-Z0-9]', '_')
    $filePath = Join-Path $logDir "$safeName.txt"
    $content | Out-File -FilePath $filePath -Encoding ASCII
}

# Updated regex: match 15.x.x or 15.x.x.x
function Get-BuildFromText {
    param([string]$text)
    if ($null -ne $text -and $text -match "15\.\d+\.\d+(?:\.\d+)?") {
        return $matches[0]
    }
    return $null
}

function Scan-Endpoint {
    param($url, $Cred)
    try {
        if ($Cred) {
            return Invoke-WebRequest -Uri $url -Credential $Cred -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
        } else {
            return Invoke-WebRequest -Uri $url -UseDefaultCredentials -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
        }
    }
    catch { return $null }
}

function Scan-Autodiscover {
    param($FQDN, $Cred, $Email)
    if (-not $Email) {
        Write-Warning "Skipping autodiscover POST because no -EmailAddress was provided."
        return $null
    }

    $uri = "https://${FQDN}/autodiscover/autodiscover.xml"
    $authInfo = ("{0}:{1}" -f $Cred.UserName, $Cred.GetNetworkCredential().Password)
    $authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authInfo))

    $headers = @{
        "Authorization" = $authHeader
        "Content-Type"  = "text/xml"
    }

    $body = @"
<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006">
  <Request>
    <EMailAddress>$Email</EMailAddress>
    <AcceptableResponseSchema>
      http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a
    </AcceptableResponseSchema>
  </Request>
</Autodiscover>
"@

    try {
        return Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
    }
    catch {
        Write-Warning "Autodiscover POST failed: $_"
        return $null
    }
}

$script:foundBuilds = @()

function Process-Response {
    param($url, $resp, $scheme)

    if (-not $resp) { return }

    Save-Response -url $url -content $resp.Content

    # 1. Headers
    foreach ($headerName in $resp.Headers.Keys) {
        $build = Get-BuildFromText $resp.Headers[$headerName]
        if ($build) {
            $script:foundBuilds += [PSCustomObject]@{
                Endpoint = $url
                Source   = "Header: $headerName"
                Build    = $build
            }
        }
    }

    # 2. Scan entire body text
    $buildFromBody = Get-BuildFromText $resp.Content
    if ($buildFromBody) {
        $script:foundBuilds += [PSCustomObject]@{
            Endpoint = $url
            Source   = "Body Content"
            Build    = $buildFromBody
        }
    }

    # 3. Extract and scan linked resources
    $links = @()

    if ($resp.Links)    { $links += $resp.Links.href }
    if ($resp.Scripts)  { $links += $resp.Scripts.src }

    try {
        if ($resp.ParsedHtml -and $resp.ParsedHtml.getElementsByTagName("link")) {
            foreach ($lnk in $resp.ParsedHtml.getElementsByTagName("link")) {
                if ($lnk.href) { $links += $lnk.href }
            }
        }
    } catch { }

    $cssMatches = [regex]::Matches($resp.Content, 'url\(["'']?([^)"'']+)["'']?\)')
    foreach ($m in $cssMatches) { $links += $m.Groups[1].Value }

    $links = $links | Where-Object { $_ -and ($_ -like "/*" -or $_ -like "http*") }
    $links = $links | Select-Object -Unique

    foreach ($link in $links) {
        # Always check the link string itself first
        $buildFromLink = Get-BuildFromText $link
        if ($buildFromLink) {
            $script:foundBuilds += [PSCustomObject]@{
                Endpoint = $url
                Source   = "Link Reference"
                Build    = $buildFromLink
            }
        }

        if ($link -like "*microsoft.com*") { continue }
        $fullUrl = if ($link -like "http*") { $link } else { "${scheme}://${ExchangeServerFQDN}$link" }

        try {
            if ($Credential) {
                $res = Invoke-WebRequest -Uri $fullUrl -Credential $Credential -UseBasicParsing -ErrorAction Stop
            } else {
                $res = Invoke-WebRequest -Uri $fullUrl -UseDefaultCredentials -UseBasicParsing -ErrorAction Stop
            }
            Save-Response -url $fullUrl -content $res.Content

            # Scan fetched resource content
            $buildFromRes = Get-BuildFromText $res.Content
            if ($buildFromRes) {
                $script:foundBuilds += [PSCustomObject]@{
                    Endpoint = $fullUrl
                    Source   = "Resource Content"
                    Build    = $buildFromRes
                }
            }

            # Scan CSS url() references inside fetched resources
            $cssMatchesRes = [regex]::Matches($res.Content, 'url\(["'']?([^)"'']+)["'']?\)')
            foreach ($m in $cssMatchesRes) {
                $cssUrl = $m.Groups[1].Value
                $buildFromCssUrl = Get-BuildFromText $cssUrl
                if ($buildFromCssUrl) {
                    $script:foundBuilds += [PSCustomObject]@{
                        Endpoint = $fullUrl
                        Source   = "CSS URL Reference"
                        Build    = $buildFromCssUrl
                    }
                }
            }

        } catch {
            Write-Warning "Failed to fetch linked resource: $fullUrl"
        }
    }
}

Write-Host "Scanning $ExchangeServerFQDN for Exchange version leaks..." -ForegroundColor Cyan

foreach ($path in $paths) {
    foreach ($scheme in @("https", "http")) {
        $url = "${scheme}://${ExchangeServerFQDN}$path"
        Write-Host "Checking $url ..." -ForegroundColor Yellow

        $resp = $null
        if ($path -eq "/autodiscover/autodiscover.xml" -and $Credential -and $scheme -eq "https") {
            $resp = Scan-Autodiscover -FQDN $ExchangeServerFQDN -Cred $Credential -Email $EmailAddress
        } else {
            $resp = Scan-Endpoint -url $url -Cred $Credential
        }

        if (-not $resp) {
            Write-Host "Failed to connect to $url" -ForegroundColor DarkGray
            continue
        }

        Process-Response -url $url -resp $resp -scheme $scheme
    }
}

# --- Final output ---
if ($script:foundBuilds.Count -gt 0) {
    Write-Host "`nPossible Exchange build numbers found:" -ForegroundColor Green
    $script:foundBuilds |
        Sort-Object Build -Unique |
        Format-Table -AutoSize
    Write-Host "`nRaw responses saved in: $logDir" -ForegroundColor Cyan
    Write-Host "You can search them with:" -ForegroundColor Cyan
    Write-Host "Select-String -Path $logDir\* -Pattern '15\.\d+\.\d+(?:\.\d+)?'" -ForegroundColor Yellow
} else {
    Write-Warning "No version information found on any tested endpoint."
    Write-Host "`nRaw responses saved in: $logDir" -ForegroundColor Cyan
    Write-Host "You can manually inspect them for hidden leaks." -ForegroundColor Cyan
    Write-Host "For example, run:" -ForegroundColor Cyan
    Write-Host "Select-String -Path $logDir\* -Pattern '15\.\d+\.\d+(?:\.\d+)?'" -ForegroundColor Yellow
}

Write-Host "`nScan complete." -ForegroundColor Green

