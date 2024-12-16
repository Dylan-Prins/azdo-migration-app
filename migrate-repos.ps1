# Parameters
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath = "data/repos-config.json",

    [Parameter(Mandatory = $false)]
    [int]$MaxParallelJobs = 0,

    [Parameter(Mandatory = $false)]
    [string]$LogPath
)

# Importeer alle functies
Get-ChildItem -Path "functions" -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}

# Controleer of module aanwezig is
if (-not (Get-Module -ListAvailable -Name AzureDevOpsPowerShell)) {
    Write-MigrationLog -Project "Setup" -Message "AzureDevOpsPowerShell module wordt geïnstalleerd..." -LogPath $LogPath
    Install-Module -Name AzureDevOpsPowerShell -Scope CurrentUser -Force
}
Import-Module AzureDevOpsPowerShell

# Lees de configuratie
$config = Get-Content $ConfigPath | ConvertFrom-Json

# Bepaal aantal parallelle jobs
$throttleLimit = Get-ParallelJobCount -MaxJobs $MaxParallelJobs -MigrationCount $config.migrations.Count
Write-MigrationLog -Project "Setup" -Message "Start migratie met $throttleLimit parallelle jobs" -LogPath $LogPath

# Voer migraties parallel uit
$totalMigrations = $config.migrations.Count
$completed = 0
$config.migrations | ForEach-Object -ThrottleLimit $throttleLimit -Parallel {
    try {
        # Importeer functies in de parallel scope
        Get-ChildItem -Path "functions" -Filter "*.ps1" | ForEach-Object {
            . $_.FullName
        }
        Import-Module AzureDevOpsPowerShell

        $migration = $_
        $config = $using:config
        $logPath = $using:LogPath
        $projectId = "$($migration.sourceProject) -> $($migration.destinationProject)"

        Write-MigrationLog -Project $projectId -Message "Start migratie" -LogPath $logPath

        # Migreer repositories
        $repoParams = @{
            SourceOrganizationUrl = "https://dev.azure.com/$($migration.sourceOrganization)"
            DestinationOrganizationUrl = "https://dev.azure.com/$($config.destinationOrganization)"
            SourceProject = $migration.sourceProject
            DestinationProject = $migration.destinationProject
            RepositoryNames = $migration.repositories
            IncludeTags = $migration.includeTags
            IncludeWiki = $migration.includeWiki
        }
        Copy-AzDoRepositories @repoParams

        # Migreer artifacts indien gewenst
        if ($migration.includeArtifacts) {
            Copy-AzDoArtifacts -SourceOrganizationUrl $migration.sourceOrganization `
                               -DestinationOrganizationUrl $config.destinationOrganization `
                               -SourceProject $migration.sourceProject `
                               -DestinationProject $migration.destinationProject
        }

        # Migreer service connections indien aanwezig
        if ($migration.PSObject.Properties.Name -contains "serviceConnections") {
            Write-MigrationLog -Project $projectId -Message "Start migratie van service connections" -LogPath $logPath
            $scParams = @{
                SourceOrganizationUrl = $config.sourceOrganization
                DestinationOrganizationUrl = $config.destinationOrganization
                SourceProject = $migration.sourceProject
                DestinationProject = $migration.destinationProject
                ServiceConnections = $migration.serviceConnections
            }
            New-AzDoServiceConnections @scParams
            Write-MigrationLog -Project $projectId -Message "Service connections migratie voltooid" -LogPath $logPath
        }

        Write-MigrationLog -Project $projectId -Message "Migratie voltooid" -LogPath $logPath
        $Global:completed++
        $percentComplete = ($Global:completed / $totalMigrations) * 100
        Write-Progress -Activity "Migratie" -Status "$Global:completed van $totalMigrations projecten" -PercentComplete $percentComplete
    }
    catch {
        Write-MigrationLog -Project $projectId -Message "Fout tijdens migratie: $_" -LogPath $logPath
        throw
    }
}

Write-MigrationLog -Project "Setup" -Message "Alle migraties zijn voltooid" -LogPath $LogPath