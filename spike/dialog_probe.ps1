<#
A Windows Forms dialog driven by JSON files, started from Dorico's Lua with os.execute.
  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File dialog_probe.ps1 -Request <json> -Response <json> [-AutoClose]
Request: {"players": [...], "noteheads": [...]}. Response: {"cancelled": bool, "notehead": "..."}.
#>
param(
    [Parameter(Mandatory = $true)][string]$Request,
    [Parameter(Mandatory = $true)][string]$Response,
    [switch]$AutoClose
)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$req = Get-Content -Raw -Encoding UTF8 $Request | ConvertFrom-Json

$form = New-Object System.Windows.Forms.Form
$form.Text = "Handbells Used Chart (spike)"
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.AutoSize = $true
$form.AutoSizeMode = "GrowAndShrink"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$layout = New-Object System.Windows.Forms.FlowLayoutPanel
$layout.FlowDirection = "TopDown"
$layout.AutoSize = $true
$layout.Padding = New-Object System.Windows.Forms.Padding 12

$label = New-Object System.Windows.Forms.Label
$label.AutoSize = $true
$label.Text = "Players: " + (($req.players) -join ", ")
$layout.Controls.Add($label)

$combo = New-Object System.Windows.Forms.ComboBox
$combo.DropDownStyle = "DropDownList"
$combo.Width = 320
foreach ($n in $req.noteheads) { [void]$combo.Items.Add($n) }
if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }
$layout.Controls.Add($combo)

$ok = New-Object System.Windows.Forms.Button
$ok.Text = "OK"
$ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $ok
$layout.Controls.Add($ok)
$form.Controls.Add($layout)

if ($AutoClose) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({ $timer.Stop(); $ok.PerformClick() })
    $form.Add_Shown({ $timer.Start() })
}
$form.Add_Shown({ $form.Activate() })

$result = $form.ShowDialog()
$out = @{ cancelled = ($result -ne [System.Windows.Forms.DialogResult]::OK); notehead = [string]$combo.SelectedItem }
[System.IO.File]::WriteAllText($Response, ($out | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
