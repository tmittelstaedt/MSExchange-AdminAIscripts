param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile,   # Path to the input file

    [Parameter(Mandatory = $true)]
    [string]$OutputFile   # Path to the output file
)

try {
    # Validate input file exists
    if (-not (Test-Path $InputFile)) {
        throw "Input file '$InputFile' does not exist."
    }

    # Read all lines from the file
    $lines = Get-Content -Path $InputFile -ErrorAction Stop

    # Determine total number of parts (25 lines per part)
    $totalParts = [math]::Ceiling($lines.Count / 25)

    # Prepare output file (clear if exists)
    if (Test-Path $OutputFile) {
        Clear-Content -Path $OutputFile
    }

    # Process in chunks of 25 lines
    for ($i = 0; $i -lt $totalParts; $i++) {
        $partNumber = $i + 1
        $startIndex = $i * 25
        $chunk = $lines[$startIndex..([math]::Min($startIndex + 24, $lines.Count - 1))]

        # Write header
        Add-Content -Path $OutputFile -Value "===part $partNumber of $totalParts==="

        # Write chunk
        $chunk | Add-Content -Path $OutputFile

        # Write footer
        Add-Content -Path $OutputFile -Value "===end of part $partNumber of $totalParts==="
        Add-Content -Path $OutputFile -Value ""  # Blank line for readability
    }

    Write-Host "File successfully split into $totalParts parts and saved to '$OutputFile'."
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
