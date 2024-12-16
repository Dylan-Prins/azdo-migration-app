<#
.SYNOPSIS
    Kopieert project wiki's van een Azure DevOps project naar een ander project.

.DESCRIPTION
    Kopieert zowel code-based als project wiki's van het bronproject naar het doelproject.
    Bestaande wiki's worden bijgewerkt met de laatste wijzigingen.

.PARAMETER SourceOrganizationUrl
    De URL van de bron Azure DevOps organisatie.

.PARAMETER DestinationOrganizationUrl
    De URL van de doel Azure DevOps organisatie.

.PARAMETER SourceProject
    De naam van het bronproject.

.PARAMETER DestinationProject
    De naam van het doelproject.

.EXAMPLE
    Copy-AzDoWiki -SourceOrganizationUrl "https://dev.azure.com/source-org" `
                  -DestinationOrganizationUrl "https://dev.azure.com/dest-org" `
                  -SourceProject "Project-A" `
                  -DestinationProject "Project-B"
#>
function Copy-AzDoWiki {
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

    # Haal alle wiki's op van het bronproject
    $sourceParams = @{
        CollectionUri = $SourceOrganizationUrl
        Project = $SourceProject
    }
    $sourceWikis = Invoke-ThrottledOperation -Operation { Get-AzDoWiki @sourceParams } -OperationType 'rest'

    foreach ($wiki in $sourceWikis) {
        Write-MigrationLog -Project $DestinationProject -Message "Bezig met kopiëren van wiki: $($wiki.name)"

        # Maak een tijdelijke directory
        $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TMPDIR "wiki-migration-$(Get-Date -Format 'yyyyMMddHHmmss')")
        $wikiPath = Join-Path $tempDir $wiki.name

        try {
            # Check of het een project wiki of code wiki is
            if ($wiki.type -eq "projectWiki") {
                # Project wiki
                $destWikiParams = @{
                    CollectionUri = $DestinationOrganizationUrl
                    Project = $DestinationProject
                    Name = $wiki.name
                    Type = "projectWiki"
                }

                try {
                    $destWiki = Invoke-ThrottledOperation -Operation { Get-AzDoWiki @destWikiParams } -OperationType 'rest'
                }
                catch {
                    Write-MigrationLog -Project $DestinationProject -Message "Project wiki bestaat nog niet, wordt aangemaakt..."
                    $destWiki = Invoke-ThrottledOperation -Operation { New-AzDoWiki @destWikiParams } -OperationType 'rest'
                }

                # Clone en update wiki
                Invoke-ThrottledOperation -Operation { git clone $wiki.remoteUrl $wikiPath } -OperationType 'git'
                Set-Location $wikiPath
                git remote add target $destWiki.remoteUrl
                Invoke-ThrottledOperation -Operation { git push --mirror target } -OperationType 'git'
            }
            else {
                # Code wiki - koppel aan gemigreerde repository
                $repoName = $wiki.repositoryId
                $destWikiParams = @{
                    CollectionUri = $DestinationOrganizationUrl
                    Project = $DestinationProject
                    Name = $wiki.name
                    Type = "codeWiki"
                    RepositoryId = $repoName
                    Path = $wiki.path
                }

                try {
                    $destWiki = Get-AzDoWiki @destWikiParams
                }
                catch {
                    Write-MigrationLog -Project $DestinationProject -Message "Code wiki bestaat nog niet, wordt aangemaakt..."
                    $destWiki = New-AzDoWiki @destWikiParams
                }
            }

            Write-MigrationLog -Project $DestinationProject -Message "Wiki $($wiki.name) succesvol gekopieerd"
        }
        finally {
            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force
            }
        }
    }
}