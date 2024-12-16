<#
.SYNOPSIS
    Voert een operatie uit met respect voor Azure DevOps API-limieten.

.DESCRIPTION
    Implementeert rate limiting en exponential backoff voor Azure DevOps API calls.
    Houdt bij hoeveel requests er zijn gedaan en wacht indien nodig.

.PARAMETER Operation
    De uit te voeren scriptblock.

.PARAMETER OperationType
    Het type operatie ('git' of 'rest').

.EXAMPLE
    Invoke-ThrottledOperation -Operation { Get-AzDoRepository @params } -OperationType 'rest'
#>
function Invoke-ThrottledOperation {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateSet('git', 'rest')]
        [string]$OperationType
    )

    # Statische variabelen voor rate limiting
    if (-not $script:requestCounts) {
        $script:requestCounts = @{
            git = @{
                count = 0
                lastReset = [DateTime]::Now
            }
            rest = @{
                count = 0
                lastReset = [DateTime]::Now
            }
        }
    }

    # Reset counters als nodig
    $now = [DateTime]::Now
    foreach ($type in @('git', 'rest')) {
        if (($now - $script:requestCounts[$type].lastReset).TotalMinutes -ge 1) {
            $script:requestCounts[$type].count = 0
            $script:requestCounts[$type].lastReset = $now
        }
    }

    # Check limieten
    $maxRequests = @{
        git = 200  # per minuut
        rest = 250 # per minuut (conservatieve schatting)
    }

    # Wacht als we de limiet naderen
    if ($script:requestCounts[$OperationType].count -ge $maxRequests[$OperationType]) {
        $waitSeconds = 60 - ($now - $script:requestCounts[$OperationType].lastReset).TotalSeconds
        if ($waitSeconds -gt 0) {
            Write-MigrationLog -Project "RateLimit" -Message "API limiet bereikt voor $OperationType, wacht $([math]::Ceiling($waitSeconds)) seconden"
            Start-Sleep -Seconds ([math]::Ceiling($waitSeconds))
            $script:requestCounts[$OperationType].count = 0
            $script:requestCounts[$OperationType].lastReset = [DateTime]::Now
        }
    }

    # Exponential backoff bij fouten
    $maxAttempts = 5
    $attempt = 1
    $delay = 1

    while ($true) {
        try {
            $script:requestCounts[$OperationType].count++
            return & $Operation
        }
        catch {
            if ($_.Exception.Message -match "429|TooManyRequests") {
                if ($attempt -ge $maxAttempts) {
                    throw "Maximum aantal pogingen bereikt na rate limiting: $_"
                }

                $waitSeconds = [math]::Pow(2, $attempt) * $delay
                Write-MigrationLog -Project "RateLimit" -Message "Rate limit hit, wacht $waitSeconds seconden (poging $attempt/$maxAttempts)"
                Start-Sleep -Seconds $waitSeconds
                $attempt++
                continue
            }
            throw
        }
    }
}