@{
    Severity = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # InjectionHunter's Add-Type rule only looks at -TypeDefinition, so it reports every Add-Type -AssemblyName.
        # tests/test_shipped_calls.py lists every Add-Type the plug-in ships instead.
        'Measure-AddType',
        # The New- functions here build WinForms controls in memory. None of them changes anything that -WhatIf
        # could guard.
        'PSUseShouldProcessForStateChangingFunctions'
    )
    Rules    = @{
        # The plug-in starts its dialog with Windows PowerShell 5.1 (powershell.exe), and the tests and tools use it
        # too, so every script must work there as well as in PowerShell 7.
        PSUseCompatibleSyntax   = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        # PSUseCompatibleTypes is left off: it reports every WinForms and UI Automation type, which the scripts load
        # themselves with Add-Type -AssemblyName.
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @('win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }
    }
}
