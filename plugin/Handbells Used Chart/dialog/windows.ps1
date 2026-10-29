<#
Handbells Used Chart: the settings dialog and the results window, for Windows PowerShell 5.1 (nothing to install).
Started by the plug-in (hbuc/dorico/dialog.lua) with os.execute; Dorico waits until it closes.

  windows.ps1 -Request <request.json> -Response <response.json>   the settings dialog
  windows.ps1 -Message <message.json>                             the results window: {"title", "kind", "text", "ok"}
  windows.ps1 -Choice <choice.json> -Response <response.json>     a message with buttons, answering {"choice": id}
  windows.ps1 -Pick <pick.json> -Response <response.json>         a file picker, answering {"files": [...]}

A choice is {"title", "text", "buttons": [{"id", "label"}], "cancel": id}; closing the window or Esc answers the
cancel id. A pick is {"title", "folder", "files" (the first is preselected), "filter": {"name", "extensions"}}; a
cancel answers no files.

The request is what hbuc/request.lua builds. The response is the chosen options:
{"version", "runId", "cancelled": false, "instruments": [...], "atPitch": [...], "mode", "newPage": bool,
 "heads": {kind: set id}, "shapes": {kind: shape}, "colours": {kind: text}, "remove": bool}; a cancel is
 {"version", "runId", "cancelled": true}.
atPitch: the instruments whose "Written as" is at pitch. It is written as UTF-8 without a byte-order mark.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Response',
    Justification = 'Write-Response uses it')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 's',
    Justification = 'The sender, in event handlers that only need the event')]
param(
    [string]$Request,
    [string]$Response,
    [string]$Message,
    [string]$Choice,
    [string]$Pick
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Hbuc -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
# Drawn at the display's own resolution rather than scaled up blurry; fixed sizes are scaled to match.
[void][Hbuc.Dpi]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
$probe = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$Scale = $probe.DpiX / 96.0
$probe.Dispose()
function Px([int]$n) { return [int][Math]::Round($n * $Scale) }

$Utf8 = New-Object System.Text.UTF8Encoding $false

function Read-Json([string]$path) {
    return [System.IO.File]::ReadAllText($path, $Utf8) | ConvertFrom-Json
}

# Lua writes an empty list as {}, and PowerShell may hand back a one-item list as a bare value.
function ToList($value) {
    if ($null -eq $value) { return ,@() }
    if ($value -is [string]) { return ,@($value) }
    if ($value -is [System.Management.Automation.PSCustomObject] -and @($value.PSObject.Properties).Count -eq 0) {
        return ,@()
    }
    return ,@($value)
}

function Field($object, [string]$name) {
    if ($null -eq $object) { return $null }
    $p = $object.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function New-Label([string]$text, [bool]$bold = $false) {
    $l = New-Object System.Windows.Forms.Label
    $l.UseMnemonic = $false
    $l.Text = $text
    $l.AutoSize = $true
    $l.Margin = New-Object System.Windows.Forms.Padding 3, 6, 3, 3
    if ($bold) { $l.Font = New-Object System.Drawing.Font($l.Font, [System.Drawing.FontStyle]::Bold) }
    return $l
}

function New-Combo([object[]]$items, [int]$width) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = "DropDownList"
    $c.Width = Px $width
    foreach ($i in $items) { [void]$c.Items.Add([string]$i) }
    return $c
}

function New-Form([string]$title) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.AutoSize = $true
    $form.AutoSizeMode = "GrowAndShrink"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Add_Shown({ $this.Activate() })
    return $form
}

function New-Button([string]$text, $result) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.AutoSize = $true
    $b.MinimumSize = New-Object System.Drawing.Size (Px 80), 0
    $b.DialogResult = $result
    return $b
}

function Write-Response($object) {
    [System.IO.File]::WriteAllText($Response, (ConvertTo-Json -InputObject $object -Depth 5 -Compress), $Utf8)
}

# ---------------------------------------------------------------------------------------------------- results
if ($Message) {
    $msg = Read-Json $Message
    $form = New-Form ([string](Field $msg "title"))
    $layout = New-Object System.Windows.Forms.FlowLayoutPanel
    $layout.FlowDirection = "TopDown"
    $layout.AutoSize = $true
    $layout.Padding = New-Object System.Windows.Forms.Padding 12
    $text = New-Object System.Windows.Forms.Label
    $text.UseMnemonic = $false
    $text.Text = [string](Field $msg "text")
    $text.AutoSize = $true
    $text.MaximumSize = New-Object System.Drawing.Size (Px 560), 0
    # A long report scrolls, so the window and its OK button stay on the screen.
    $text.Font = $form.Font   # measured below, before the form would hand it its font
    $tall = $text.GetPreferredSize((New-Object System.Drawing.Size (Px 560), 0))
    $room = [int]([System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea.Height * 0.6)
    if ($tall.Height -gt $room) {
        $scroller = New-Object System.Windows.Forms.Panel
        $scroller.AutoScroll = $true
        $scroller.Size = New-Object System.Drawing.Size ($tall.Width + [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + (Px 4)), $room
        $scroller.Controls.Add($text)
        $layout.Controls.Add($scroller)
    } else {
        $layout.Controls.Add($text)
    }
    $okLabel = [string](Field $msg "ok")
    if (-not $okLabel) { $okLabel = "OK" }
    $ok = New-Button $okLabel ([System.Windows.Forms.DialogResult]::OK)
    $ok.Anchor = "Right"
    $layout.Controls.Add($ok)
    $form.Controls.Add($layout)
    $form.AcceptButton = $ok
    $form.CancelButton = $ok
    [void]$form.ShowDialog()
    exit 0
}

# ---------------------------------------------------------------------------------------------------- choice
if ($Choice) {
    $spec = Read-Json $Choice
    $cancelId = [string](Field $spec "cancel")
    $script:chosen = $cancelId
    $form = New-Form ([string](Field $spec "title"))
    $layout = New-Object System.Windows.Forms.FlowLayoutPanel
    $layout.FlowDirection = "TopDown"
    $layout.AutoSize = $true
    $layout.Padding = New-Object System.Windows.Forms.Padding 12
    $text = New-Object System.Windows.Forms.Label
    $text.UseMnemonic = $false
    $text.Text = [string](Field $spec "text")
    $text.AutoSize = $true
    $text.MaximumSize = New-Object System.Drawing.Size (Px 560), 0
    $layout.Controls.Add($text)
    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true
    $row.Anchor = "Right"
    foreach ($b in (ToList (Field $spec "buttons"))) {
        $button = New-Button ([string](Field $b "label")) ([System.Windows.Forms.DialogResult]::None)
        $button.Tag = [string](Field $b "id")
        $button.Add_Click({ param($s) $script:chosen = [string]$s.Tag; $s.FindForm().Close() })
        if ($button.Tag -eq $cancelId) { $form.CancelButton = $button }
        $row.Controls.Add($button)
    }
    $layout.Controls.Add($row)
    $form.Controls.Add($layout)
    [void]$form.ShowDialog()
    Write-Response @{ choice = $script:chosen }
    exit 0
}

# ---------------------------------------------------------------------------------------------------- picker
if ($Pick) {
    $spec = Read-Json $Pick
    # An owner that stays on top, so the picker opens above Dorico rather than behind it.
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.ShowInTaskbar = $false
    $owner.FormBorderStyle = "None"
    $owner.Opacity = 0
    $owner.StartPosition = "CenterScreen"
    $owner.Size = New-Object System.Drawing.Size 1, 1
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = [string](Field $spec "title")
    $picker.Multiselect = $true
    $folder = [string](Field $spec "folder")
    if ($folder) { $picker.InitialDirectory = $folder.Replace("/", "\") }
    # ToList hands back its list as one object: assigned first, so that piping it goes item by item.
    $preselected = ToList (Field $spec "files")
    # several files are preselected the way the picker writes a multiple selection: each name quoted
    if ($preselected.Count -eq 1) { $picker.FileName = [string]$preselected[0] }
    if ($preselected.Count -gt 1) { $picker.FileName = ($preselected | ForEach-Object { '"' + [string]$_ + '"' }) -join " " }
    $filter = Field $spec "filter"
    $extensions = ToList (Field $filter "extensions")
    $patterns = ($extensions | ForEach-Object { "*." + [string]$_ }) -join ";"
    if ($patterns) { $picker.Filter = "{0} ({1})|{1}" -f [string](Field $filter "name"), $patterns }
    $owner.Show()
    $owner.Activate()
    $chosen = @()
    if ($picker.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { $chosen = @($picker.FileNames) }
    $owner.Close()
    Write-Response @{ files = $chosen }
    exit 0
}

# ---------------------------------------------------------------------------------------------------- settings
$req = Read-Json $Request
$labels = Field $req "labels"
$version = [string](Field $req "version")
$runId = Field $req "runId"   # echoed, so the plug-in never takes another run's answer for this one
$instruments = ToList (Field $req "instruments")
$selected = ToList (Field $req "selected")
$noteheads = ToList (Field $req "noteheads")
$shapes = ToList (Field $req "shapes")
$modes = ToList (Field $req "modes")
$kinds = ToList (Field $req "kinds")
$majority = Field $req "colours"
$headIds = @($noteheads | ForEach-Object { [string](Field $_ "id") })
$headNames = @($noteheads | ForEach-Object { [string](Field $_ "name") })

$form = New-Form ([string](Field $req "title"))
$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.ColumnCount = 1
$main.AutoSize = $true
$main.Padding = New-Object System.Windows.Forms.Padding 12

$main.Controls.Add((New-Label ([string](Field $labels "instruments")) $true))
# One row per instrument: chart it or not, and how its part is written (Lua cannot tell; hbuc/transpose.lua).
$writtenHandbells = [string](Field $labels "writtenHandbells")
$writtenAtPitch = [string](Field $labels "writtenAtPitch")
$table = New-Object System.Windows.Forms.DataGridView
$table.Font = $form.Font   # before its rows are measured: a control takes the form's font only once added
$table.AllowUserToAddRows = $false
$table.AllowUserToDeleteRows = $false
$table.AllowUserToResizeRows = $false
$table.AllowUserToResizeColumns = $false
$table.AllowUserToOrderColumns = $false
$table.RowHeadersVisible = $false
$table.MultiSelect = $false
$table.EditMode = "EditOnEnter"
$table.BackgroundColor = [System.Drawing.SystemColors]::Window
$table.BorderStyle = "FixedSingle"
# No highlighted cell: the table is a set of choices, not a selection.
$table.DefaultCellStyle.SelectionBackColor = [System.Drawing.SystemColors]::Window
$table.DefaultCellStyle.SelectionForeColor = [System.Drawing.SystemColors]::WindowText
$table.ColumnHeadersHeightSizeMode = "DisableResizing"
$table.ColumnHeadersHeight = $form.Font.Height + (Px 10)
$table.RowTemplate.Height = $form.Font.Height + (Px 10)
$chartColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$chartColumn.HeaderText = [string](Field $labels "chartColumn")
$chartColumn.Width = Px 56
$nameColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$nameColumn.HeaderText = [string](Field $labels "instrumentColumn")
$nameColumn.ReadOnly = $true
$nameColumn.Width = Px 220
$writtenColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
$writtenColumn.HeaderText = [string](Field $labels "writtenHeader")
[void]$writtenColumn.Items.Add($writtenHandbells)
[void]$writtenColumn.Items.Add($writtenAtPitch)
$writtenColumn.DisplayStyle = "ComboBox"
$writtenColumn.Width = Px 300
$writtenColumn.MinimumWidth = $writtenColumn.Width
$writtenColumn.AutoSizeMode = "Fill"   # takes the scroll bar's room when there is no scroll bar
foreach ($c in @($chartColumn, $nameColumn, $writtenColumn)) {
    $c.SortMode = "NotSortable"
    [void]$table.Columns.Add($c)
}
$atPitch = ToList (Field $req "atPitch")
# Case-sensitive (-ccontains), as Lua compares names: "Handbells" and "HANDBELLS" are two players.
foreach ($name in $instruments) {
    $written = if ($atPitch -ccontains $name) { $writtenAtPitch } else { $writtenHandbells }
    [void]$table.Rows.Add(($selected -ccontains $name), [string]$name, $written)
}
# Eight rows show at most, then the table scrolls; the width leaves room for the scroll bar either way.
$shown = [Math]::Min(8, [Math]::Max(3, $instruments.Count))
$tableWidth = $chartColumn.Width + $nameColumn.Width + $writtenColumn.Width +
    [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + (Px 3)
$tableHeight = $table.ColumnHeadersHeight + $shown * $table.RowTemplate.Height + (Px 3)
$tableSize = New-Object System.Drawing.Size $tableWidth, $tableHeight
# The layout table sizes rows by each control's preferred size, which for a grid is too small: hold it open.
$table.MinimumSize = $tableSize
$table.Size = $tableSize
# A tick or a "Written as" choice counts at once, not only when the cell is left.
$table.Add_CurrentCellDirtyStateChanged({
    if ($table.IsCurrentCellDirty) { [void]$table.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
})
# One click opens a "Written as" choice, rather than one to enter the cell and another to open it.
$table.Add_CellClick({
    param($s, $e)
    if ($e.ColumnIndex -eq 2 -and $e.RowIndex -ge 0 -and $table.BeginEdit($true)) {
        $box = $table.EditingControl
        if ($box -is [System.Windows.Forms.ComboBox]) { $box.DroppedDown = $true }
    }
})
$table.Add_DataError({ param($s, $e) $e.ThrowException = $false })
function Get-RowsNamed([int]$column, $value) {
    return ,@($table.Rows | Where-Object { $_.Cells[$column].Value -eq $value } | ForEach-Object { [string]$_.Cells[1].Value })
}
$main.Controls.Add($table)

$chartsRow = New-Object System.Windows.Forms.FlowLayoutPanel
$chartsRow.AutoSize = $true
$chartsRow.Controls.Add((New-Label ([string](Field $labels "charts")) $true))
$modeBox = New-Combo $modes 300
$modeBox.SelectedItem = [string](Field $req "mode")
if ($modeBox.SelectedIndex -lt 0 -and $modeBox.Items.Count -gt 0) { $modeBox.SelectedIndex = 0 }
$chartsRow.Controls.Add($modeBox)
$main.Controls.Add($chartsRow)
# Charting one instrument apart is the same as charting it combined.
$updateMode = { $modeBox.Enabled = ((Get-RowsNamed 0 $true).Count -gt 1) }
$table.Add_CellValueChanged($updateMode)
& $updateMode

$newPage = New-Object System.Windows.Forms.CheckBox
$newPage.UseMnemonic = $false
$newPage.Text = [string](Field $labels "newPage")
$newPage.AutoSize = $true
$newPage.Checked = (Field $req "newPage") -ne $false
$main.Controls.Add($newPage)

$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.ColumnCount = 3
$grid.AutoSize = $true
$grid.Margin = New-Object System.Windows.Forms.Padding 0, 8, 0, 0
$grid.Controls.Add((New-Label ""), 0, 0)
$grid.Controls.Add((New-Label ([string](Field $labels "noteheadHeader")) $true), 1, 0)
$grid.Controls.Add((New-Label ([string](Field $labels "shapeHeader")) $true), 2, 0)
$headBoxes = @{}
$shapeBoxes = @{}
$colourBoxes = @{}
$row = 1
foreach ($k in $kinds) {
    $kind = [string](Field $k "kind")
    $grid.Controls.Add((New-Label ([string](Field $k "label"))), 0, $row)
    $head = New-Combo $headNames 260
    $at = [Array]::IndexOf($headIds, [string](Field $k "head"))
    $head.SelectedIndex = [Math]::Max(0, $at)
    $head.Tag = $kind
    $grid.Controls.Add($head, 1, $row)
    $shape = New-Combo $shapes 160
    $shape.SelectedItem = [string](Field $k "shape")
    if ($shape.SelectedIndex -lt 0) { $shape.SelectedIndex = 0 }
    $grid.Controls.Add($shape, 2, $row)
    $headBoxes[$kind] = $head
    $shapeBoxes[$kind] = $shape
    $row++
}

$colourGrid = New-Object System.Windows.Forms.TableLayoutPanel
$colourGrid.ColumnCount = 2
$colourGrid.AutoSize = $true
$colourGrid.Margin = New-Object System.Windows.Forms.Padding 0, 8, 0, 0
$row = 0
foreach ($k in $kinds) {
    $label = Field $k "colourLabel"
    if ($null -ne $label) {
        $kind = [string](Field $k "kind")
        $colourGrid.Controls.Add((New-Label ([string]$label)), 0, $row)
        $box = New-Object System.Windows.Forms.TextBox
        $box.Width = Px 120
        $value = Field $k "colour"
        if ($null -ne $value) { $box.Text = [string]$value }
        $colourGrid.Controls.Add($box, 1, $row)
        $colourBoxes[$kind] = $box
        $row++
    }
}
# Picking a notehead puts the colour most of its notes carry into that instrument's colour field.
foreach ($kind in @($colourBoxes.Keys)) {
    $headBoxes[$kind].Add_SelectedIndexChanged({
        $id = $headIds[$this.SelectedIndex]
        $colour = Field $majority $id
        $colourBoxes[$this.Tag].Text = if ($null -ne $colour) { [string]$colour } else { "" }
    })
}
$main.Controls.Add($grid)
$main.Controls.Add($colourGrid)

$remove = New-Object System.Windows.Forms.CheckBox
$remove.UseMnemonic = $false
$remove.Text = [string](Field $labels "remove")
$remove.AutoSize = $true
$remove.Margin = New-Object System.Windows.Forms.Padding 3, 10, 3, 3
$main.Controls.Add($remove)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.FlowDirection = "RightToLeft"
$buttons.AutoSize = $true
$buttons.Dock = "Fill"
$buttons.Margin = New-Object System.Windows.Forms.Padding 0, 10, 0, 0
$okButton = New-Button ([string](Field $labels "ok")) ([System.Windows.Forms.DialogResult]::OK)
$cancelButton = New-Button ([string](Field $labels "cancel")) ([System.Windows.Forms.DialogResult]::Cancel)
$buttons.Controls.Add($okButton)
$buttons.Controls.Add($cancelButton)
$note = New-Label ([string](Field $labels "saveNote"))
$note.ForeColor = [System.Drawing.SystemColors]::GrayText
$buttons.Controls.Add($note)
$main.Controls.Add($buttons)

$form.Controls.Add($main)
$form.AcceptButton = $okButton
$form.CancelButton = $cancelButton
# The first focus goes to OK, not the table: the table keeps Enter for moving down a row, so Enter would not press OK.
$form.ActiveControl = $okButton

$result = $form.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Response @{ version = $version; runId = $runId; cancelled = $true }
    exit 0
}
$heads = @{}
$chosenShapes = @{}
$colours = @{}
foreach ($kind in @($headBoxes.Keys)) {
    $heads[$kind] = $headIds[$headBoxes[$kind].SelectedIndex]
    $chosenShapes[$kind] = [string]$shapeBoxes[$kind].SelectedItem
}
foreach ($kind in @($colourBoxes.Keys)) { $colours[$kind] = $colourBoxes[$kind].Text }
Write-Response @{
    version = $version
    runId = $runId
    cancelled = $false
    instruments = Get-RowsNamed 0 $true
    atPitch = Get-RowsNamed 2 $writtenAtPitch
    mode = [string]$modeBox.SelectedItem
    newPage = [bool]$newPage.Checked
    heads = $heads
    shapes = $chosenShapes
    colours = $colours
    remove = [bool]$remove.Checked
}
exit 0
