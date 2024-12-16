<#
.SYNOPSIS
    Schrijft een geformatteerd logbericht voor de migratie.

.DESCRIPTION
    Schrijft een logbericht met timestamp en project context naar de console en/of een logbestand.

.PARAMETER Project
    De naam van het project of context waarvoor het bericht wordt gelogd.

.PARAMETER Message
    Het bericht dat gelogd moet worden.

.PARAMETER LogPath
    Optioneel pad waar logbestanden worden opgeslagen. Als niet opgegeven, wordt alleen naar console gelogd.

.EXAMPLE
    Write-MigrationLog -Project "Project-A" -Message "Start migratie"
    Write-MigrationLog -Project "Project-A" -Message "Start migratie" -LogPath "./logs"
#>
function Write-MigrationLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp][$Project] $Message"

    # Altijd naar console schrijven
    Write-Host $logMessage

    # Als LogPath is opgegeven, ook naar bestand schrijven
    if ($LogPath) {
        # Maak logdirectory als deze niet bestaat
        if (-not (Test-Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath | Out-Null
        }

        # Gebruik één logbestand per script run
        $dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $logFile = Join-Path $LogPath "migration_$dateStamp.log"

        # Schrijf naar logbestand (thread-safe)
        $mutex = New-Object System.Threading.Mutex($false, "MigrationLogMutex")
        $mutex.WaitOne() | Out-Null
        try {
            $logMessage | Out-File -FilePath $logFile -Append
        }
        finally {
            $mutex.ReleaseMutex()
        }
    }
}