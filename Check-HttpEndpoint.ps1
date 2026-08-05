param(
    [Parameter(Mandatory = $true)]
    [string]$TestUrl,

    [string]$SaveBodyPath = "",

    # Always save log file in the same folder as the script
    [string]$AnalysisFilePath = "$PSScriptRoot\HttpAnalysis.txt"
)

Write-Host "Testing URL: $TestUrl" -ForegroundColor Cyan
$startTime = Get-Date

function Get-ErrorResponse {
    param($err)
    $ex = $err
    if ($err -is [System.Management.Automation.ErrorRecord]) {
        $ex = $err.Exception
    }
    if ($ex -is [System.Net.WebException] -and $ex.Response) {
        $resp = $ex.Response
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $content = $reader.ReadToEnd()
        $reader.Close()
        return [PSCustomObject]@{
            StatusCode = [int]$resp.StatusCode
            Headers    = $resp.Headers
            Content    = $content
        }
    }
    return $null
}

function Get-RawHttpResponse {
    param([string]$url)
    try {
        $uri = [System.Uri]$url
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $port = $uri.Port
        if (-not $port) {
            if ($uri.Scheme -eq "https") { $port = 443 } else { $port = 80 }
        }
        $tcpClient.Connect($uri.Host, $port)
        $stream = $tcpClient.GetStream()
        if ($uri.Scheme -eq "https") {
            $sslStream = New-Object System.Net.Security.SslStream($stream, $false, ({ $true } -as [System.Net.Security.RemoteCertificateValidationCallback]))
            $sslStream.AuthenticateAsClient($uri.Host)
            $stream = $sslStream
        }
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.NewLine = "`r`n"
        $writer.WriteLine("GET $($uri.PathAndQuery) HTTP/1.1")
        $writer.WriteLine("Host: $($uri.Host)")
        $writer.WriteLine("User-Agent: RawHeaderCapture/1.0")
        $writer.WriteLine("Connection: close")
        $writer.WriteLine("")
        $writer.Flush()
        $reader = New-Object System.IO.StreamReader($stream)
        $rawResponse = $reader.ReadToEnd()
        $reader.Close()
        $writer.Close()
        $tcpClient.Close()
        return $rawResponse
    }
    catch {
        return "ERROR capturing raw HTTP response: $($_.Exception.Message)"
    }
}

function Detect-ServerType {
    param([string]$serverHeader)
    if ($serverHeader -match "(?i)varnish") {
        Write-Host "Varnish Cache Detected" -ForegroundColor Yellow
    }
    elseif ($serverHeader -match "(?i)apache") {
        Write-Host "Apache Server Detected" -ForegroundColor Yellow
    }
    elseif ($serverHeader -match "(?i)nginx") {
        Write-Host "Nginx Server Detected" -ForegroundColor Yellow
    }
    else {
        Write-Host ("Server Detected: {0}" -f $serverHeader) -ForegroundColor Yellow
    }
}

# --- STEP 1: RAW CAPTURE FIRST ---
Write-Host "`nCapturing raw HTTP response..." -ForegroundColor Cyan
$rawData = Get-RawHttpResponse -url $TestUrl
if (-not $rawData) { $rawData = "ERROR: No raw HTTP data captured." }

try {
    Set-Content -Path $AnalysisFilePath -Value $rawData -Encoding ASCII
    Write-Host "Raw HTTP response saved to: $AnalysisFilePath" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not write to $AnalysisFilePath - $($_.Exception.Message)" -ForegroundColor Red
}

# Detect server from raw headers
if ($rawData -match "(?im)^Server:\s*(.+)$") {
    $rawServer = $matches[1].Trim()
    Write-Host "`n--- Raw Header Server Detection ---" -ForegroundColor Cyan
    Detect-ServerType -serverHeader $rawServer
} else {
    Write-Host "`nNo Server header found in raw HTTP response." -ForegroundColor Red
}

# --- STEP 2: PARSED REQUEST ---
try {
    $response = $null
    try {
        $response = Invoke-WebRequest -Uri $TestUrl -Method GET -MaximumRedirection 0 -TimeoutSec 90 -ErrorAction Stop
    }
    catch {
        $response = Get-ErrorResponse -err $_
    }

    $elapsed = (Get-Date) - $startTime
    if (-not $response) {
        Write-Host ("No response object returned. Time: {0:N2} seconds" -f $elapsed.TotalSeconds) -ForegroundColor Red
        return
    }

    if ($response.StatusCode) {
        Write-Host "HTTP Status Code: $($response.StatusCode)" -ForegroundColor Yellow
    } else {
        Write-Host "HTTP Status Code: (Unavailable)" -ForegroundColor Yellow
    }
    Write-Host ("Response Time: {0:N2} seconds" -f $elapsed.TotalSeconds) -ForegroundColor Yellow

    Write-Host "`n--- Response Headers ---" -ForegroundColor Cyan
    $serverHeader = $null
    if ($response.Headers -and $response.Headers.Count -gt 0) {
        foreach ($header in $response.Headers.GetEnumerator()) {
            Write-Host "$($header.Key): $($header.Value)"
            if ($header.Key -ieq "Server") { $serverHeader = $header.Value }
        }
    } else {
        Write-Host "WARNING: No headers returned by server." -ForegroundColor Red
    }

    if ($serverHeader) {
        Detect-ServerType -serverHeader $serverHeader
    } else {
        Write-Host "No Server header detected" -ForegroundColor Red
    }

    if ($SaveBodyPath) {
        $response.Content | Out-File -FilePath $SaveBodyPath -Encoding UTF8
        Write-Host "`nFull response body saved to: $SaveBodyPath" -ForegroundColor Green
    }

    Write-Host "`n--- First 40 lines of Response Body ---" -ForegroundColor Cyan
    if ($response.Content -and $response.Content.Trim().Length -gt 0) {
        $bodyLines = $response.Content -split "`n"
        $bodyLines[0..([Math]::Min(39, $bodyLines.Count - 1))] | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "WARNING: No body content returned by server." -ForegroundColor Red
    }

    Write-Host "`n--- Analysis ---" -ForegroundColor Cyan
    if ($response.Content -and $response.Content -match "(?i)<html") {
        Write-Host "HTML detected in response body." -ForegroundColor Yellow
    }
    elseif ($response.Content -and $response.Content -match "(?i)<\?xml") {
        Write-Host "XML declaration found -- response may be a valid XML document." -ForegroundColor Green
    }
    elseif ($response.Content -and $response.Content.Trim().Length -gt 0) {
        Write-Host "Non-empty body detected but not HTML or XML." -ForegroundColor Yellow
    }
    else {
        Write-Host "No content detected in body." -ForegroundColor Red
    }

    Write-Host "`nAnalysis complete." -ForegroundColor Cyan
}
catch {
    $elapsed = (Get-Date) - $startTime
    Write-Host ("ERROR: {0} (after {1:N2} seconds)" -f $_.Exception.Message, $elapsed.TotalSeconds) -ForegroundColor Red
}
