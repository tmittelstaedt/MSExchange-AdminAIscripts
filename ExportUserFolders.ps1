<#
.SYNOPSIS
    Generates a New-MailboxExportRequest command for all user-created and archive folders in a mailbox,
    excluding system folders that may be misclassified, and creates a second file to remove completed export jobs.

.DESCRIPTION
    This script runs in the Exchange Management Shell and:
    - Accepts a mailbox name, output file path, and optional PST export UNC path.
    - Retrieves only folders with FolderType = "User Created" or "Archive".
    - Excludes known system folders and other unwanted folders.
    - Removes leading "/" from folder paths.
    - Quotes ALL folder names with double quotes.
    - Outputs a single-line New-MailboxExportRequest command to a file.
    - Creates a second file with a Remove-MailboxExportRequest command that only removes completed jobs.

.PARAMETER Mailbox
    The mailbox identity (alias, SMTP address, or display name).

.PARAMETER OutputFile
    The file path where the generated command will be saved.

.PARAMETER ExportPath
    The UNC path for the PST export. If not supplied, defaults to \\exchange.coda.com\pst\<MailboxName>.pst

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
    [ValidateNotNullOrEmpty()]
    [string]$Mailbox,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath
)

try {
    # If no ExportPath is provided, build the default UNC path
    if (-not $ExportPath) {
        $ExportPath = "\\exchange.coda.com\pst\$Mailbox.pst"
    }

    # Known system folders and unwanted folders to exclude
    $excludeFolders = @(
        "Outbox",
        "Outbox/VoiceOutbox",
        "Sync Issues",
        "Sync Issues/Conflicts",
        "Sync Issues/Local Failures",
        "Sync Issues/Server Failures",
        "Conversation History",
        "Junk Email",
        "RSS Feeds",
        "News Feed",
        "Quick Step Settings"
    )

    # Get only user-created or archive folders, excluding known system folders
    $userFolders = Get-MailboxFolderStatistics -Identity $Mailbox -ErrorAction Stop |
        Where-Object {
            $_.FolderType -in @("User Created", "Archive") -and
            -not ($excludeFolders -contains $_.FolderPath.TrimStart("/"))
        } |
        Select-Object -ExpandProperty FolderPath

    if (-not $userFolders) {
        Write-Host "No user-created or archive folders found for mailbox '$Mailbox'." -ForegroundColor Yellow
        exit 0
    }

    # Remove leading "/" and wrap ALL folder names in double quotes
    $quotedFolders = $userFolders | ForEach-Object {
        '"' + $_.TrimStart("/") + '"'
    }

    # Build the New-MailboxExportRequest command as a single string
    $command = 'New-MailboxExportRequest -Mailbox "{0}" -IncludeFolders {1} -FilePath "{2}"' -f $Mailbox, ($quotedFolders -join ","), $ExportPath

    # Save EXACTLY the same string to the main output file
    Set-Content -Path $OutputFile -Value $command -Encoding UTF8

    # Build the remove command (only completed jobs)
    $removeCommand = 'Get-MailboxExportRequest -Mailbox "{0}" | Where-Object {{$_.Status -eq "Completed"}} | Remove-MailboxExportRequest' -f $Mailbox

    # Create the second output file name (insert "Remove" before extension)
    $removeFile = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($OutputFile),
        ([System.IO.Path]::GetFileNameWithoutExtension($OutputFile) + "Remove" + [System.IO.Path]::GetExtension($OutputFile))
    )

    # Save the remove command to the second file
    Set-Content -Path $removeFile -Value $removeCommand -Encoding UTF8

    # Output to screen
    Write-Host "Export command saved to $OutputFile" -ForegroundColor Green
    Write-Host "Remove command saved to $removeFile" -ForegroundColor Green
    Write-Host "`nExport Command:" -ForegroundColor Cyan
    Write-Host $command
    Write-Host "`nRemove Command:" -ForegroundColor Cyan
    Write-Host $removeCommand
}
catch {
    Write-Error "Error: $_"
    exit 1
}
