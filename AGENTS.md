# Repository Guidance

## Purpose

This repo builds Windows ISO artifacts from UUP packages through GitHub Actions.
The main maintenance risk is build-number drift when Microsoft updates release history pages.

## Source of truth

- Use the Windows Server Learn release-history page for Windows Server 2025 and Windows Server 2022.
- Use the product-specific Microsoft support update history pages for Windows 10, Windows 11, and Windows Server, version 23H2.
- Do not add the `WindowsReleaseInformation` PowerShell Gallery module here unless it gains first-class Windows Server coverage.

## Important files

- `Get-WindowsUpdateHistory.ps1`: lookup logic for supported products.
- `.github/workflows/windows-2025-iso.yml`: manual workflow for Windows Server 2025, now with `os_arch` and `os_build` inputs.
- `.github/workflows/windows-2022-iso.yml`: manual workflow for Windows Server 2022, with `os_build` input.
- `.github/workflows/windows-11-iso.yml`: Windows 11 workflow.
- `.github/workflows/windows-10-iso.yml`: Windows 10 workflow.

## Change guidelines

- Prefer first-party Microsoft data sources over community modules.
- Keep the lookup script dependency-free so it runs on stock GitHub-hosted runners.
- When updating workflows, keep artifact names aligned with the selected build and architecture.
- Treat `D` releases and entries explicitly labeled `Preview` as non-usable preview builds unless the repo is changed to support them intentionally.

## Verification

- Dot-source `Get-WindowsUpdateHistory.ps1` and verify at least `Windows Server 2025`, `Windows Server 2022`, and one desktop product.
- If changing the Windows Server 2025 workflow, test the lookup path first, then attempt an `arm64` dispatch or a local `UUPDownload.exe` probe.