<#
Press a named button in a window through UI Automation (no mouse needed).
  powershell -NoProfile -File tools/dorico/click.ps1 -Window "Edit Instrument Names" -Button "OK"
Finds top-level windows by exact name, then Dorico's owned windows (Qt dialogs). Buttons that UI Automation
shows as Panes (WinForms) are pressed with BM_CLICK on their window handle. Exits 3 when nothing is found.
#>
param(
    [Parameter(Mandatory = $true)][string]$Window,
    [Parameter(Mandatory = $true)][string]$Button
)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HbucClick {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
}
"@
$A = [System.Windows.Automation.AutomationElement]
$scope = [System.Windows.Automation.TreeScope]
$root = $A::RootElement
$byName = New-Object System.Windows.Automation.PropertyCondition ($A::NameProperty), $Window
# A top-level window is found by Win32, which reads window titles without asking their programs: UI Automation's
# search of the desktop asks every window, and a Dorico waiting on the plug-in's dialog can take minutes to answer.
$hwnd = [HbucClick]::FindWindow([NullString]::Value, $Window)
$win = if ($hwnd -ne [IntPtr]::Zero) { $A::FromHandle($hwnd) } else { $null }
if (-not $win) {
    # Qt parents its dialogs to the main window, so look one level further down too.
    $proc = Get-Process -Name Dorico6 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        $byPid = New-Object System.Windows.Automation.PropertyCondition ($A::ProcessIdProperty), $proc.Id
        foreach ($top in $root.FindAll($scope::Children, $byPid)) {
            $win = $top.FindFirst($scope::Descendants, $byName)
            if ($win) { break }
        }
    }
}
if (-not $win) { Write-Output "no window named '$Window'"; exit 3 }
$named = New-Object System.Windows.Automation.PropertyCondition ($A::NameProperty), $Button
$isButton = New-Object System.Windows.Automation.PropertyCondition ($A::ControlTypeProperty), ([System.Windows.Automation.ControlType]::Button)
$btn = $win.FindFirst($scope::Descendants, (New-Object System.Windows.Automation.AndCondition $isButton, $named))
if (-not $btn) { $btn = $win.FindFirst($scope::Descendants, $named) }
if (-not $btn) { Write-Output "no button '$Button' in '$Window'"; exit 3 }
$invoke = $null
if ($btn.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invoke)) {
    $invoke.Invoke()
} else {
    $hwnd = [IntPtr]$btn.Current.NativeWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { Write-Output "'$Button' in '$Window' has no window handle"; exit 3 }
    [void][HbucClick]::SendMessage($hwnd, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK
}
"pressed '$Button' in '$Window'"
