# uup-media

GitHub Actions workflows for building Windows ISO images from UUP packages with UUPMediaCreator.

## What changed

- Windows Server build selection now uses the first-party Windows Server release history table on Learn instead of scraping the legacy support page navigation.
- The PowerShell Gallery module `WindowsReleaseInformation` is intentionally not used here because it only exposes Windows 10 and Windows 11 commands and does not cover Windows Server release history.
- The Windows Server 2025 workflow now accepts manual `os_arch` and `os_build` inputs so an `arm64` build can be attempted explicitly.
- The Windows Server 2022 workflow now accepts a manual `os_build` input for repeatable rebuilds.

## Files

- `scripts/Get-WindowsUpdateHistory.ps1`: resolves the latest non-preview build for the supported Windows products and can write the selected result to JSON.
- `scripts/Export-WindowsUpdateHistory.ps1`: exports the full usable history for all supported products into snapshot JSON files under `history/`.
- `.github/workflows/windows-2025-iso.yml`: builds Windows Server 2025 ISO artifacts.
- `.github/workflows/windows-2022-iso.yml`: builds Windows Server 2022 ISO artifacts.
- `.github/workflows/windows-11-iso.yml`: builds Windows 11 ISO artifacts.
- `.github/workflows/windows-10-iso.yml`: builds Windows 10 ISO artifacts.

## Data sources

- Windows Server 2025 and Windows Server 2022: `https://learn.microsoft.com/en-us/windows-server/get-started/windows-server-release-info`
- Windows 11 24H2: `https://support.microsoft.com/en-us/topic/windows-11-version-24h2-update-history-0929c747-1815-4543-8461-0160d16f15e5`
- Windows 11 23H2: `https://support.microsoft.com/en-us/topic/windows-11-version-23h2-update-history-59875222-b990-4bd9-932f-91a5954de434`
- Windows 10 22H2: `https://support.microsoft.com/en-us/topic/windows-10-update-history-8127c2c6-6edf-4fdf-8b9f-0f7be1ef3562`
- Windows Server, version 23H2: `https://support.microsoft.com/en-us/help/5031680`

## Local usage

Write the latest usable Windows Server 2025 build to a JSON file:

```powershell
.\scripts\Get-WindowsUpdateHistory.ps1 -Name 'Windows Server 2025' -OutputPath .\windows-server-2025.json
Get-Content .\windows-server-2025.json
```

Query all updates in-memory when you want the full list instead of a JSON artifact:

```powershell
. .\scripts\Get-WindowsUpdateHistory.ps1
Get-WindowsUpdateHistory 'Windows 11, version 24H2' | Select-Object -First 5
```

Export full history snapshots for every supported product into `history/`:

```powershell
.\scripts\Export-WindowsUpdateHistory.ps1
Get-ChildItem .\history\*.json
```

## GitHub Actions usage

Windows Server 2025 can now be dispatched with an explicit architecture and build:

```powershell
gh workflow run windows-2025-iso.yml -f os_arch=arm64 -f os_build=latest
```

To rebuild a known Windows Server 2022 build:

```powershell
gh workflow run windows-2022-iso.yml -f os_build=20348.4893
```

## Notes on Windows Server 2025 ARM

The workflow is wired to try `arm64` by passing `-t arm64` to `UUPDownload.exe` for `StandardServer` on `fe_release`.
Whether that succeeds depends on Microsoft publishing matching UUP packages for that SKU and architecture.
If packages are unavailable, the workflow should fail during the UUP download step rather than during build selection.
