<#
.SYNOPSIS
    Bepaalt het optimale aantal parallelle jobs voor de migratie.

.DESCRIPTION
    Berekent het aantal parallelle jobs gebaseerd op systeemcapaciteit en configuratie.
    Detecteert het platform en bepaalt het aantal beschikbare CPU cores.

.PARAMETER MaxJobs
    Het maximaal toegestane aantal parallelle jobs. Als 0, wordt automatisch bepaald.

.PARAMETER MigrationCount
    Het aantal migraties dat uitgevoerd moet worden.

.EXAMPLE
    Get-ParallelJobCount -MaxJobs 0 -MigrationCount 5
#>
function Get-ParallelJobCount {
    param(
        [Parameter(Mandatory = $true)]
        [int]$MaxJobs,

        [Parameter(Mandatory = $true)]
        [int]$MigrationCount
    )

    # Bepaal aantal CPU cores op een platform-onafhankelijke manier
    if ($MaxJobs -le 0) {
        if ($IsWindows) {
            $MaxJobs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        }
        elseif ($IsMacOS) {
            $MaxJobs = sysctl -n hw.logicalcpu
        }
        elseif ($IsLinux) {
            $MaxJobs = nproc
        }
        else {
            # Fallback naar een veilige waarde
            $MaxJobs = 4
        }
    }

    # Limiteer op basis van aantal migraties
    return [Math]::Min($MaxJobs, $MigrationCount)
}