<#
.SYNOPSIS
    Kopieert Azure Artifacts feeds van een Azure DevOps project naar een ander project.

.DESCRIPTION
    Kopieert alle feeds en packages van het bronproject naar het doelproject.
    Ondersteunt NuGet, npm, Maven en Python packages.
    Gebruikt dezelfde authenticatie als de AzureDevOpsPowerShell module.

.PARAMETER SourceOrganizationUrl
    De URL van de bron Azure DevOps organisatie.

.PARAMETER DestinationOrganizationUrl
    De URL van de doel Azure DevOps organisatie.

.PARAMETER SourceProject
    De naam van het bronproject.

.PARAMETER DestinationProject
    De naam van het doelproject.

.EXAMPLE
    Copy-AzDoArtifacts -SourceOrganizationUrl "https://dev.azure.com/source-org" `
                       -DestinationOrganizationUrl "https://dev.azure.com/dest-org" `
                       -SourceProject "Project-A" `
                       -DestinationProject "Project-B"
#>
function Copy-AzDoArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceOrganizationUrl,

        [Parameter(Mandatory = $true)]
        [string]$DestinationOrganizationUrl,

        [Parameter(Mandatory = $true)]
        [string]$SourceProject,

        [Parameter(Mandatory = $true)]
        [string]$DestinationProject
    )

    Write-MigrationLog -Project $DestinationProject -Message "Start migratie van Azure Artifacts feeds"

    # Haal access token op
    $token = Get-AzAccessToken -CollectionUri $SourceOrganizationUrl

    # Stel headers in met token
    $headers = @{
        Authorization = "Bearer $token"
        'Content-Type' = 'application/json'
    }

    # Haal alle feeds op van het bronproject via REST API
    $sourceFeeds = Invoke-ThrottledOperation -Operation {
        $uri = "$SourceOrganizationUrl/$SourceProject/_apis/packaging/feeds?api-version=6.0-preview.1"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        return $response.value
    } -OperationType 'rest'

    foreach ($feed in $sourceFeeds) {
        Write-MigrationLog -Project $DestinationProject -Message "Migreren van feed: $($feed.name)"

        # Check of feed al bestaat
        $existingFeed = Invoke-ThrottledOperation -Operation {
            try {
                $uri = "$DestinationOrganizationUrl/$DestinationProject/_apis/packaging/feeds/$($feed.name)?api-version=6.0-preview.1"
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
                return $response
            }
            catch {
                if ($_.Exception.Response.StatusCode -eq 404) { return $null }
                throw
            }
        } -OperationType 'rest'

        if ($existingFeed) {
            Write-MigrationLog -Project $DestinationProject -Message "Feed $($feed.name) bestaat al, wordt overgeslagen"
            continue
        }

        # Maak feed in doelproject
        $destFeed = Invoke-ThrottledOperation -Operation {
            $uri = "$DestinationOrganizationUrl/$DestinationProject/_apis/packaging/feeds?api-version=6.0-preview.1"
            $body = @{
                name = $feed.name
                description = $feed.description
                upstreamSources = $feed.upstreamSources
            } | ConvertTo-Json

            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body
            return $response
        } -OperationType 'rest'

        # Haal alle packages op van de source feed
        $packages = Invoke-ThrottledOperation -Operation {
            $uri = "$SourceOrganizationUrl/$SourceProject/_apis/packaging/feeds/$($feed.name)/packages?api-version=6.0-preview.1"
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
            return $response.value
        } -OperationType 'rest'

        # Kopieer elk package
        foreach ($package in $packages) {
            Write-MigrationLog -Project $DestinationProject -Message "Migreren van package: $($package.name)"

            # Haal alle versies op
            $versions = Invoke-ThrottledOperation -Operation {
                $uri = "$SourceOrganizationUrl/$SourceProject/_apis/packaging/feeds/$($feed.name)/packages/$($package.id)/versions?api-version=6.0-preview.1"
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
                return $response.value
            } -OperationType 'rest'

            foreach ($version in $versions) {
                # Download package
                $tempFile = Join-Path $env:TEMP "$($package.name)-$($version.version).$($package.protocolType.toLowerCase())"

                Invoke-ThrottledOperation -Operation {
                    $uri = "$SourceOrganizationUrl/$SourceProject/_apis/packaging/feeds/$($feed.name)/packages/$($package.id)/versions/$($version.id)/content?api-version=6.0-preview.1"
                    Invoke-WebRequest -Uri $uri -Headers $headers -OutFile $tempFile
                } -OperationType 'rest'

                # Upload package naar doel
                Invoke-ThrottledOperation -Operation {
                    $uri = "$DestinationOrganizationUrl/$DestinationProject/_apis/packaging/feeds/$($destFeed.name)/packages/$($package.protocolType.toLowerCase())?api-version=6.0-preview.1"
                    Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -InFile $tempFile
                } -OperationType 'rest'

                Remove-Item $tempFile -Force
            }
        }
    }

    Write-MigrationLog -Project $DestinationProject -Message "Azure Artifacts feeds succesvol gemigreerd"
}