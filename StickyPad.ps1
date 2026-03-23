Param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

enum Cmd {
    TERM
    OPEN
    START
    LATEST
    EDIT
    FUNC
}

$Script:Tool = @{}

$imgSame           = "$Env:APPDATA + '\Zoomvd\data\Emojis\1f988.svg'"   # [推定: パスはやや不鮮明]
$picH              = 40
$offsetX           = 8
$offsetY           = 0
$targethwnd        = 0
$position          = 'Right'
$positionY         = 'Top'
$opacity           = 1.0
$menu              = Join-Path $PSScriptRoot 'menu.ps1'
$defaultMode       = 'Sticky'
$script:TextBoxPos = 'Below'   # 'Below' or 'Inside'
$script:StickyMode = $true

. $menu

Add-Type @"
using System;
using System.Runtime.InteropServices;

public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public struct POINT {
    public int x;
    public int y;
}

public delegate void WinEventDelegate(
    IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
    int idObject, int idChild, uint dwEventThread, uint dwmsEventTime
);

public class WinAPI {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
    [DllImport("user32.dll")] public static extern bool EnableWindow(IntPtr hWnd, long flags);
    [DllImport("user32.dll")] public static extern bool PhysicalToLogicalPointForPerMonitorDPI(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax,
        IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc,
        uint idProcess, uint idThread, uint dwFlags);
    [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hWinEventHook);
}
"@


# setPosition 用 事前確保（New-Object を毎回生成しないためのキャッシュ）
$Script:rc     = New-Object RECT
$Script:prevRc = New-Object RECT
$Script:pt     = New-Object POINT

function launch($txt) {
    ([string]$key, [string[]]$keys) = $txt.split(" ")
    if ($key -eq $null) {
        exit
    }
    elseif ($Script:List.ContainsKey($key)) {
        if ($List[$key] -is [Hashtable]) {
            if ($keys.length -gt 0 -and $Script:List[$key].ContainsKey([string]$keys[0])) {
                ($cmd, [string[]]$opt) = $Script:List[$key][[string]$keys[0]]
            }
            else {
                ($cmd, [string[]]$opt) = $Script:List[$key][@($List[$key].keys | sort)[0]]
            }
        }
        else {
            ($cmd, [string[]]$opt) = $Script:List[$key]
        }

        # コマンドの省略
        if ($cmd -is [String]) {
            if ($opt.length -gt 0) {
                $opt = @($cmd) + $opt
            }
            else {
                $opt = @($cmd)
            }
            $cmd = [Cmd]::OPEN
        }

        switch ($cmd) {
            ([Cmd]::FUNC) {
                & $opt[0] $keys
            }
            ([Cmd]::EDIT) {
                if( $opt.length -eq 0 ){
                    Start-Process -FilePath $Script:Tool[([Cmd]$cmd)]
                }else{
                    Start-Process -FilePath $Script:Tool[[Cmd]$cmd] -ArgumentList $opt
                }
            }
            ([Cmd]::TERM) {
                if( $opt.length -eq 0 ){
                    Start-Process -FilePath $Script:Tool[[Cmd]$cmd]
                }else{
                    Start-Process -FilePath $Script:Tool[[Cmd]$cmd] -ArgumentList $opt
                }
            }
            ([Cmd]::OPEN) {
                if ($opt[0] -like "*.ps1") {
                    Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $opt -NoNewWindow
                }
                else {
                    if ($keys.length -gt 0) {
                        Start $opt[0] -ArgumentList $keys
                    }
                    else {
                        if ($opt.length -eq 1) {
                            Start $opt[0]
                        }
                        else {
                            Start $opt[0] -ArgumentList $opt[1..$opt.length]
                        }
                    }
                }
            }
            ([Cmd]::START) {
                if ($keys.length -gt 0) {
                    Start-Process $opt[0] -ArgumentList $keys
                }
                else {
                    Start-Process $opt[0]
                }
            }
            ([Cmd]::LATEST) {
                Start ((Get-ChildItem $opt[0] | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName)
            }
        }
    }
    else {
        & $Fallback $txt
    }
}

function setDesktop {
    $screen = [System.Windows.Forms.Screen]::FromControl($Form)

    if ($Script:PositionY -ieq 'top' -and $Script:Position -ieq 'left') {
        $x = $screen.WorkingArea.X
        $y = $screen.WorkingArea.Y
    }
    elseif ($Script:PositionY -ieq 'bottom' -and $Script:Position -ieq 'left') {
        $x = $screen.WorkingArea.X
        $y = $screen.WorkingArea.Y + $screen.WorkingArea.Height - $Form.Height
    }
    elseif ($Script:PositionY -ieq 'bottom' -and $Script:Position -ieq 'right') {
        $x = $screen.WorkingArea.X + $screen.WorkingArea.Width - $Form.Width
        $y = $screen.WorkingArea.Y + $screen.WorkingArea.Height - $Form.Height
    }
    else {
        $x = $screen.WorkingArea.X + $screen.WorkingArea.Width - $Form.Width
        $y = $screen.WorkingArea.Y
    }

    $Form.Top  = $y
    $Form.Left = $x
}

function setPosition($hwnd) {
    if (!$Script:StickyMode) { return }

    [void][WinAPI]::DwmGetWindowAttribute($hwnd, 9, [ref]$Script:rc, 16)  # DWMWA_EXTENDED_FRAME_BOUNDS(9)

    if ($Script:rc.Right - $Script:rc.Left -le 160) { return }

    # ウィンドウが動いていない場合はスキップ
    if ($Script:rc.Left   -eq $Script:prevRc.Left   -and
        $Script:rc.Top    -eq $Script:prevRc.Top    -and
        $Script:rc.Right  -eq $Script:prevRc.Right  -and
        $Script:rc.Bottom -eq $Script:prevRc.Bottom) { return }

    $Script:prevRc.Left   = $Script:rc.Left
    $Script:prevRc.Top    = $Script:rc.Top
    $Script:prevRc.Right  = $Script:rc.Right
    $Script:prevRc.Bottom = $Script:rc.Bottom

    if ($Script:Position -ieq 'Left') {
        $x = $Script:rc.Left
    }
    else {
        $x = $Script:rc.Right
    }

    if ($Script:PositionY -ieq 'Bottom') {
        $y = $Script:rc.Bottom
    }
    else {
        $y = $Script:rc.Top
    }

    $Script:pt.x = $x
    $Script:pt.y = $y
    [WinAPI]::PhysicalToLogicalPointForPerMonitorDPI(0, [ref]$Script:pt)
    $x = $Script:pt.x
    $y = $Script:pt.y

    if ($Script:Position -ieq 'Left') {
        $x = $x - $Script:OffsetX
    }
    else {
        $x = $x - $Form.Width + $Script:OffsetX
    }

    if ($Script:PositionY -ieq 'Bottom') {
        $y = $y - $Script:picH - $Script:OffsetY
    }
    else {
        $y = $y - $Script:picH + $Script:OffsetY
    }

    if ($Form.Top -ne $y -or $Form.Left -ne $x) {
        $Form.Top = $y
        $Form.Left = $x
        $Form.TopMost = $true
        hideTextBox
    }
}

function showTextBox {
    $TextBox.Width = $Form.Width
    if ($Script:TextBoxPos -ieq 'Below') {
        $TextBox.Location = New-Object System.Drawing.Point(0, $Script:picH)
        $Form.Height = $Script:picH + $TextBox.Height
    }
    else {
        $TextBox.Location = New-Object System.Drawing.Point(0, $Script:picH - $TextBox.Height)
    }

    $TextBox.BringToFront()
    $TextBox.Visible = $true
    $TextBox.Select()
}

function hideTextBox {
    $TextBox.Visible = $false
    $Form.Height = $Script:picH
}

function loadImage($key, $size=40, $rotate='RotateNoneFlipNone') {
    $Script:Rotate    = $rotate
    $Script:picH      = $size
    $Script:Position  = 'Right'
    $Script:PositionY = 'Top'
    $mode             = 'Default'

    try {
        if ($key -ne '' -and $Script:Images.Contains($key)) {
            $Script:OffsetX = $Script:Images[$key][0]
            $Script:OffsetY = $Script:Images[$key][1]

            if (Test-Path $Script:Images[$key][2]) {
                $fs = New-Object System.IO.FileStream($Script:Images[$key][2], [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
            }
            else {
                $png = [Convert]::FromBase64String($Script:Images[$key][2])
                $fs  = New-Object System.IO.MemoryStream($png, 0, $png.Length)
            }

            if ($Script:Images[$key][3] -ne $null -and $Script:Images[$key][3] -ne '') {
                if ($Script:Images[$key][3] -imatch 'Rotate-(?<val>[a-zA-Z0-9]+)') { $Script:Rotate   = $matches.val }
                if ($Script:Images[$key][3] -imatch 'Mode-(?<val>[a-zA-Z0-9]+)')   { $mode            = $matches.val }
                if ($Script:Images[$key][3] -imatch 'Size-(?<val>[0-9]+)')         { $Script:picH     = [int]$matches.val }
                if ($Script:Images[$key][3] -imatch 'Bottom')                      { $Script:PositionY = 'Bottom' }
            }

            $Script:ImageFile = $Script:Images[$key][2]
        }
        else{
            if ($key -ne '' ){ $Script:ImageFile = $key }
            $Script:OffsetX = -4
            $Script:OffsetY = 4
            $fs = New-Object System.IO.FileStream($Script:ImageFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        }
    }
    catch {
        $fs = New-Object System.IO.FileStream($ImgSame, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        $Script:OffsetX = 10
        $Script:OffsetY = -24
    }

    $img = [System.Drawing.Image]::FromStream($fs)
    $fs.Dispose()

    $gdp = $null
    hideTextBox
    try {
        $img.RotateFlip($Script:Rotate)
        $Form.Height = $Script:picH
        $Form.Width  = [int]($Script:picH * ($img.Width / $img.Height))

        $dst = New-Object System.Drawing.Bitmap($Form.Width, $Form.Height)
        $gdp = [System.Drawing.Graphics]::FromImage($dst)
        $gdp.InterpolationMode = $mode
        $gdp.DrawImage($img, 0, 0, $Form.Width, $Form.Height)
        if ($Pict.Image) { $Pict.Image.Dispose() }
        $Pict.Image = $dst
        $Pict.SizeMode = 'Normal'
    }
    finally {
        $img.Dispose()
        if ($gdp) { $gdp.Dispose() }
    }

    setPosition($Script:targethwnd)
}

# ---- Form --------------------------------------------------------
$Form = New-Object System.Windows.Forms.Form
$Form.MaximizeBox    = $false
$Form.MinimizeBox    = $false
$Form.ControlBox     = $false
$Form.ShowIcon       = $false
$Form.Text           = ''
$Form.ShowInTaskbar  = $false
$Form.FormBorderStyle = 'FixedToolWindow'
$Form.SizeGripStyle  = 'Hide'
$Form.Width          = $picH
$Form.Height         = $picH
$Form.BackColor      = '#010101'
$Form.TransparencyKey = $Form.BackColor
$Form.StartPosition  = 'Manual'
$Form.TopMost        = $true
$Form.AllowDrop      = $true
$Form.Add_Deactivate({ hideTextBox })
$Form.Add_Activated({
    $TextBox.Text = ''
    showTextBox
    $Form.Opacity = $Script:Opacity
})
$Form.Add_Load({ $Form.FormBorderStyle = 'None' })
$Form.Add_MouseDown({
    if ([System.Windows.Forms.Control]::MouseButtons -eq 'Left') {
        showTextBox
        $Form.Opacity = $Script:Opacity
    }
})

$Form.Add_DragEnter({ $_.Effect = 'All' })
$Form.Add_DragDrop({
    $name = @($_.Data.GetData("FileDrop"))
    loadImage $name[0]
})

# ---- TextBox -----------------------------------------------------
$TextBox = New-Object System.Windows.Forms.TextBox
$TextBox.BorderStyle   = 'None'
$TextBox.Font          = New-Object System.Drawing.Font("Consolas", 10)
$TextBox.AcceptsReturn = $false
$TextBox.BackColor     = '#c0c0c0'
$TextBox.Dock          = 'None'
$TextBox.Visible       = $false

$TextBox.Add_KeyDown({
    if ($_.KeyCode -eq 'Return') {
        if ($TextBox.Text -ieq 'quit') {
            $Form.Close()
        }
        elseif ($TextBox.Text -like ':*') {
            if ($TextBox.Text -eq ':reload') {
                . $menu
            }
            elseif ($TextBox.Text -match ':(?<val>(left|right))') {
                $Script:Position = $matches.val
            }
            elseif ($TextBox.Text -match ':(?<val>(top|bottom))') {
                $Script:PositionY = $matches.val
            }
            elseif ($TextBox.Text -match ':size=(?<num>[0-9]+)') {
                if ([int]$matches.num -ge 10) {
                    $Script:picH = [int]$matches.num
                    loadImage '' $Script:picH $Script:Rotate
                }
            }
            elseif ($TextBox.Text -match ':flip=?(?<xy>[xyone])') {
                $Script:Rotate = 'RotateNoneFlip' + $matches.xy.ToUpper()
                loadImage '' $Script:picH $Script:Rotate
            }
            elseif ($TextBox.Text -match ':off(set)?y=(?<num>[-0-9]+)') {
                $Script:OffsetY = [int]$matches.num
            }
            elseif ($TextBox.Text -match ':off(set)?x=(?<num>[-0-9]+)') {
                $Script:OffsetX = [int]$matches.num
            }
            elseif ($TextBox.Text -match ':opacity=(?<num>[.0-9]+)') {
                $Script:Opacity = [double]$matches.num
            }
            elseif ($TextBox.Text -match ':tbpos=(?<val>(below|inside))') {
                $Script:TextBoxPos = $matches.val
            }

            if ($menuDesktop.Checked) {
                setDesktop
            }
            else {
                setPosition($Script:targethwnd)
            }
        }
        elseif ($TextBox.Text -like '!*') {
            if ($TextBox.Text -match '!disable') {
                [void][WinAPI]::EnableWindow($Script:targethwnd, 0)
            }
            elseif ($TextBox.Text -match '!enable') {
                [void][WinAPI]::EnableWindow($Script:targethwnd, 1)
            }
            elseif ($TextBox.Text -match '!alpha=(?<num>[0-9]+)') {
                if ($matches.num -eq 255) {
                    $ws = [WinAPI]::GetWindowLong($Script:targethwnd, -20)
                    [WinAPI]::SetWindowLong($Script:targethwnd, -20, ($ws -band (-bnot 0x80000)))
                }
                else {
                    $ws = [WinAPI]::GetWindowLong($Script:targethwnd, -20)
                    [WinAPI]::SetWindowLong($Script:targethwnd, -20, ($ws -bor 0x80000))
                    [void][WinAPI]::SetLayeredWindowAttributes($Script:targethwnd, 0, $matches.num, 2)
                }
            }
        }
        elseif ($TextBox.Text -ne '') {
            launch $TextBox.Text
        }

        $TextBox.Text = ''
    }
})
$Form.Controls.Add($TextBox)

# ---- PictureBox --------------------------------------------------
$Pict = New-Object System.Windows.Forms.PictureBox
$Pict.Dock = 'Fill'
$Pict.Add_MouseDown({
    if ([System.Windows.Forms.Control]::MouseButtons -eq 'Left') {
        showTextBox
        $Form.Opacity = $Script:Opacity
    }
})
$Form.Controls.Add($Pict)

# ---- Context Menu ------------------------------------------------
$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip

$menuImg = New-Object System.Windows.Forms.ToolStripMenuItem
$menuImg.Text = '&Image'
[void]$ctxMenu.Items.Add($menuImg)
if ($Script:Images.Count -gt 0) {
    foreach ($i in $Script:Images.Keys) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem
        $mi.Text = $i
        $mi.Add_Click({ loadImage $this.Text })
        [void]$menuImg.DropDownItems.Add($mi)
        if ($Script:Images[$i][2] -like '%APPDATA%*') {
            $Script:Images[$i][2] = $Script:Images[$i][2].Replace('%APPDATA%', $Env:APPDATA)
        }
    }
}

$menuMode = New-Object System.Windows.Forms.ToolStripMenuItem
$menuMode.Text = '&Mode'
[void]$ctxMenu.Items.Add($menuMode)

$menuM1 = New-Object System.Windows.Forms.ToolStripMenuItem
$menuM1.Text = '&Sticky mode'
$menuM1.Add_Click({
    $Script:StickyMode = $true
    $menuM1.Checked = $true
    $menuDesktop.Checked = $false
})
[void]$menuMode.DropDownItems.Add($menuM1)

$menuDesktop = New-Object System.Windows.Forms.ToolStripMenuItem
$menuDesktop.Text = '&Desktop mode'
$menuDesktop.Add_Click({
    $Script:StickyMode = $false
    setDesktop
    $menuM1.Checked = $false
    $menuDesktop.Checked = $true
})
[void]$menuMode.DropDownItems.Add($menuDesktop)

if ($defaultMode -eq 'Desktop') {
    $Script:StickyMode = $false
    setDesktop
    $menuDesktop.Checked = $true
    $menuM1.Checked = $false
}
else {
    $menuM1.Checked = $true
    $menuDesktop.Checked = $false
}

$menuZoomY = New-Object System.Windows.Forms.ToolStripMenuItem
$menuZoomY.Text = '&ZoomY'
$menuZoomY.Add_Click({
    if ($Script:StickyMode) {
        $screen = [System.Windows.Forms.Screen]::FromControl($Form)
        $src = New-Object RECT
        [void][WinAPI]::GetWindowRect($Script:targethwnd, [ref]$src)
        [void][WinAPI]::MoveWindow($Script:targethwnd, $src.Left, ($screen.WorkingArea.Y + 1), ($src.Right - $src.Left), ($screen.WorkingArea.Height - 1), 1)
        setPosition($Script:targethwnd)
    }
})
[void]$ctxMenu.Items.Add($menuZoomY)

[void]$ctxMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$menuQuit = New-Object System.Windows.Forms.ToolStripMenuItem
$menuQuit.Text = '&Quit'
$menuQuit.Add_Click({ $Form.Close() })
[void]$ctxMenu.Items.Add($menuQuit)

$Form.ContextMenuStrip = $ctxMenu


# ---- WinEvent フック ---------------------------------------------

$EVENT_SYSTEM_FOREGROUND     = [uint32]0x0003  # フォアグラウンドウィンドウ変化
$EVENT_OBJECT_LOCATIONCHANGE = [uint32]0x800B  # ウィンドウ位置・サイズ変化
$WINEVENT_OUTOFCONTEXT       = [uint32]0x0000  # メッセージキュー経由（UI スレッドで処理）
$WINEVENT_SKIPOWNPROCESS     = [uint32]0x0002  # 自プロセスのイベントを除外

#
# フォアグラウンド変化: 追従対象ウィンドウを切り替える
# デリゲート参照を $Script: に保持し GC されないようにする
$Script:FgDelegate = [WinEventDelegate]{
    param([IntPtr]$hook,[uint32]$evt,[IntPtr]$hwnd,[int]$idObj,[int]$idChild,[uint32]$thread,[uint32]$time)

    if (-not $Script:StickyMode) { return }
    if ($hwnd -eq $Form.Handle) { return }

    $ws = [WinAPI]::GetWindowLong($hwnd, -16)
    # 0x10000000 WS_VISIBLE / 0x00C00000 WS_CAPTION
    if ((($ws -band 0x10000000) -eq 0) -or (($ws -band 0x00800000) -eq 0) -and (($ws -band 0x00040000) -eq 0)) {
        $Form.Opacity = 0.3
        return
    }

    $len = [WinAPI]::GetWindowTextLength($hwnd)
    if ($len -eq 0) {
        $Form.Opacity = 0.7
        return
    }

    $Script:targethwnd = $hwnd
    $Script:prevRc.Left = 0; $Script:prevRc.Top = 0
    $Script:prevRc.Right = 0; $Script:prevRc.Bottom = 0
    $Form.Opacity = $Script:Opacity
    setPosition($hwnd)
}

# ウィンドウ位置変化: 追従対象が動いたらフォームを追従させる
# idObj == 0 (OBJID_WINDOW) のみ処理し、スクロール等の内容変化は無視する
$Script:LocDelegate = [WinEventDelegate]{
    param([IntPtr]$hook,[uint32]$evt,[IntPtr]$hwnd,[int]$idObj,[int]$idChild,[uint32]$thread,[uint32]$time)

    if (-not $Script:StickyMode) { return }
    if ($hwnd -ne $Script:targethwnd) { return }
    if ($idObj -ne 0) { return }  # OBJID_WINDOW のみ

    setPosition($hwnd)
}

$Script:HookFg = [WinAPI]::SetWinEventHook(
    $EVENT_SYSTEM_FOREGROUND, $EVENT_SYSTEM_FOREGROUND,
    [IntPtr]::Zero, $Script:FgDelegate,
    0, 0, ($WINEVENT_OUTOFCONTEXT -bor $WINEVENT_SKIPOWNPROCESS))

$Script:HookLoc = [WinAPI]::SetWinEventHook(
    $EVENT_OBJECT_LOCATIONCHANGE, $EVENT_OBJECT_LOCATIONCHANGE,
    [IntPtr]::Zero, $Script:LocDelegate,
    0, 0, ($WINEVENT_OUTOFCONTEXT -bor $WINEVENT_SKIPOWNPROCESS))

# 終了時にフックを解除
$Form.Add_FormClosed({
    [WinAPI]::UnhookWinEvent($Script:HookFg)
    [WinAPI]::UnhookWinEvent($Script:HookLoc)
})

# ---- 起動 --------------------------------------------------------
loadImage @($Script:Images.Keys)[0]
[void]$Form.ShowDialog()
