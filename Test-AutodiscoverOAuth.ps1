param (
    [Parameter(Mandatory = $true)]
    [string]$ClientId
)

# Step 1: Ask for email address
$EmailAddress = Read-Host "Enter the full email address (e.g., user@contoso.com)"

# Validate email format
if ($EmailAddress -notmatch '^[^@]+@[^@]+\.[^@]+$') {
    Write-Host "Invalid email address format."
    exit 1
}

# Step 2: Parse domain from email
$Domain = $EmailAddress.Split("@")[1]
Write-Host "Parsed domain: $Domain"

# Step 3: Discover tenant ID from domain
try {
    $OidcConfigUrl = "https://login.microsoftonline.com/$Domain/.well-known/openid-configuration"
    $OidcConfig = Invoke-RestMethod -Uri $OidcConfigUrl -Method Get -ErrorAction Stop
    if ($OidcConfig.issuer -match "https://sts\.windows\.net/([0-9a-fA-F-]+)/") {
        $TenantId = $matches[1]
        Write-Host "Discovered Tenant ID: $TenantId"
    } else {
        Write-Host "Could not parse tenant ID from issuer."
        exit 1
    }
} catch {
    Write-Host "Error discovering tenant ID: $($_.Exception.Message)"
    exit 1
}

# Resource for Exchange Online
$Resource = "https://outlook.office365.com"

try {
    # Step 4: Request device code
    $DeviceCodeResponse = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/devicecode" `
        -Body @{
            resource  = $Resource
            client_id = $ClientId
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop

    Write-Host "To sign in, open this URL in a browser:"
    Write-Host $DeviceCodeResponse.verification_url
    Write-Host "Then enter the code: $($DeviceCodeResponse.user_code)"
    Write-Host "Waiting for you to complete sign-in..."

    # Step 5: Poll for token
    $Token = $null
    while (-not $Token) {
        Start-Sleep -Seconds $DeviceCodeResponse.interval
        try {
            $TokenResponse = Invoke-RestMethod -Method Post `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" `
                -Body @{
                    grant_type = "device_code"
                    client_id  = $ClientId
                    code       = $DeviceCodeResponse.device_code
                    resource   = $Resource
                } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
            $Token = $TokenResponse
        }
        catch {
            if ($_.ErrorDetails.Message -notmatch "authorization_pending") {
                throw
            }
        }
    }

    Write-Host "Login successful. Access token acquired."
    Write-Host "Token expires at: $($Token.expires_on)"

    # Step 6: Build Autodiscover URL (Exchange Online)
    $AutodiscoverUrl = "https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml"

    # Step 7: Build Autodiscover request body
    $AutodiscoverBody = @"
<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006">
  <Request>
    <EMailAddress>$EmailAddress</EMailAddress>
    <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a</AcceptableResponseSchema>
  </Request>
</Autodiscover>
"@

    Write-Host "Querying Exchange Online Autodiscover for $EmailAddress ..."

    # Step 8: Send Autodiscover request with Bearer token and get raw XML
    $Headers = @{
        "Authorization" = "Bearer $($Token.access_token)"
        "Content-Type"  = "text/xml"
    }

    # UseBasicParsing avoids the security prompt
    $RawResponse = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $AutodiscoverUrl -Headers $Headers -Body $AutodiscoverBody -ErrorAction Stop

    Write-Host "Raw Autodiscover XML Response:"
    Write-Output $RawResponse.Content

    # Step 9: Hybrid awareness check
    if ($RawResponse.Content -notmatch "<Protocol") {
        Write-Warning "No mailbox settings returned. This is expected if the mailbox is on-premises and Hybrid Modern Authentication is not yet enabled."
        Write-Warning "After hybridization, rerun this script to verify OAuth Autodiscover for mobile clients."
    }

} catch {
    Write-Host "Error: $($_.Exception.Message)"
}
