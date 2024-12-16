<#
.SYNOPSIS
    Maakt nieuwe service connections aan in een Azure DevOps project.

.DESCRIPTION
    Kopieert service connections van het bronproject naar het doelproject
    met behoud van de originele configuratie.

.PARAMETER SourceOrganizationUrl
    De URL van de bron Azure DevOps organisatie.

.PARAMETER DestinationOrganizationUrl
    De URL van de doel Azure DevOps organisatie.

.PARAMETER SourceProject
    De naam van het bronproject.

.PARAMETER DestinationProject
    De naam van het doelproject.

.PARAMETER ServiceConnections
    Array met namen van service connections die gemigreerd moeten worden.

.EXAMPLE
    New-AzDoServiceConnections -SourceOrganizationUrl "https://dev.azure.com/source-org" `
                              -DestinationOrganizationUrl "https://dev.azure.com/dest-org" `
                              -SourceProject "Project-A" `
                              -DestinationProject "Project-B" `
                              -ServiceConnections @("Azure-Prod", "Azure-Test")
#>
function New-AzDoServiceConnections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceOrganizationUrl,

        [Parameter(Mandatory = $true)]
        [string]$DestinationOrganizationUrl,

        [Parameter(Mandatory = $true)]
        [string]$SourceProject,

        [Parameter(Mandatory = $true)]
        [string]$DestinationProject,

        [Parameter(Mandatory = $true)]
        [array]$ServiceConnections
    )

    foreach ($sc in $ServiceConnections) {
        Write-MigrationLog -Project $DestinationProject -Message "Service connection ophalen: $($sc.name)"

        # Check of service connection al bestaat
        $destParams = @{
            CollectionUri = $DestinationOrganizationUrl
            Project = $DestinationProject
            Name = $sc.name
        }

        try {
            $existingConnection = Get-AzDoServiceEndpoint @destParams
            Write-MigrationLog -Project $DestinationProject -Message "Service Connection '$($sc.name)' bestaat al, wordt overgeslagen"
            continue
        }
        catch {
            if ($_.Exception.Response.StatusCode -ne 404) { throw }
        }

        # Haal de bestaande service connection op
        $sourceParams = @{
            CollectionUri = $SourceOrganizationUrl
            Project = $SourceProject
            Name = $sc.name
        }
        $sourceConnection = Invoke-ThrottledOperation -Operation { Get-AzDoServiceEndpoint @sourceParams } -OperationType 'rest'

        # Maak nieuwe service connection met dezelfde configuratie
        $endpointParams = @{
            CollectionUri = $DestinationOrganizationUrl
            Project = $DestinationProject
            EndpointObject = @{
                name = $sourceConnection.name
                type = $sourceConnection.type
                url = $sourceConnection.url
                description = $sourceConnection.description
                authorization = $sourceConnection.authorization
            }
        }

        Invoke-WithRetry { New-AzDoServiceEndpoint @endpointParams }
        Write-MigrationLog -Project $DestinationProject -Message "Service Connection '$($sc.name)' succesvol gemigreerd"
    }
}

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5
    )

    $attempt = 1
    while ($true) {
        try {
            return & $ScriptBlock
        }
        catch {
            if ($attempt -ge $MaxAttempts) { throw }
            Write-MigrationLog -Project $DestinationProject -Message "Poging $attempt/$MaxAttempts gefaald, nieuwe poging over $DelaySeconds seconden" -LogPath $logPath
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
    }
}