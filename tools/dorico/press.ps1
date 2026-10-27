<#
Bring one of Dorico's windows to the front and send it keystrokes (for dismissing a modal prompt).
  powershell -NoProfile -File tools/dorico/press.ps1 (-Index <n> | -Title <exact title>) [-Keys "{ENTER}"]
<n> is the window's position in `capture.ps1 -All` output. Keys use System.Windows.Forms.SendKeys syntax.
With -Title, exits 3 without pressing anything when no window has exactly that title.
#>
param(
    [int]$Index = -1,
    [string]$Title,
    [string]$Keys = "{ENTER}"
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class HbucPress {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, System.Text.StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static List<IntPtr> WindowsOf(uint pid) {
        var found = new List<IntPtr>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) found.Add(h);
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
$proc = Get-Process -Name Dorico6 -ErrorAction Stop | Select-Object -First 1
$windows = [HbucPress]::WindowsOf([uint32]$proc.Id)
if ($Title) {
    $h = $null
    foreach ($w in $windows) {
        $sb = New-Object System.Text.StringBuilder 512
        [void][HbucPress]::GetWindowText($w, $sb, 512)
        if ($sb.ToString() -eq $Title) { $h = $w; break }
    }
    if (-not $h) { exit 3 }
} else {
    if ($Index -lt 0 -or $Index -ge $windows.Count) { throw "Dorico has only $($windows.Count) visible windows" }
    $h = $windows[$Index]
}
# Windows only lets a process take the foreground after recent input; a lone ALT press satisfies that rule.
[HbucPress]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [HbucPress]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
[void][HbucPress]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 300
if ([HbucPress]::GetForegroundWindow() -ne $h) { throw "could not bring window $Index to the front" }
[System.Windows.Forms.SendKeys]::SendWait($Keys)
"sent $Keys to window $Index"
