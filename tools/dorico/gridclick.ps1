<#
Click a cell of the Windows dialog's instrument table, and optionally press keys in it, with window messages (no
mouse, and the window need not be in front). For tests/dialog/test_windows_dialog.py.
  powershell -NoProfile -File tools/dorico/gridclick.ps1 -Window <title> -Row 1 -Column 0 -Shown 3 [-Keys Down,Return]
Row and Column count from 0 (the header is not a row). Shown: how many rows the table shows (windows.ps1 shows
3 to 8). Column widths are windows.ps1's, at 96 dpi. The header is as tall as a row there, and the table's window is
the first one with no text after the "Instruments to Chart" label. Exits 3 when the table is not found.
#>
param(
    [Parameter(Mandatory = $true)][string]$Window,
    [Parameter(Mandatory = $true)][int]$Row,
    [Parameter(Mandatory = $true)][int]$Column,
    [Parameter(Mandatory = $true)][int]$Shown,
    [string[]]$Keys = @()
)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HbucGrid {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public int cbSize, flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);
}
"@
# The same pixels as the dialog, which is DPI-aware too.
[void][HbucGrid]::SetProcessDPIAware()
$probe = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$scale = $probe.DpiX / 96.0
$probe.Dispose()

$A = [System.Windows.Automation.AutomationElement]
$scope = [System.Windows.Automation.TreeScope]
$byName = New-Object System.Windows.Automation.PropertyCondition ($A::NameProperty), $Window
$win = $A::RootElement.FindFirst($scope::Children, $byName)
if (-not $win) { Write-Output "no window named '$Window'"; exit 3 }
$all = @($win.FindAll($scope::Descendants, [System.Windows.Automation.Condition]::TrueCondition))
$grid = $null
for ($i = 0; $i -lt $all.Count - 1; $i++) {
    if ($all[$i].Current.Name -eq "Instruments to Chart") {
        for ($j = $i + 1; $j -lt $all.Count; $j++) {
            if ($all[$j].Current.Name -eq "") { $grid = $all[$j]; break }
        }
        break
    }
}
if (-not $grid) { Write-Output "no instrument table in '$Window'"; exit 3 }
$hwnd = [IntPtr]$grid.Current.NativeWindowHandle

$client = New-Object HbucGrid+RECT
[void][HbucGrid]::GetClientRect($hwnd, [ref]$client)
$rowHeight = ($client.Bottom - $client.Top) / ($Shown + 1)
$widths = @(56, 220, 300) | ForEach-Object { $_ * $scale }
$x = 0
for ($c = 0; $c -lt $Column; $c++) { $x += $widths[$c] }
$x = [int]($x + $widths[$Column] / 2)   # the middle of the cell: a check box ticks only on its glyph
$y = [int](($Row + 1.5) * $rowHeight)
$point = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
[void][HbucGrid]::PostMessage($hwnd, 0x0201, [IntPtr]1, $point)   # WM_LBUTTONDOWN, MK_LBUTTON
[void][HbucGrid]::PostMessage($hwnd, 0x0202, [IntPtr]::Zero, $point)   # WM_LBUTTONUP
Start-Sleep -Milliseconds 400

# Keys go to whatever has the focus in the dialog's thread (the cell's editor once the click has opened it), sent
# straight to its window.
$codes = @{ Down = 0x28; Up = 0x26; Return = 0x0D; Space = 0x20; Escape = 0x1B }
# -File hands "Down,Return" over as one string
$Keys = @($Keys | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
foreach ($k in $Keys) {
    if (-not $codes.ContainsKey($k)) { Write-Output "no key named '$k'"; exit 3 }
}
foreach ($k in $Keys) {
    $pid2 = [uint32]0
    $thread = [HbucGrid]::GetWindowThreadProcessId($hwnd, [ref]$pid2)
    $info = New-Object HbucGrid+GUITHREADINFO
    $info.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($info)
    [void][HbucGrid]::GetGUIThreadInfo($thread, [ref]$info)
    $target = if ($info.hwndFocus -ne [IntPtr]::Zero) { $info.hwndFocus } else { $hwnd }
    [void][HbucGrid]::SendMessage($target, 0x0100, [IntPtr]$codes[$k], [IntPtr]1)   # WM_KEYDOWN
    [void][HbucGrid]::SendMessage($target, 0x0101, [IntPtr]$codes[$k], [IntPtr]0xC0000001)   # WM_KEYUP
    Start-Sleep -Milliseconds 300
}
"clicked row $Row, column $Column"
