[CmdletBinding()]
param (
    [ValidateSet(
        'Windows Server 2025',
        'Windows Server 2022',
        'Windows 11, version 26H1',
        'Windows 11, version 25H2',
        'Windows 11, version 24H2',
        'Windows 11, version 23H2',
        'Windows Server, version 23H2'
    )]
    [string] $Name = 'Windows Server 2025',

    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = 'arm64',

    [string] $Build = 'latest',

    [ValidateSet('BOnly', 'AllNonPreview')]
    [string] $CandidateSet = 'BOnly',

    [int] $MaxCandidates = 6,

    [string] $Language = 'en-US',

    [string] $ReportingSku,

    [string] $Edition,

    [string] $WorkingDirectory = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'uup-build-probe')),

    [int] $ConversionProbeSeconds = 45,

    [string] $UupMediaCreatorPath
)

$boundName = $Name
$boundArchitecture = $Architecture
$boundBuild = $Build
$boundCandidateSet = $CandidateSet
$boundMaxCandidates = $MaxCandidates
$boundLanguage = $Language
$boundReportingSku = $ReportingSku
$boundEdition = $Edition
$boundWorkingDirectory = $WorkingDirectory
$boundConversionProbeSeconds = $ConversionProbeSeconds
$boundUupMediaCreatorPath = $UupMediaCreatorPath

. (Join-Path $PSScriptRoot 'Get-WindowsUpdateHistory.ps1')

$Name = $boundName
$Architecture = $boundArchitecture
$Build = $boundBuild
$CandidateSet = $boundCandidateSet
$MaxCandidates = $boundMaxCandidates
$Language = $boundLanguage
$ReportingSku = $boundReportingSku
$Edition = $boundEdition
$WorkingDirectory = $boundWorkingDirectory
$ConversionProbeSeconds = $boundConversionProbeSeconds
$UupMediaCreatorPath = $boundUupMediaCreatorPath

function Get-DefaultProbeConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [string] $ReportingSku,

        [string] $Edition
    )

    $defaults = switch ($Name) {
        'Windows Server 2025' {
            @{
                ReportingSku = 'StandardServer'
                Edition      = 'ServerStandard'
                Branch       = 'fe_release'
            }
        }
        'Windows Server 2022' {
            @{
                ReportingSku = 'StandardServer'
                Edition      = 'ServerStandard'
                Branch       = 'fe_release'
            }
        }
        'Windows Server, version 23H2' {
            @{
                ReportingSku = 'StandardServer'
                Edition      = 'ServerStandard'
                Branch       = 'fe_release'
            }
        }
        default {
            @{
                ReportingSku = 'Professional'
                Edition      = 'Professional'
                Branch       = 'vb_release'
            }
        }
    }

    if ($ReportingSku) {
        $defaults.ReportingSku = $ReportingSku
    }

    if ($Edition) {
        $defaults.Edition = $Edition
    }

    return [PSCustomObject] $defaults
}

function Get-ProbeCandidates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Build,

        [Parameter(Mandatory = $true)]
        [string] $CandidateSet,

        [Parameter(Mandatory = $true)]
        [int] $MaxCandidates
    )

    $history = @(Get-WindowsUpdateHistory -Name $Name)
    $candidates = New-Object System.Collections.Generic.List[object]

    if ($Build -ne 'latest') {
        $candidates.Add([PSCustomObject]@{
            Title       = "$Name (manual probe build $Build)"
            KB          = $null
            Build       = [version] $Build
            Link        = $null
            UpdateType  = 'Manual'
            ReleaseDate = $null
            Source      = 'Manual'
            IsPreview   = $false
        })

        $history = $history | Where-Object { $_.Build -le [version] $Build }
    }

    if ($CandidateSet -eq 'BOnly') {
        $history = $history | Where-Object { $_.UpdateType -match '\sB$' }
    }

    foreach ($update in $history) {
        $candidates.Add($update)
    }

    $seen = @{}
    return $candidates |
        Where-Object {
            $buildKey = $_.Build.ToString()
            if ($seen.ContainsKey($buildKey)) {
                return $false
            }

            $seen[$buildKey] = $true
            return $true
        } |
        Select-Object -First $MaxCandidates
}

function Ensure-UupMediaCreator {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    $downloadExe = Join-Path $DestinationPath 'UUPDownload.exe'
    $converterExe = Join-Path $DestinationPath 'UUPMediaConverter.exe'
    if ((Test-Path -Path $downloadExe) -and (Test-Path -Path $converterExe)) {
        return [PSCustomObject]@{
            DownloadExe  = $downloadExe
            ConverterExe = $converterExe
        }
    }

    $zipPath = Join-Path (Split-Path -Path $DestinationPath -Parent) 'UUPMediaCreator.zip'
    New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest 'https://github.com/gus33000/UUPMediaCreator/releases/download/v3.1.9.3/win-x64-binaries.zip' -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $DestinationPath -Force

    return [PSCustomObject]@{
        DownloadExe  = $downloadExe
        ConverterExe = $converterExe
    }
}

function Get-UupWorkspaceState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $WorkspacePath,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Language
    )

    $editionPackagesPath = Join-Path $WorkspacePath 'UUP\Desktop\editionpackages'
    $neutralEditionPath = Join-Path $editionPackagesPath 'neutral'
    $serverLanguagePath = Join-Path $editionPackagesPath (Join-Path $Language 'Server')
    $metadataCompDbPath = Join-Path $WorkspacePath 'UUP\Desktop\MetadataCompDBPackages'

    $neutralEditionPackages = @()
    if (Test-Path -Path $neutralEditionPath) {
        $neutralEditionPackages = @(Get-ChildItem -Path $neutralEditionPath -File)
    }

    $serverLanguagePackages = @()
    if (Test-Path -Path $serverLanguagePath) {
        $serverLanguagePackages = @(Get-ChildItem -Path $serverLanguagePath -File)
    }

    $metadataCompDbPackages = @()
    if (Test-Path -Path $metadataCompDbPath) {
        $metadataCompDbPackages = @(Get-ChildItem -Path $metadataCompDbPath -Recurse -File)
    }

    $neutralServerNamedPackages = @($neutralEditionPackages | Where-Object { $_.Name -match 'Server|Datacenter|Standard' })
    $neutralClientNamedPackages = @($neutralEditionPackages | Where-Object { $_.Name -match 'Client|Professional|Core' })

    return [PSCustomObject]@{
        WorkspacePath                = $WorkspacePath
        NeutralEditionPackageCount   = $neutralEditionPackages.Count
        NeutralServerPackageCount    = $neutralServerNamedPackages.Count
        NeutralClientPackageCount    = $neutralClientNamedPackages.Count
        ServerLanguagePackageCount   = $serverLanguagePackages.Count
        MetadataCompDbPackageCount   = $metadataCompDbPackages.Count
        HasNeutralEditionPackages    = $neutralEditionPackages.Count -gt 0
        HasServerLanguagePackages    = $serverLanguagePackages.Count -gt 0
        HasMetadataCompDbPackages    = $metadataCompDbPackages.Count -gt 0
        NeutralEditionPackageNames   = @($neutralEditionPackages | Select-Object -ExpandProperty Name)
        NeutralServerPackageNames    = @($neutralServerNamedPackages | Select-Object -ExpandProperty Name)
        NeutralClientPackageNames    = @($neutralClientNamedPackages | Select-Object -ExpandProperty Name)
        ServerLanguagePackageNames   = @($serverLanguagePackages | Select-Object -ExpandProperty Name)
    }
}

function Invoke-QuickConversionProbe {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ConverterExe,

        [Parameter(Mandatory = $true)]
        [string] $WorkspacePath,

        [Parameter(Mandatory = $true)]
        [string] $Language,

        [Parameter(Mandatory = $true)]
        [string] $ProbeDirectory,

        [Parameter(Mandatory = $true)]
        [int] $TimeoutSeconds
    )

    New-Item -Path $ProbeDirectory -ItemType Directory -Force | Out-Null
    $stdoutPath = Join-Path $ProbeDirectory 'converter.stdout.log'
    $stderrPath = Join-Path $ProbeDirectory 'converter.stderr.log'
    $isoPath = Join-Path $ProbeDirectory 'probe.iso'

    $process = Start-Process -FilePath $ConverterExe `
        -ArgumentList @('-l', $Language, '--uup-path', $WorkspacePath, '--iso-path', $isoPath) `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $process.Refresh()
    }

    $timedOut = -not $process.HasExited
    if ($timedOut) {
        Stop-Process -Id $process.Id -Force
    }

    $combinedLog = @(
        if (Test-Path -Path $stdoutPath) { Get-Content -Path $stdoutPath -Raw }
        if (Test-Path -Path $stderrPath) { Get-Content -Path $stderrPath -Raw }
    ) -join "`n"

    if ($combinedLog -match "couldn't find an edition composition") {
        return [PSCustomObject]@{
            Status = 'missing-edition-composition'
            Log    = $combinedLog
        }
    }

    if ($timedOut) {
        return [PSCustomObject]@{
            Status = 'passed-metadata-gate'
            Log    = $combinedLog
        }
    }

    if ((Test-Path -Path $isoPath) -and $process.ExitCode -eq 0) {
        return [PSCustomObject]@{
            Status = 'completed'
            Log    = $combinedLog
        }
    }

    return [PSCustomObject]@{
        Status = 'failed-early'
        Log    = $combinedLog
    }
}

function Test-UupCandidate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject] $Candidate,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Architecture,

        [Parameter(Mandatory = $true)]
        [string] $Language,

        [Parameter(Mandatory = $true)]
        [psobject] $Config,

        [Parameter(Mandatory = $true)]
        [psobject] $Tools,

        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [int] $ConversionProbeSeconds
    )

    $build = $Candidate.Build.ToString()
    $machineType = @{'x64'='amd64';'arm64'='arm64'}[$Architecture]
    $candidateRoot = Join-Path $WorkingDirectory ($build -replace '[^0-9.]', '_')
    New-Item -Path $candidateRoot -ItemType Directory -Force | Out-Null

    $existingWorkspace = Get-Item (Join-Path $candidateRoot '10.0.*') -ErrorAction SilentlyContinue | Select-Object -First 1
    $downloadExitCode = 0

    if (-not $existingWorkspace) {
        $downloadArguments = @(
            '-s', $Config.ReportingSku,
            '-r', 'Retail',
            '-b', 'Retail',
            '-c', $Config.Branch,
            '-l', $Language,
            '-t', $machineType,
            '-v', "10.0.$build",
            '-y',
            '-o', $candidateRoot
        )

        if ($Config.Edition) {
            $downloadArguments += @('-e', $Config.Edition)
        }

        & $Tools.DownloadExe @downloadArguments
        $downloadExitCode = $LASTEXITCODE
        $existingWorkspace = Get-Item (Join-Path $candidateRoot '10.0.*') -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($downloadExitCode -ne 0 -or -not $existingWorkspace) {
        return [PSCustomObject]@{
            Name                       = $Name
            Build                      = $build
            UpdateType                 = [string] $Candidate.UpdateType
            ReleaseDate                = [string] $Candidate.ReleaseDate
            ReportingSku               = $Config.ReportingSku
            Edition                    = $Config.Edition
            WorkspacePath              = if ($existingWorkspace) { $existingWorkspace.FullName } else { $null }
            HasNeutralEditionPackages  = $false
            NeutralEditionPackageCount = 0
            ProbeStatus                = 'download-failed'
            Notes                      = 'UUPDownload.exe did not produce a reusable workspace for the exact build.'
        }
    }

    $state = Get-UupWorkspaceState -WorkspacePath $existingWorkspace.FullName -Name $Name -Language $Language
    $isServerProduct = $Name -like 'Windows Server*'

    if ($isServerProduct -and -not $state.HasNeutralEditionPackages) {
        return [PSCustomObject]@{
            Name                       = $Name
            Build                      = $build
            UpdateType                 = [string] $Candidate.UpdateType
            ReleaseDate                = [string] $Candidate.ReleaseDate
            ReportingSku               = $Config.ReportingSku
            Edition                    = $Config.Edition
            WorkspacePath              = $state.WorkspacePath
            HasNeutralEditionPackages  = $state.HasNeutralEditionPackages
            NeutralEditionPackageCount = $state.NeutralEditionPackageCount
            ProbeStatus                = 'missing-neutral-edition-packages'
            Notes                      = 'The workspace only contains language-specific server payloads and no neutral edition packages, so media conversion will fail.'
        }
    }

    if ($isServerProduct -and $state.NeutralServerPackageCount -eq 0 -and $state.NeutralClientPackageCount -gt 0) {
        return [PSCustomObject]@{
            Name                       = $Name
            Build                      = $build
            UpdateType                 = [string] $Candidate.UpdateType
            ReleaseDate                = [string] $Candidate.ReleaseDate
            ReportingSku               = $Config.ReportingSku
            Edition                    = $Config.Edition
            WorkspacePath              = $state.WorkspacePath
            HasNeutralEditionPackages  = $state.HasNeutralEditionPackages
            NeutralEditionPackageCount = $state.NeutralEditionPackageCount
            ProbeStatus                = 'client-only-neutral-editions'
            Notes                      = 'The neutral edition package set is client-only, which matches the converter failure seen for non-convertible server media.'
        }
    }

    $probeResult = Invoke-QuickConversionProbe -ConverterExe $Tools.ConverterExe -WorkspacePath $existingWorkspace.FullName -Language $Language -ProbeDirectory (Join-Path $candidateRoot 'probe') -TimeoutSeconds $ConversionProbeSeconds

    return [PSCustomObject]@{
        Name                       = $Name
        Build                      = $build
        UpdateType                 = [string] $Candidate.UpdateType
        ReleaseDate                = [string] $Candidate.ReleaseDate
        ReportingSku               = $Config.ReportingSku
        Edition                    = $Config.Edition
        WorkspacePath              = $state.WorkspacePath
        HasNeutralEditionPackages  = $state.HasNeutralEditionPackages
        NeutralEditionPackageCount = $state.NeutralEditionPackageCount
        ProbeStatus                = $probeResult.Status
        Notes                      = switch ($probeResult.Status) {
            'passed-metadata-gate' { 'UUPMediaConverter stayed alive past the metadata gate, so this build looks promising.' }
            'completed' { 'UUPMediaConverter finished and produced the probe ISO.' }
            'missing-edition-composition' { 'UUPMediaConverter could not find an edition composition for the specified language.' }
            default { 'UUPMediaConverter failed before the metadata probe could be considered a pass.' }
        }
    }
}

$toolRoot = if ($UupMediaCreatorPath) {
    [System.IO.Path]::GetFullPath($UupMediaCreatorPath)
} else {
    Join-Path $WorkingDirectory 'UUPMediaCreator'
}

$config = Get-DefaultProbeConfig -Name $Name -ReportingSku $ReportingSku -Edition $Edition
$tools = Ensure-UupMediaCreator -DestinationPath $toolRoot
$candidates = @(Get-ProbeCandidates -Name $Name -Build $Build -CandidateSet $CandidateSet -MaxCandidates $MaxCandidates)

if ($candidates.Count -eq 0) {
    throw "No candidate builds were available for $Name."
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($candidate in $candidates) {
    $result = Test-UupCandidate -Candidate $candidate -Name $Name -Architecture $Architecture -Language $Language -Config $config -Tools $tools -WorkingDirectory $WorkingDirectory -ConversionProbeSeconds $ConversionProbeSeconds
    $results.Add($result)

    if ($result.ProbeStatus -in @('passed-metadata-gate', 'completed')) {
        break
    }
}

$results