<#
Runs PSScriptAnalyzer on the given files with the repo's settings and the InjectionHunter rules, and prints every
finding as one JSON array. tools/lint.py starts it. It runs in Windows PowerShell 5.1 and in PowerShell 7.
#>
param(
    [Parameter(Mandatory = $true)] [string] $Settings,
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $Files
)
$ErrorActionPreference = 'Stop'
Import-Module PSScriptAnalyzer
$injectionHunter = (Get-Module -ListAvailable InjectionHunter | Select-Object -First 1).Path
if (-not $injectionHunter) {
    throw 'InjectionHunter is not installed. Install it with: Install-Module InjectionHunter -Scope CurrentUser'
}
$records = foreach ($file in $Files) {
    Invoke-ScriptAnalyzer -Path $file -Settings $Settings -CustomRulePath $injectionHunter -IncludeDefaultRules
}
$out = @($records | ForEach-Object {
        [pscustomobject]@{
            RuleName   = $_.RuleName
            Severity   = $_.Severity.ToString()
            Line       = $_.Line
            Column     = $_.Column
            Message    = $_.Message
            ScriptPath = $_.ScriptPath
        }
    })
ConvertTo-Json -InputObject $out -Depth 3
