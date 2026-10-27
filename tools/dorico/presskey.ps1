<#
Press a key in a window, as the keyboard would: the key is posted to whatever has the focus in the window's thread,
so it goes through Windows Forms' key handling (Enter for the OK button, say). For tests/dialog/test_windows_dialog.py.
  powershell -NoProfile -File tools/dorico/presskey.ps1 -Window <title> -Key Return
Exits 3 when the window is not found or the key is not one it knows.
#>
param(
    [Parameter(Mandatory = $true)][string]$Window,
    [Parameter(Mandatory = $true)][string]$Key
)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HbucKey {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public int cbSize, flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);
}
"@
$codes = @{ Return = 0x0D; Escape = 0x1B; Tab = 0x09; Space = 0x20 }
if (-not $codes.ContainsKey($Key)) { Write-Output "no key named '$Key'"; exit 3 }
$A = [System.Windows.Automation.AutomationElement]
$byName = New-Object System.Windows.Automation.PropertyCondition ($A::NameProperty), $Window
$win = $A::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $byName)
if (-not $win) { Write-Output "no window named '$Window'"; exit 3 }
$hwnd = [IntPtr]$win.Current.NativeWindowHandle
$pid2 = [uint32]0
$thread = [HbucKey]::GetWindowThreadProcessId($hwnd, [ref]$pid2)
$info = New-Object HbucKey+GUITHREADINFO
$info.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($info)
[void][HbucKey]::GetGUIThreadInfo($thread, [ref]$info)
$target = if ($info.hwndFocus -ne [IntPtr]::Zero) { $info.hwndFocus } else { $hwnd }
[void][HbucKey]::PostMessage($target, 0x0100, [IntPtr]$codes[$Key], [IntPtr]1)   # WM_KEYDOWN
[void][HbucKey]::PostMessage($target, 0x0101, [IntPtr]$codes[$Key], [IntPtr]0xC0000001)   # WM_KEYUP
"pressed $Key in '$Window'"
