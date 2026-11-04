# The one test covered.ps1 runs: windows.ps1 with the arguments it was given, inside Pester so Pester can measure it.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Dialog',
    Justification = 'The It block runs it')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Arguments',
    Justification = 'The It block splats it')]
param($Dialog, $Arguments)

Describe "windows.ps1" {
    It "runs to the end" { & $Dialog @Arguments }
}
