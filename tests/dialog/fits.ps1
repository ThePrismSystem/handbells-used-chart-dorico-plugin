<#
Says "yes" when the window titled -Title and its -Button both lie inside the screen's working area, else what was
measured. For tests/dialog/test_windows_dialog.py. Win32 throughout, so every rectangle is in the same coordinates.
  powershell -NoProfile -File tests/dialog/fits.ps1 -Title <title> -Button OK
#>
param(
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Button
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class HbucFits {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int n);
    public static IntPtr Child(IntPtr parent, string text) {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (h, l) => {
            var sb = new StringBuilder(256);
            GetWindowText(h, sb, 256);
            if (sb.ToString() == text) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
$hwnd = [HbucFits]::FindWindow([NullString]::Value, $Title)
if ($hwnd -eq [IntPtr]::Zero) { "no window"; exit 3 }
# Not $button: that is $Button, this script's parameter, since PowerShell names ignore case.
$buttonHwnd = [HbucFits]::Child($hwnd, $Button)
if ($buttonHwnd -eq [IntPtr]::Zero) { "no button"; exit 3 }
$w = New-Object HbucFits+RECT
$b = New-Object HbucFits+RECT
[void][HbucFits]::GetWindowRect($hwnd, [ref]$w)
[void][HbucFits]::GetWindowRect($buttonHwnd, [ref]$b)
$work = [System.Windows.Forms.Screen]::FromHandle($hwnd).WorkingArea
if ($w.Top -ge $work.Top -and $w.Bottom -le $work.Bottom -and $b.Top -ge $w.Top -and $b.Bottom -le $w.Bottom) {
    "yes"
} else {
    "window $($w.Top)-$($w.Bottom), button $($b.Top)-$($b.Bottom), working area $($work.Top)-$($work.Bottom)"
}
