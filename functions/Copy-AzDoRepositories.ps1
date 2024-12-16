<#
.SYNOPSIS
    Kopieert repositories van een Azure DevOps project naar een ander project.

.DESCRIPTION
    Maakt een mirror clone van alle opgegeven repositories en kopieert deze
    naar het doelproject. Alle branches, tags en geschiedenis worden meegenomen.

.PARAMETER SourceOrganizationUrl
    De URL van de bron Azure DevOps organisatie.

.PARAMETER DestinationOrganizationUrl
    De URL van de doel Azure DevOps organisatie.

.PARAMETER SourceProject
    De naam van het bronproject.

.PARAMETER DestinationProject
    De naam van het doelproject.

.PARAMETER RepositoryNames
    Optionele array met namen van specifieke repositories die gemigreerd moeten worden.
    Als dit leeg is worden alle repositories gemigreerd.

.PARAMETER IncludeTags
    Of git tags meegenomen moeten worden in de migratie.

.PARAMETER IncludeWiki
    Of project en code wiki's meegenomen moeten worden.

.EXAMPLE
    Copy-AzDoRepositories -SourceOrganizationUrl "https://dev.azure.com/source-org" `
                         -DestinationOrganizationUrl "https://dev.azure.com/dest-org" `
                         -SourceProject "Project-A" `
                         -DestinationProject "Project-B" `
                         -RepositoryNames @("repo1", "repo2") `
                         -IncludeTags $true `
                         -IncludeWiki $true
#>
function Copy-AzDoRepositories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceOrganizationUrl,

        [Parameter(Mandatory = $true)]
        [string]$DestinationOrganizationUrl,

        [Parameter(Mandatory = $true)]
        [string]$SourceProject,

        [Parameter(Mandatory = $true)]
        [string]$DestinationProject,

        [Parameter(Mandatory = $false)]
        [string[]]$RepositoryNames,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeTags = $false,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeWiki = $false
    )

    # Maak een tijdelijke directory voor klonen
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TMPDIR "repo-migration-$(Get-Date -Format 'yyyyMMddHHmmss')")

    try {
        # Haal alle repositories op
        $repoParams = @{
            CollectionUri = $SourceOrganizationUrl
            Project = $SourceProject
        }
        $sourceRepos = Invoke-ThrottledOperation -Operation { Get-AzDoRepository @repoParams } -OperationType 'rest'

        # Filter repositories indien nodig
        if ($RepositoryNames.Count -gt 0) {
            $sourceRepos = $sourceRepos | Where-Object { $_.name -in $RepositoryNames }
        }

        foreach ($repo in $sourceRepos) {
            Update-AzDoRepository -SourceOrganizationUrl $SourceOrganizationUrl `
                                -DestinationOrganizationUrl $DestinationOrganizationUrl `
                                -SourceProject $SourceProject `
                                -DestinationProject $DestinationProject `
                                -RepositoryName $repo.name `
                                -IncludeTags $IncludeTags
        }

        # Kopieer project wiki's indien gewenst
        if ($IncludeWiki) {
            Copy-AzDoWiki -SourceOrganizationUrl $SourceOrganizationUrl `
                         -DestinationOrganizationUrl $DestinationOrganizationUrl `
                         -SourceProject $SourceProject `
                         -DestinationProject $DestinationProject
        }
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }
}