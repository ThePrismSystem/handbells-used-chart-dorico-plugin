<#
Capture Dorico's main window to a PNG, even when another window is in front of it.
  powershell -NoProfile -File tools/dorico/capture.ps1 -Out <png> [-All] [-TitleLike <wildcard>]
-All captures every top-level Dorico window (dialogs included) into <png> with an index suffix.
-ProcessId captures another process's windows instead (the plug-in's own dialog, which PowerShell shows).
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [switch]$All,
    [string]$TitleLike,
    [int]$ProcessId = 0
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class HbucWin {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hwnd, StringBuilder sb, int max);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public static List<IntPtr> WindowsOf(uint pid) {
        var found = new List<IntPtr>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) found.Add(h);
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static string Title(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
}
"@

[void][HbucWin]::SetProcessDPIAware()   # otherwise window rectangles come back scaled and captures are cropped
if ($ProcessId -gt 0) {
    $proc = Get-Process -Id $ProcessId -ErrorAction Stop
} else {
    $proc = Get-Process -Name Dorico6 -ErrorAction Stop | Select-Object -First 1
}
$windows = [HbucWin]::WindowsOf([uint32]$proc.Id)
if ($windows.Count -eq 0) { throw "process $($proc.Id) has no visible windows" }

function Save-Window([IntPtr]$h, [string]$path) {
    if ([HbucWin]::IsIconic($h)) { [void][HbucWin]::ShowWindow($h, 9) ; Start-Sleep -Milliseconds 500 }
    $r = New-Object HbucWin+RECT
    [void][HbucWin]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
    if ($w -le 0 -or $hgt -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $w, $hgt
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][HbucWin]::PrintWindow($h, $hdc, 2)   # PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    return "$path`t$w x $hgt`t$([HbucWin]::Title($h))"
}

if ($All) {
    $i = 0
    foreach ($h in $windows) {
        $path = [System.IO.Path]::ChangeExtension($Out, $null).TrimEnd('.') + "-$i.png"
        $line = Save-Window $h $path
        if ($line) { $line }
        $i++
    }
} elseif ($TitleLike) {
    $match = $windows | Where-Object { [HbucWin]::Title($_) -like $TitleLike } | Select-Object -First 1
    if (-not $match) { throw "no Dorico window titled like '$TitleLike'" }
    Save-Window $match $Out
} else {
    # The main window is the largest visible one.
    $main = $windows | Sort-Object { $r = New-Object HbucWin+RECT; [void][HbucWin]::GetWindowRect($_, [ref]$r); -(($r.Right - $r.Left) * ($r.Bottom - $r.Top)) } | Select-Object -First 1
    Save-Window $main $Out
}
