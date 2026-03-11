[CmdletBinding()]
param (
    [string[]] $Name,

    [string] $OutputDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\history'))
)

. (Join-Path $PSScriptRoot 'Get-WindowsUpdateHistory.ps1')

function ConvertTo-HistoryFileName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $fileName = $Name.ToLowerInvariant()
    $fileName = $fileName -replace '[^a-z0-9]+', '-'
    $fileName = $fileName.Trim('-')
    return "$fileName.json"
}

if (-not $Name -or $Name.Count -eq 0) {
    $Name = Get-SupportedWindowsUpdateHistoryNames
}

New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

$generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$results = foreach ($historyName in $Name) {
    $updates = Get-WindowsUpdateHistory -Name $historyName | ForEach-Object {
        ConvertTo-WindowsUpdateJsonRecord -Name $historyName -Update $_
    }

    $payload = [PSCustomObject]@{
        Name           = $historyName
        GeneratedAtUtc = $generatedAtUtc
        UpdateCount    = @($updates).Count
        Updates        = @($updates)
    }

    $outputPath = Join-Path $OutputDirectory (ConvertTo-HistoryFileName -Name $historyName)
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $outputPath -Encoding utf8

    [PSCustomObject]@{
        Name        = $historyName
        OutputPath  = $outputPath
        UpdateCount = @($updates).Count
    }
}

return $results