$script:WindowsUpdateSources = [ordered]@{
    'Windows Server 2025' = @{
        Type           = 'ServerReleaseInfo'
        Url            = 'https://learn.microsoft.com/en-us/windows-server/get-started/windows-server-release-info'
        SectionHeading = 'Windows Server 2025'
    }
    'Windows Server 2022' = @{
        Type           = 'ServerReleaseInfo'
        Url            = 'https://learn.microsoft.com/en-us/windows-server/get-started/windows-server-release-info'
        SectionHeading = 'Windows Server 2022'
    }
    'Windows 11, version 24H2' = @{
        Type = 'SupportArticle'
        Url  = 'https://support.microsoft.com/en-us/topic/windows-11-version-24h2-update-history-0929c747-1815-4543-8461-0160d16f15e5'
    }
    'Windows 11, version 23H2' = @{
        Type = 'SupportArticle'
        Url  = 'https://support.microsoft.com/en-us/topic/windows-11-version-23h2-update-history-59875222-b990-4bd9-932f-91a5954de434'
    }
    'Windows 10, version 22H2' = @{
        Type = 'SupportArticle'
        Url  = 'https://support.microsoft.com/en-us/topic/windows-10-update-history-8127c2c6-6edf-4fdf-8b9f-0f7be1ef3562'
    }
    'Windows Server, version 23H2' = @{
        Type = 'SupportArticle'
        Url  = 'https://support.microsoft.com/en-us/help/5031680'
    }
}

function ConvertFrom-HtmlText {
    [CmdletBinding()]
    param (
        [AllowEmptyString()]
        [string] $Html
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ''
    }

    $text = [System.Net.WebUtility]::HtmlDecode($Html)
    $text = [regex]::Replace($text, '<[^>]+>', ' ')
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

function Resolve-UpdateLink {
    [CmdletBinding()]
    param (
        [AllowEmptyString()]
        [string] $Href,

        [Parameter(Mandatory = $true)]
        [string] $BaseUrl
    )

    if ([string]::IsNullOrWhiteSpace($Href)) {
        return $null
    }

    if ($Href -match '^https?://') {
        return $Href
    }

    if ($Href.StartsWith('/')) {
        return "https://support.microsoft.com$Href"
    }

    return ([System.Uri]::new([System.Uri]$BaseUrl, $Href)).AbsoluteUri
}

function Get-SupportArticleUpdates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [hashtable] $Definition
    )

    $response = Invoke-WebRequest -Uri $Definition.Url -UseBasicParsing
    $html = $response.Content
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $targetList = $null

    foreach ($listMatch in [regex]::Matches($html, '<ul\s+class="supLeftNavArticles"[^>]*>.*?</ul>', $regexOptions)) {
        $linkMatches = [regex]::Matches($listMatch.Value, '<a[^>]+href="(?<href>[^"]+)"[^>]*>(?<text>.*?)</a>', $regexOptions)
        if ($linkMatches.Count -eq 0) {
            continue
        }

        $firstTitle = ConvertFrom-HtmlText $linkMatches[0].Groups['text'].Value
        if ($firstTitle -eq $Name) {
            $targetList = $linkMatches
            break
        }
    }

    if (-not $targetList) {
        throw "No matching update list found for '$Name' at $($Definition.Url)."
    }

    $updates = foreach ($linkMatch in $targetList) {
        $title = ConvertFrom-HtmlText $linkMatch.Groups['text'].Value
        if ($title -notmatch 'KB(?<kb>\d+).*?OS Build (?<build>\d{5}\.\d+)') {
            continue
        }

        [PSCustomObject]@{
            Title            = $title
            KB               = "KB$($matches['kb'])"
            Build            = [version]$matches['build']
            Link             = Resolve-UpdateLink -Href $linkMatch.Groups['href'].Value -BaseUrl $Definition.Url
            UpdateType       = $null
            AvailabilityDate = $null
            Source           = 'SupportArticle'
            IsPreview        = $title -match 'Preview'
        }
    }

    return $updates | Where-Object { -not $_.IsPreview } | Sort-Object Build -Descending
}

function Get-ServerReleaseInfoUpdates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [hashtable] $Definition
    )

    $response = Invoke-WebRequest -Uri $Definition.Url -UseBasicParsing
    $html = $response.Content
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $headingPattern = [regex]::Escape($Definition.SectionHeading)
    $tableMatches = [regex]::Matches($html, "$headingPattern\s*\(OS build [^)]*\).*?<table[^>]*>(?<table>.*?)</table>", $regexOptions)
    $tableHtml = $null

    foreach ($tableMatch in $tableMatches) {
        $headerCells = [regex]::Matches($tableMatch.Groups['table'].Value, '<th[^>]*>(?<cell>.*?)</th>', $regexOptions) | ForEach-Object {
            ConvertFrom-HtmlText $_.Groups['cell'].Value
        }

        if ($headerCells -contains 'Servicing option' -and $headerCells -contains 'Update type' -and $headerCells -contains 'Build' -and $headerCells -contains 'KB article') {
            $tableHtml = $tableMatch.Groups['table'].Value
            break
        }
    }

    if (-not $tableHtml) {
        throw "Could not locate the '$Name' release history table at $($Definition.Url)."
    }

    $rowMatches = [regex]::Matches($tableHtml, '<tr[^>]*>(?<row>.*?)</tr>', $regexOptions)
    if ($rowMatches.Count -lt 2) {
        throw "The '$Name' release history table did not contain any update rows."
    }

    $updates = for ($rowIndex = 1; $rowIndex -lt $rowMatches.Count; $rowIndex++) {
        $rowHtml = $rowMatches[$rowIndex].Groups['row'].Value
        $cellMatches = [regex]::Matches($rowHtml, '<t[dh][^>]*>(?<cell>.*?)</t[dh]>', $regexOptions)
        if ($cellMatches.Count -lt 5) {
            continue
        }

        $cells = @($cellMatches | ForEach-Object { ConvertFrom-HtmlText $_.Groups['cell'].Value })
        $buildText = $cells[3] -replace '^OS Build\s*', ''
        $kbMatch = [regex]::Match($cells[4], 'KB\d+')
        if ($buildText -notmatch '^\d+\.\d+$' -or -not $kbMatch.Success) {
            continue
        }

        $kbCellHtml = $cellMatches[4].Groups['cell'].Value
        $hrefMatch = [regex]::Match($kbCellHtml, 'href="(?<href>[^"]+)"', $regexOptions)
        $updateType = $cells[1]

        [PSCustomObject]@{
            Title            = "$Name $($kbMatch.Value) (OS Build $buildText)"
            KB               = $kbMatch.Value
            Build            = [version]$buildText
            Link             = Resolve-UpdateLink -Href $hrefMatch.Groups['href'].Value -BaseUrl $Definition.Url
            UpdateType       = $updateType
            AvailabilityDate = $cells[2]
            Source           = 'WindowsServerReleaseInfo'
            IsPreview        = $updateType -match '\sD$' -or $updateType -match 'Preview'
        }
    }

    return $updates | Where-Object { -not $_.IsPreview } | Sort-Object Build -Descending
}

function Get-WindowsUpdateHistory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet(
            'Windows Server 2025',
            'Windows Server 2022',
            'Windows 11, version 24H2',
            'Windows 11, version 23H2',
            'Windows 10, version 22H2',
            'Windows Server, version 23H2'
        )]
        [string] $Name
    )

    $definition = $script:WindowsUpdateSources[$Name]
    if (-not $definition) {
        throw "Unsupported release history name '$Name'."
    }

    switch ($definition.Type) {
        'ServerReleaseInfo' {
            return Get-ServerReleaseInfoUpdates -Name $Name -Definition $definition
        }
        'SupportArticle' {
            return Get-SupportArticleUpdates -Name $Name -Definition $definition
        }
        default {
            throw "Unsupported source type '$($definition.Type)' for '$Name'."
        }
    }
}