<#
Says "yes" when a visible top-level window has exactly this title. For the tests that wait for the plug-in's windows.
  powershell -NoProfile -File tools/dorico/haswindow.ps1 -Title <title>
Win32 reads window titles without asking their programs. UI Automation's search of the desktop asks every window,
and a Dorico waiting on the plug-in's dialog can take minutes to answer, so a wait for the dialog ran out with the
dialog on screen.
#>
param([Parameter(Mandatory = $true)][string]$Title)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HbucHas {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
}
"@
$hwnd = [HbucHas]::FindWindow([NullString]::Value, $Title)
if ($hwnd -ne [IntPtr]::Zero -and [HbucHas]::IsWindowVisible($hwnd)) { "yes" } else { "no" }
