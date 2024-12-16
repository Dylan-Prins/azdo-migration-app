<#
.SYNOPSIS
    Werkt een bestaande repository bij met de laatste wijzigingen van de bron.

.DESCRIPTION
    Synchroniseert een bestaande repository in het doelproject met de bronrepository.
    Als de repository niet bestaat, wordt deze aangemaakt.

.PARAMETER SourceOrganizationUrl
    De URL van de bron Azure DevOps organisatie.

.PARAMETER DestinationOrganizationUrl
    De URL van de doel Azure DevOps organisatie.

.PARAMETER SourceProject
    De naam van het bronproject.

.PARAMETER DestinationProject
    De naam van het doelproject.

.PARAMETER RepositoryName
    De naam van de repository.

.PARAMETER IncludeTags
    Of git tags meegenomen moeten worden in de migratie.

.EXAMPLE
    Update-AzDoRepository -SourceOrganizationUrl "https://dev.azure.com/source-org" `
                         -DestinationOrganizationUrl "https://dev.azure.com/dest-org" `
                         -SourceProject "Project-A" `
                         -DestinationProject "Project-B" `
                         -RepositoryName "repo1"
#>
function Update-AzDoRepository {
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
        [string]$RepositoryName,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeTags = $false
    )

    # Controleer of de doelrepository bestaat
    $destParams = @{
        CollectionUri = $DestinationOrganizationUrl
        Project = $DestinationProject
        RepositoryId = $RepositoryName
    }

    try {
        $destRepo = Invoke-ThrottledOperation -Operation { Get-AzDoRepository @destParams } -OperationType 'rest'
    }
    catch {
        Write-MigrationLog -Project $DestinationProject -Message "Repository $RepositoryName bestaat nog niet, wordt aangemaakt..."
        $destRepo = Invoke-ThrottledOperation -Operation {
            New-AzDoRepository -CollectionUri $DestinationOrganizationUrl `
                              -Project $DestinationProject `
                              -RepositoryName $RepositoryName
        } -OperationType 'rest'
    }

    # Haal bronrepository op
    $sourceParams = @{
        CollectionUri = $SourceOrganizationUrl
        Project = $SourceProject
        RepositoryId = $RepositoryName
    }
    $sourceRepo = Get-AzDoRepository @sourceParams

    # Maak een tijdelijke directory
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TMPDIR "repo-update-$(Get-Date -Format 'yyyyMMddHHmmss')")
    $repoPath = Join-Path $tempDir $RepositoryName

    try {
        # Clone en update repository
        Write-MigrationLog -Project $DestinationProject -Message "Bezig met updaten van repository: $RepositoryName"

        # Clone source met alle refs
        $cloneArgs = @("-c", "core.compression=0", "clone", "--mirror")
        if (-not $IncludeTags) {
            $cloneArgs += "--no-tags"
        }
        $cloneArgs += $sourceRepo.remoteUrl, $repoPath
        Invoke-ThrottledOperation -Operation { & git @cloneArgs } -OperationType 'git'

        Set-Location $repoPath

        # Voeg destination toe als remote en push
        git remote add target $destRepo.remoteUrl
        $pushArgs = @("-c", "pack.threads=0", "push", "--mirror")
        if ($IncludeTags) {
            $pushArgs += "--tags"
        }
        $pushArgs += "target"
        & git @pushArgs

        Write-MigrationLog -Project $DestinationProject -Message "Repository $RepositoryName succesvol bijgewerkt"
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }
}