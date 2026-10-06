<#
.SYNOPSIS
    Imports a CSV of employee names and positions and updates their Title in On-Premises Exchange.

.DESCRIPTION
    - Designed to run inside the Exchange Management Shell (EMS).
    - Cleans medical suffixes (MD, DO, DDS, etc.) out of the last name field.
    - Features an interactive '-ManualRun' mode to learn name variations and resolve duplicates.
#>
param(
    [Parameter(Mandatory = $false)]
    [switch]$GoForImport,

    [Parameter(Mandatory = $false)]
    [switch]$ManualRun
)

# --- CONFIGURATION ---
$csvPath = "C:\ScriptsandHealthChecker\Employee List.csv"
$mapPath = "C:\ScriptsandHealthChecker\NicknameMap.txt"

# Suffixes to strip out from the last name field
$suffixesToRemove = '\b(MD|DO|DDS|PHD|PA|NP|JR|SR|IV|III|II)\b'
# ---------------------

if (-not (Test-Path $csvPath)) {
    Write-Error "CSV file not found at $csvPath"
    return
}

# Initialize/Load the automatic nickname mapping table from file
$nicknameMap = @{}
if (Test-Path $mapPath) {
    Get-Content $mapPath | ForEach-Object {
        if ($_ -match '^(?<CsvName>[^=]+)=(?<AdName>.+)$') {
            $nicknameMap[$Matches['CsvName'].Trim().ToUpper()] = $Matches['AdName'].Trim().ToUpper()
        }
    }
}

if ($GoForImport) { Write-Host ">>> LIVE MODE: Changes will be written to Exchange. <<<" -ForegroundColor Cyan } 
else { Write-Host ">>> DRY-RUN MODE: Displaying commands only. Use '-GoForImport' to execute. <<<" -ForegroundColor Yellow }

if ($ManualRun) { Write-Host ">>> MANUAL MODE: Interactive prompt enabled for missing/duplicate users. <<<" -ForegroundColor Magenta }

$employees = Import-Csv -Path $csvPath

foreach ($emp in $employees) {
    try {
        # Extract first and last name from "LASTNAME, FIRSTNAME" format
        if ($emp.Employee_Name -match '^\s*"?(?<Last>[^,]+),\s*(?<First>.+?)"?\s*$') {
            $rawLastName = $Matches['Last'].Trim()
            
            # Strip out known medical or generational suffixes from the last name field
            $lastName = ($rawLastName -replace $suffixesToRemove, '').Trim()
            
            # Grab just the very first word of the first name to strip out middle names/initials
            $firstName = ($Matches['First'].Trim() -split ' ')[0]
            $displayName = "$firstName $lastName"
        }
        else {
            Write-Warning "Name format not recognized: $($emp.Employee_Name)"
            continue
        }

        $user = $null
        $csvLookupKey = $firstName.ToUpper()

        # 1. Primary Check: Direct Match with clean names (Forced Array)
        $results = @(Get-User -Filter "LastName -eq '$lastName' -and FirstName -like '$firstName*'" -ErrorAction SilentlyContinue)

        # 2. Secondary Check: Check the pre-learned mapping file
        if ($results.Count -eq 0 -and $nicknameMap.ContainsKey($csvLookupKey)) {
            $mappedFirstName = $nicknameMap[$csvLookupKey]
            $results = @(Get-User -Filter "LastName -eq '$lastName' -and FirstName -like '$mappedFirstName*'" -ErrorAction SilentlyContinue)
        }

        # 3. Tertiary Check: Interactive Manual Resolution (LastName Search)
        if ($results.Count -eq 0 -and $ManualRun) {
            Write-Host "No direct match for $displayName. Searching alternative first names by LastName ($lastName)..." -ForegroundColor DarkGray
            $candidates = Get-User -Filter "LastName -eq '$lastName'" -ErrorAction SilentlyContinue
            
            foreach ($candidate in $candidates) {
                $response = Read-Host "Is CSV entry '$($emp.Employee_Name)' the same person as Exchange user '$($candidate.DisplayName)'? (Y/N)"
                if ($response.Trim().ToUpper() -eq 'Y') {
                    $user = $candidate
                    
                    # Learn the variation and append it to our mapping table file for next time
                    $candidateFirstName = $candidate.FirstName
                    if (-not $nicknameMap.ContainsKey($csvLookupKey)) {
                        $nicknameMap[$csvLookupKey] = $candidateFirstName.ToUpper()
                        "$csvLookupKey=$($candidateFirstName.ToUpper())" | Out-File -FilePath $mapPath -Append -Encoding utf8
                        Write-Host "Saved mapping: $csvLookupKey -> $($candidateFirstName.ToUpper()) to $mapPath" -ForegroundColor Cyan
                    }
                    break
                }
            }
        }
        elseif ($results.Count -eq 1) {
            $user = $results[0]
        }
        # 4. Interactive Duplicate Resolution
        elseif ($results.Count -gt 1) {
            if ($ManualRun) {
                Write-Host "Multiple matches found for '$displayName' ($($results.Count) accounts)." -ForegroundColor Yellow
                foreach ($candidate in $results) {
                    $response = Read-Host "Is CSV entry '$($emp.Employee_Name)' the same person as Exchange user '$($candidate.DisplayName)' ($($candidate.UserPrincipalName))? (Y/N)"
                    if ($response.Trim().ToUpper() -eq 'Y') {
                        $user = $candidate
                        break
                    }
                }
            } else {
                Write-Warning "Multiple matches found for '$displayName' ($($results.Count) accounts). Skipping to prevent incorrect updates."
                continue
            }
        }

        # Fallback if all lookups and interaction fail to find a user
        if ($null -eq $user) {
            Write-Warning "No Exchange user found for CSV entry: $($emp.Employee_Name)"
            continue
        }

        # Execution or preview phase using explicit SamAccountName string binding
        if (-not $GoForImport) {
            if ($user.Title -eq $emp.Position) {
                Write-Host "[NO CHANGE] $($user.SamAccountName) already has title '$($user.Title)'" -ForegroundColor DarkGray
            } else {
                Write-Host "[CHANGE REVEALED] Will overwrite '$($user.Title)' with '$($emp.Position)' for $($user.SamAccountName)" -ForegroundColor Yellow
                Write-Host "  -> Command: Set-User -Identity '$($user.SamAccountName)' -Title '$($emp.Position)'" -ForegroundColor Gray
            }
        }
        else {
            Set-User -Identity $user.SamAccountName -Title $emp.Position -ErrorAction Stop
            Write-Host "[SUCCESS] Updated $($user.SamAccountName) ($displayName) title to '$($emp.Position)'" -ForegroundColor Green
        }

    }
    catch {
        Write-Error "Error processing $($emp.Employee_Name): $_"
    }
}
