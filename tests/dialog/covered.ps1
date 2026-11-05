<#
Runs dialog/windows.ps1 inside Pester with code coverage, for tests/dialog/test_windows_dialog.py when
HBUC_PS_COVERAGE is set (tests/dialog/launch.py). Pester measures only a script that runs in its own session, so the
dialog runs here instead of in a PowerShell of its own. It takes windows.ps1's parameters and passes them on.
  powershell -NoProfile -File tests/dialog/covered.ps1 -Out <report.xml> -Request <path> -Response <path>
Exits 0 when windows.ps1 finished without an error.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '',
    Justification = 'Pester 6 is imported first; the 5.1 profile knows only the Pester 3.4 that ships with Windows')]
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Request,
    [string]$Response,
    [string]$Message,
    [string]$Choice
)
$ErrorActionPreference = "Stop"
Import-Module Pester -MinimumVersion 6.0
$dialog = Join-Path $PSScriptRoot "..\..\plugin\Handbells Used Chart\dialog\windows.ps1"
$arguments = @{}
if ($Request) { $arguments.Request = $Request }
if ($Response) { $arguments.Response = $Response }
if ($Message) { $arguments.Message = $Message }
if ($Choice) { $arguments.Choice = $Choice }
$container = New-PesterContainer -Path (Join-Path $PSScriptRoot "covered.Tests.ps1") `
    -Data @{ Dialog = $dialog; Arguments = $arguments }
$config = New-PesterConfiguration
$config.Run.Container = $container
$config.Run.Exit = $true
$config.Output.Verbosity = "None"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = $dialog
$config.CodeCoverage.OutputFormat = "Cobertura"
$config.CodeCoverage.OutputPath = $Out
Invoke-Pester -Configuration $config
