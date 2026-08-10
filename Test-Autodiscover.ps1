<#
.SYNOPSIS
    Tests Autodiscover DNS and HTTP endpoints for a given email address.

.DESCRIPTION
    This script checks DNS records (A, AAAA, CNAME, SRV) for autodiscover.<domain>
    and tests HTTP(S) Autodiscover endpoints for Exchange / Office 365 connectivity.
    If credentials are provided, it sends two POST requests:
        1. Desktop Outlook schema (2006a)
        2. Mobile Outlook schema (mobilesync)
    Both XML responses are saved separately.

.PARAMETER EmailAddress
    The email address to test (used to extract the domain).

.PARAMETER Credential
    Optional. A PowerShell credential object for authenticated POST requests.

.PARAMETER SaveXmlPath
    Optional. Path to save XML responses and summary CSV.

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
    [string]$Domain,

    [Parameter(Mandatory = $true)]
    [string]$EmailAddress,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$SaveXmlPath
)

# --- Allow self-signed / invalid SSL certificates ---
add-type @"
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


Write-Host "`n=== Exchange / Autodiscover Diagnostic Tool ===`n" -ForegroundColor Cyan

## -------------------------
## DNS Lookups - compacted version, saved in comments as an example
## -------------------------
#try {
#    $aRecords = Resolve-DnsName "autodiscover.$Domain" -Type A -ErrorAction SilentlyContinue
#    if ($aRecords) { foreach ($rec in $aRecords) { Write-Host "A: $($rec.Name) -> $($rec.IPAddress)" -ForegroundColor Green } }
#    $aaaaRecords = Resolve-DnsName "autodiscover.$Domain" -Type AAAA -ErrorAction SilentlyContinue
#    if ($aaaaRecords) { foreach ($rec in $aaaaRecords) { Write-Host "AAAA: $($rec.Name) -> $($rec.IPAddress)" -ForegroundColor Green } }
#    $dnsResults = Resolve-DnsName "autodiscover.$Domain" -ErrorAction SilentlyContinue
#    $cnameRecords = $dnsResults | Where-Object { $_.QueryType -eq 'CNAME' }
#    if ($cnameRecords) { foreach ($rec in $cnameRecords) { Write-Host "CNAME: $($rec.Name) -> $($rec.NameHost)" -ForegroundColor Green } }
#    $srv = Resolve-DnsName "_autodiscover._tcp.$Domain" -Type SRV -ErrorAction SilentlyContinue
#    if ($srv) { foreach ($rec in $srv) { Write-Host "SRV: _autodiscover._tcp.$Domain -> $($rec.NameTarget) Port: $($rec.Port)" -#ForegroundColor Green } }
#}
#catch { Write-Host "DNS lookup error: $_" -ForegroundColor Red }

## -------------------------
## DNS Lookups - enhanced version
## -------------------------

Write-Host "`nChecking DNS records for Autodiscover..." -ForegroundColor Cyan

# -------------------------
# A record
# -------------------------
$aRecords = Resolve-DnsName "autodiscover.$Domain" -Type A -ErrorAction SilentlyContinue |
            Where-Object { $_.QueryType -eq 'A' -and $_.IPAddress }

if ($aRecords) {
    foreach ($rec in $aRecords) {
        Write-Host "Main or glue A records: autodiscover.$Domain -> $($rec.IPAddress)" -ForegroundColor Green
    }
} else {
    Write-Host "No A record found for autodiscover.$Domain" -ForegroundColor Yellow
}

# -------------------------
# AAAA record
# -------------------------
$aaaaRecords = Resolve-DnsName "autodiscover.$Domain" -Type AAAA -ErrorAction SilentlyContinue |
               Where-Object { $_.QueryType -eq 'AAAA' -and $_.IPAddress }

if ($aaaaRecords) {
    foreach ($rec in $aaaaRecords) {
        Write-Host "AAAA Record: autodiscover.$Domain -> $($rec.IPAddress)" -ForegroundColor Green
    }
} else {
    Write-Host "No AAAA record found for autodiscover.$Domain" -ForegroundColor Yellow
}

# -------------------------
# CNAME record (filter out glue)
# -------------------------
$dnsResults = Resolve-DnsName "autodiscover.$Domain" -Type CNAME -ErrorAction SilentlyContinue
$cnameRecords = $dnsResults | Where-Object { $_.QueryType -eq 'CNAME' -and $_.NameHost }
$glueRecords  = $dnsResults | Where-Object { $_.QueryType -in @('A','AAAA') -and $_.IPAddress }

if ($cnameRecords) {
    foreach ($rec in $cnameRecords) {
        Write-Host "CNAME: autodiscover.$Domain -> $($rec.NameHost)" -ForegroundColor Green
    }
} else {
    Write-Host "No CNAME record found for autodiscover.$Domain" -ForegroundColor Yellow
}

if ($glueRecords) {
    foreach ($rec in $glueRecords) {
        Write-Host "Glue: $($rec.Name) -> $($rec.IPAddress)" -ForegroundColor DarkGray
    }
}

# -------------------------
# SRV record
# -------------------------
$srv = Resolve-DnsName "_autodiscover._tcp.$Domain" -Type SRV -ErrorAction SilentlyContinue |
       Where-Object { $_.QueryType -eq 'SRV' -and $_.NameTarget }
if ($srv) {
    foreach ($rec in $srv) {
        Write-Host "SRV: _autodiscover._tcp.$Domain -> $($rec.NameTarget) Port: $($rec.Port) Priority: $($rec.Priority) Weight: $($rec.Weight)" -ForegroundColor Green
    }
} else {
    Write-Host "No SRV record found for _autodiscover._tcp.$Domain" -ForegroundColor Yellow
}


# -------------------------
# HTTP Autodiscover Tests
# -------------------------
$Urls = @(
    "https://$Domain/autodiscover/autodiscover.xml",
    "https://autodiscover.$Domain/autodiscover/autodiscover.xml"
)

Write-Host "`nTesting Autodiscover HTTP endpoints for $EmailAddress..." -ForegroundColor Cyan
$HttpResults = @{}

foreach ($Url in $Urls) {
    Write-Host "Checking $Url ..." -ForegroundColor Yellow
    $StartTime = Get-Date
    try {
        if ($Credential) {
            # --- Outlook schema POST body ---
            $OutlookBody = @"
<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006">
  <Request>
    <EMailAddress>$EmailAddress</EMailAddress>
    <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a</AcceptableResponseSchema>
  </Request>
</Autodiscover>
"@

            # --- Desktop Outlook POST ---
            $DesktopResponse = Invoke-WebRequest -Uri $Url `
                -Method POST `
                -Credential $Credential `
                -ContentType "text/xml; charset=utf-8" `
                -Body $OutlookBody `
                -UseBasicParsing `
                -TimeoutSec 90

            # --- "Mobile" Outlook POST (full XML) ---
            $MobileResponse = Invoke-WebRequest -Uri $Url `
                -Method POST `
                -Credential $Credential `
                -ContentType "text/xml; charset=utf-8" `
                -Body $OutlookBody `
                -UseBasicParsing `
                -TimeoutSec 90 `
                -MaximumRedirection 0

            # --- Real MobileSync POST (short XML) ---
            $MobileSyncBody = @"
<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/requestschema/2006">
  <Request>
    <EMailAddress>$EmailAddress</EMailAddress>
    <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006</AcceptableResponseSchema>
  </Request>
</Autodiscover>
"@
            $MobileSyncResponse = Invoke-WebRequest -Uri $Url `
                -Method POST `
                -Credential $Credential `
                -ContentType "text/xml; charset=utf-8" `
                -Body $MobileSyncBody `
                -UseBasicParsing `
                -TimeoutSec 90 `
                -MaximumRedirection 0

            # Save XMLs if requested
            if ($SaveXmlPath) {
                try {
                    if (Test-Path $SaveXmlPath -PathType Container) {
                        $baseName = ($Url -replace 'https?://','' -replace '[^a-zA-Z0-9\.-]','_')
                        $desktopPath = Join-Path $SaveXmlPath ("autodiscover_" + $baseName + "_desktop.xml")
                        $mobilePath  = Join-Path $SaveXmlPath ("autodiscover_" + $baseName + "_mobile.xml")
                        $mobilesyncPath = Join-Path $SaveXmlPath ("autodiscover_" + $baseName + "_mobilesync.xml")
                    } else {
                        $desktopPath = $SaveXmlPath + "_desktop.xml"
                        $mobilePath  = $SaveXmlPath + "_mobile.xml"
                        $mobilesyncPath = $SaveXmlPath + "_mobilesync.xml"
                    }
                    $DesktopResponse.Content     | Out-File -FilePath $desktopPath -Encoding UTF8
                    $MobileResponse.Content      | Out-File -FilePath $mobilePath -Encoding UTF8
                    $MobileSyncResponse.Content  | Out-File -FilePath $mobilesyncPath -Encoding UTF8
                    Write-Host "Saved desktop XML to $desktopPath" -ForegroundColor DarkCyan
                    Write-Host "Saved mobile XML to $mobilePath" -ForegroundColor DarkCyan
                    Write-Host "Saved MobileSync XML to $mobilesyncPath" -ForegroundColor DarkCyan
                }
                catch { Write-Host "Failed to save autodiscover XML: $_" -ForegroundColor Red }
            }

            # --- EAS/IMAP Detection (now scans all three XMLs) ---
            $CombinedContent = $DesktopResponse.Content + "`n" + $MobileResponse.Content + "`n" + $MobileSyncResponse.Content
            $Elapsed = (Get-Date) - $StartTime

            $imapFound = $CombinedContent -match "(?i)imap"
            $easFound  = $CombinedContent -match "(?i)(eas|activesync)"

            if ($imapFound -and $easFound) {
                Write-Host ("WARNING: {0} returned XML containing both 'IMAP' and 'EAS/ActiveSync' in {1:N1} seconds - Mixed protocols detected" -f $Url, $Elapsed.TotalSeconds) -ForegroundColor Magenta
                $HttpResults[$Url] = "IMAP + EAS DETECTED"
            }
            elseif ($imapFound) {
                Write-Host ("WARNING: {0} returned XML containing 'IMAP' in {1:N1} seconds - Likely non-Exchange mailserver" -f $Url, $Elapsed.TotalSeconds) -ForegroundColor Magenta
                $HttpResults[$Url] = "IMAP DETECTED"
            }
            elseif ($easFound) {
                Write-Host ("NOTICE: {0} returned XML containing 'EAS/ActiveSync' in {1:N1} seconds - Exchange ActiveSync detected" -f $Url, $Elapsed.TotalSeconds) -ForegroundColor Cyan
                $HttpResults[$Url] = "EAS DETECTED"
            }
            else {
                Write-Host ("PASS: {0} returned XML in {1:N1} seconds" -f $Url, $Elapsed.TotalSeconds) -ForegroundColor Green
                $HttpResults[$Url] = "PASS"
            }
        }
        else {
            # --- No credentials: simple GET request ---
            $Response = Invoke-WebRequest -Uri $Url `
                -Method GET `
                -UseBasicParsing `
                -TimeoutSec 90
            $Elapsed = (Get-Date) - $StartTime
            if ($Response.Content.TrimStart() -match "^<\?xml") {
                Write-Host ("PASS: {0} returned XML in {1:N1} seconds" -f $Url, $Elapsed.TotalSeconds) -ForegroundColor Green
                $HttpResults[$Url] = "PASS"
            } else {
                Write-Host ("FAIL: {0} returned non-XML content" -f $Url) -ForegroundColor Red
                $HttpResults[$Url] = "FAIL"
            }
        }
    }
    catch {
        $Elapsed = (Get-Date) - $StartTime
        Write-Host ("ERROR: {0} - {1} (after {2:N1} seconds)" -f $Url, $_.Exception.Message, $Elapsed.TotalSeconds) -ForegroundColor Red
        $HttpResults[$Url] = "ERROR"
    }
}

Write-Host "`nAutodiscover test completed." -ForegroundColor Cyan

# -------------------------
# Advisory Message
# -------------------------
Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "A normal HTTP error for an unauthenticated request is 401 Unauthorized, 404 Not Found, 500 Internal Server Error" -ForegroundColor Yellow
Write-Host "Mobile clients may hang or fail to proceed to the next Autodiscover step if they receive 403, 402, 422, or other non-500 errors." -ForegroundColor Yellow
Write-Host "Ensure that misconfigured endpoints return a proper 404 error or are removed from DNS to avoid delays." -ForegroundColor Yellow
Write-Host "Mailservers should not have AAAA records unless they have valid IPv6 connectivity to the Internet." -ForegroundColor Yellow


# -------------------------
# Summary Table
# -------------------------
Write-Host "`nSummary:" -ForegroundColor Cyan

$Summary = @()

# DNS summary
$Summary += [PSCustomObject]@{ Test = "A Record";       Result = $(if ($aRecords) { "Found" } else { "Missing" }) }
$Summary += [PSCustomObject]@{ Test = "AAAA Record";    Result = $(if ($aaaaRecords) { "Found" } else { "Missing" }) }
$Summary += [PSCustomObject]@{ Test = "CNAME Record";   Result = $(if ($cnameRecords) { "Found" } else { "Missing" }) }
$Summary += [PSCustomObject]@{ Test = "SRV Record";     Result = $(if ($srv) { "Found" } else { "Missing" }) }

# HTTP summary
foreach ($Url in $Urls) {
    $Summary += [PSCustomObject]@{
        Test   = "HTTP Test: $Url"
        Result = $HttpResults[$Url]
    }
}

# Output the summary table
$Summary | Format-Table -AutoSize

# -------------------------
# Optional CSV Export
# -------------------------
if ($SaveXmlPath -and (Test-Path $SaveXmlPath -PathType Container)) {
    try {
        $csvPath = Join-Path $SaveXmlPath "Autodiscover_Summary.csv"
        $Summary | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Summary exported to $csvPath" -ForegroundColor DarkCyan
    }
    catch {
        Write-Host "Failed to export summary to CSV: $_" -ForegroundColor Red
    }
}

Write-Host "`nTest complete." -ForegroundColor Cyan


