<#
.SYNOPSIS
Create or update a secure Exchange Receive Connector for anonymous SMTP relay
from one or more specific internal hosts, with DNS and IP conflict validation.

.DESCRIPTION
This script:
1. Displays a warning about proper usage.
2. Prompts for the Receive Connector name.
3. Prompts for one or more IP addresses (comma-separated).
4. For each IP:
   - Checks for a PTR (reverse DNS) record.
   - Checks that the PTR hostname resolves in forward DNS.
5. If any IP fails DNS checks, warns and exits without changes.
6. Checks if any of the entered IPs are already assigned to a different connector.
7. If no conflicts, checks if the connector exists:
   - If it exists, updates the allowed IP list and ensures relay permissions are set.
   - If it does not exist, creates it with the specified settings.
8. Grants "Anonymous Logon" the right to relay to external recipients ONLY for the specified IP(s).
9. Prevents open relay by restricting to the given IP(s) or ranges.

.NOTES
Version    : 2.1
Requires   : Exchange Management Shell, Exchange Org Admin rights
#>

# ======== WARNING ========
Write-Host ""
Write-Host "WARNING: Use this command only to add either single or multiple IP addresses of devices" -ForegroundColor Red
Write-Host "         that will send mail to this server via SMTP with a destination of outside of the enterprise." -ForegroundColor Red
Write-Host "         Do NOT run this if the SMTP device is a scanner or fax that will only send SMTP mail" -ForegroundColor Red
Write-Host "         to recipients inside the organization." -ForegroundColor Red
Write-Host ""
# =========================

# ======== USER INPUT ========
$ConnectorName = Read-Host "Enter the name for the Receive Connector"
$RemoteIPsInput = Read-Host "Enter the internal host IP(s) allowed to relay (comma-separated if multiple)"
$ExchangeServer = $env:COMPUTERNAME
$Port = 25
# ============================

# Convert comma-separated string to array of IPs/ranges
$RemoteIPRanges = $RemoteIPsInput -split "\s*,\s*"

# ======== PTR + FORWARD DNS CHECK ========
Write-Host "Checking DNS (PTR and forward lookup) for each IP..." -ForegroundColor Cyan
$dnsFailures = @()

foreach ($ip in $RemoteIPRanges) {
    try {
        $ptrRecord = [System.Net.Dns]::GetHostEntry($ip)
        $hostname = $ptrRecord.HostName

        if (-not $hostname) {
            $dnsFailures += [PSCustomObject]@{ IP = $ip; Reason = "No PTR record found" }
            continue
        }

        try {
            $forwardIPs = [System.Net.Dns]::GetHostAddresses($hostname)
            if (-not $forwardIPs -or $forwardIPs.Count -eq 0) {
                $dnsFailures += [PSCustomObject]@{ IP = $ip; Reason = "PTR hostname does not resolve in forward DNS" }
            }
        }
        catch {
            $dnsFailures += [PSCustomObject]@{ IP = $ip; Reason = "PTR hostname does not resolve in forward DNS" }
        }
    }
    catch {
        $dnsFailures += [PSCustomObject]@{ IP = $ip; Reason = "No PTR record found" }
    }
}

if ($dnsFailures.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: DNS validation failed for the following IP(s):" -ForegroundColor Red
    $dnsFailures | ForEach-Object { Write-Host "   $($_.IP) - $($_.Reason)" -ForegroundColor Yellow }
    exit
}
# =========================================

# ======== IP CONFLICT CHECK ========
Write-Host "Checking for IP conflicts on $ExchangeServer..." -ForegroundColor Cyan
$conflicts = @()

foreach ($ip in $RemoteIPRanges) {
    $matchingConnectors = Get-ReceiveConnector -Server $ExchangeServer -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $ConnectorName -and $_.RemoteIPRanges -contains $ip }

    if ($matchingConnectors) {
        foreach ($mc in $matchingConnectors) {
            $conflicts += [PSCustomObject]@{
                IPAddress = $ip
                Connector = $mc.Identity
            }
        }
    }
}

if ($conflicts.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: One or more of the entered IP addresses are already assigned to other connectors:" -ForegroundColor Red
    $conflicts | ForEach-Object { Write-Host "   IP: $($_.IPAddress)  -> Connector: $($_.Connector)" -ForegroundColor Yellow }
    exit
}
# ===================================

Write-Host ""
Write-Host "No DNS or IP conflicts found. Proceeding..." -ForegroundColor Green

try {
    $existingConnector = Get-ReceiveConnector -Server $ExchangeServer -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $ConnectorName }

    if ($existingConnector) {
        $connectorDN = $existingConnector.DistinguishedName
        $connectorIdentityString = $existingConnector.Identity.ToString()  # FIX for remote sessions

        Write-Host "Connector exists. Updating settings..." -ForegroundColor Yellow

        Set-ReceiveConnector -Identity $connectorIdentityString -RemoteIPRanges $RemoteIPRanges
        Set-ReceiveConnector -Identity $connectorIdentityString -PermissionGroups AnonymousUsers
        Set-ReceiveConnector -Identity $connectorIdentityString -TransportRole FrontendTransport

        $hasPermission = Get-ADPermission -Identity $connectorDN `
            -User "NT AUTHORITY\ANONYMOUS LOGON" -ErrorAction SilentlyContinue |
            Where-Object { $_.ExtendedRights -like "*Ms-Exch-SMTP-Accept-Any-Recipient*" }

        if (-not $hasPermission) {
            Add-ADPermission -Identity $connectorDN `
                -User "NT AUTHORITY\ANONYMOUS LOGON" `
                -ExtendedRights "Ms-Exch-SMTP-Accept-Any-Recipient"
        }

        Write-Host "Receive Connector updated successfully." -ForegroundColor Green
    }
    else {
        Write-Host "Connector does not exist. Creating new connector..." -ForegroundColor Cyan

        New-ReceiveConnector -Name $ConnectorName `
            -Server $ExchangeServer `
            -Usage Custom `
            -Bindings @{IPAddress="0.0.0.0"; Port=$Port} `
            -RemoteIPRanges $RemoteIPRanges `
            -TransportRole FrontendTransport `
            -PermissionGroups AnonymousUsers

        # Retrieve the newly created connector
        $newConnector = Get-ReceiveConnector -Server $ExchangeServer |
            Where-Object { $_.Name -eq $ConnectorName }

        # Use DistinguishedName for AD permission changes
        $connectorDN = $newConnector.DistinguishedName

        # Grant relay rights to Anonymous Logon
        Add-ADPermission -Identity $connectorDN `
            -User "NT AUTHORITY\ANONYMOUS LOGON" `
            -ExtendedRights "Ms-Exch-SMTP-Accept-Any-Recipient"

        Write-Host "Receive Connector created successfully." -ForegroundColor Green
    }

    # ======== VERIFY RELAY RIGHTS ========
    Write-Host "Verifying relay permissions..." -ForegroundColor Cyan
    $relayCheck = Get-ADPermission -Identity $connectorDN `
        -User "NT AUTHORITY\ANONYMOUS LOGON" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExtendedRights -like "*Ms-Exch-SMTP-Accept-Any-Recipient*" }

    if ($relayCheck) {
        Write-Host "Relay rights confirmed for Anonymous Logon." -ForegroundColor Green
    }
    else {
        Write-Host "WARNING: Relay rights could not be verified. Please check manually." -ForegroundColor Yellow
    }

    # ======== SUMMARY OUTPUT ========
    Write-Host ""
    Write-Host "================= SUMMARY =================" -ForegroundColor White
    Write-Host ("Connector Name : {0}" -f $ConnectorName) -ForegroundColor Yellow
    Write-Host ("Allowed IP(s)  : {0}" -f ($RemoteIPRanges -join ', ')) -ForegroundColor Yellow
    Write-Host ("Port           : {0}" -f $Port) -ForegroundColor Yellow
    Write-Host ("Server         : {0}" -f $ExchangeServer) -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor White
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
