function Get-WindowsUpdateHistory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
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

    $urlMap = @{
        'Windows Server 2025'          = 'https://support.microsoft.com/en-us/help/5005454'
        'Windows Server 2022'          = 'https://support.microsoft.com/en-us/help/5005454'
        'Windows 11, version 24H2'     = 'https://support.microsoft.com/en-us/help/5045988'
        'Windows 11, version 23H2'     = 'https://support.microsoft.com/en-us/help/5031682'
        'Windows 10, version 22H2'     = 'https://support.microsoft.com/en-us/help/5018682'
        'Windows Server, version 23H2' = 'https://support.microsoft.com/en-gb/help/5031680'
    }

    $UpdateHistoryName = $Name
    $UpdateHistoryUrl = $urlMap[$Name]
    $expectedName = $UpdateHistoryName

    $response = Invoke-WebRequest -Uri $UpdateHistoryUrl
    $html = $response.Content

    # Find all <ul class="supLeftNavArticles">...</ul> blocks
    $ulMatches = [regex]::Matches($html, '<ul\s+class="supLeftNavArticles">.*?</ul>', 'Singleline')

    Add-Type -AssemblyName System.Web

    $targetUlMatch = $ulMatches | ForEach-Object {
        $fragment = $_.Value -replace '&nbsp;', ' '
        $fragment = $fragment -replace '&(?!(amp|lt|gt|quot|apos);)', '&amp;'
        $xmlString = "<root>$fragment</root>"

        try {
            [xml]$parsedXml = $xmlString
        } catch {
            Write-Verbose "⚠ Failed to parse UL block as XML."
            return
        }

        $firstText = $parsedXml.root.ul.li[0].a.InnerText.Trim()
        $decoded = [System.Web.HttpUtility]::HtmlDecode($firstText)

        if ($decoded -eq $expectedName) {
            [PSCustomObject]@{
                Xml = $parsedXml
                Match = $_
            }
        }
    } | Select-Object -First 1

    if (-Not $targetUlMatch) {
        throw "❌ No matching update list found for: $UpdateHistoryName"
    }

    $xml = $targetUlMatch.Xml

    # Extract update entries
    $updates = foreach ($node in $xml.root.ul.li) {
        $a = $node.a
        $rawText = $a.InnerText.Trim()
        $text = [System.Web.HttpUtility]::HtmlDecode($rawText)
        $href = $a.href

        if ($text -match 'KB(?<kb>\d+).*?OS Build (?<build>\d{5}\.\d+)') {
            [PSCustomObject]@{
                Title = $text
                KB    = "KB$($matches['kb'])"
                Build = [version]$matches['build']
                Link  = "https://support.microsoft.com$href"
            }
        }
    }

    $stableUpdates = $updates | Where-Object {
        $_.Title -NotMatch 'Preview|Out-of-Band'
    } | Sort-Object Build -Descending

    return $stableUpdates
}