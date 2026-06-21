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
    public List<double> Angle   = new List<double>();
    public List<double> Speed   = new List<double>();
    public List<double> OrbitX  = new List<double>();
    public List<double> OrbitY  = new List<double>();
    public List<double> CX      = new List<double>();
    public List<double> CY      = new List<double>();

    public void Add(PictureBox pb, double angle, double speed, double ox, double oy, double cx, double cy) {
        Viruses.Add(pb);
        Angle.Add(angle);
        Speed.Add(speed);
        OrbitX.Add(ox);
        OrbitY.Add(oy);
        CX.Add(cx);
        CY.Add(cy);
    }

    public void MoveAll() {
        for (int i = 0; i < Viruses.Count; i++) {
            Angle[i] += Speed[i];
            int nx = (int)(CX[i] + Math.Cos(Angle[i]) * OrbitX[i]) - Viruses[i].Width / 2;
            int ny = (int)(CY[i] + Math.Sin(Angle[i]) * OrbitY[i]) - Viruses[i].Height / 2;
            Viruses[i].Left = nx;
            Viruses[i].Top  = ny;
        }
    }
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing

# ── Загрузка ресурсов ──────────────────────────────────────────────────────────
$script:imgPath  = "$env:TEMP\virus_$(Get-Random).png"
$script:songPath = "$env:TEMP\vashsin_$(Get-Random).mp3"

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
    $script:REST, $script:REST, $script:REST, $script:REST, $script:NREST,
    $script:REST, $script:REST, $script:REST, $script:REST, $script:NREST
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
$script:phase2  = $false   # флаг: рисовать ли колесо

# ── Phase1 состояние ───────────────────────────────────────────────────────────
$script:totalArea  = [long]0
$script:spawnedPBs = [System.Collections.Generic.List[System.Windows.Forms.PictureBox]]::new()
$script:vm         = $null
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

# ── Paint: рисуем только в Phase2 ─────────────────────────────────────────────
$script:panel.Add_Paint({
    param($s, $e)
    if (-not $script:phase2) { return }

    $g = $e.Graphics
    $g.SmoothingMode     = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAlias'
    $W = $script:panel.Width; $H = $script:panel.Height

    # Фон
    $g.DrawImage($script:virusImg, 0, 0, $W, $H)

    $r  = [int]([Math]::Min($W,$H) * 0.26)
    $cx = [int]($W/2); $cy = [int]($H/2)
    $x  = $cx-$r;  $y = $cy-$r;  $d = $r*2

    # Тень
    $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(130,0,0,0))
    $g.FillEllipse($sh, $x+8, $y+8, $d, $d); $sh.Dispose()

    # Секторы
    for ($n=0; $n -lt $script:N; $n++) {
        $br = New-Object System.Drawing.SolidBrush($script:clr[$n])
        $g.FillPie($br,$x,$y,$d,$d,[float]($script:a+$n*$script:sweep),[float]$script:sweep)
        $br.Dispose()
    }

    # Линии
    $wp = New-Object System.Drawing.Pen([System.Drawing.Color]::White,[float]2)
    for ($n=0; $n -lt $script:N; $n++) {
        $g.DrawPie($wp,$x,$y,$d,$d,[float]($script:a+$n*$script:sweep),[float]$script:sweep)
    }
    $wp.Dispose()
    $wp2 = New-Object System.Drawing.Pen([System.Drawing.Color]::White,[float]5)
    $g.DrawEllipse($wp2,$x,$y,$d,$d); $wp2.Dispose()

    # Метки
    $fn = New-Object System.Drawing.Font('Arial',11,[System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $ts = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150,0,0,0))
    for ($n=0; $n -lt $script:N; $n++) {
        $ma = ($script:a + $n*$script:sweep + $script:sweep/2) * [Math]::PI / 180
        $tx = [float]($cx + [Math]::Cos($ma)*$r*0.68)
        $ty = [float]($cy + [Math]::Sin($ma)*$r*0.68)
        $g.DrawString($script:lbl[$n],$fn,$ts,$tx+1,$ty+1,$sf)
        $g.DrawString($script:lbl[$n],$fn,$tb,$tx,$ty,$sf)
    }
    $fn.Dispose(); $sf.Dispose(); $tb.Dispose(); $ts.Dispose()

    # Центр
    $cr = [int]($r*0.10)
    $cb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($cb,$cx-$cr,$cy-$cr,$cr*2,$cr*2); $cb.Dispose()

    # Стрелка
    $as = [float]($r*0.14)
    $pts = @(
        [System.Drawing.PointF]::new([float]$cx,             [float]($cy+$r-$as*0.5)),
        [System.Drawing.PointF]::new([float]($cx-$as*0.7),   [float]($cy+$r+$as*0.8)),
        [System.Drawing.PointF]::new([float]($cx+$as*0.7),   [float]($cy+$r+$as*0.8))
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

# ── Вспомогательная функция: добавить вирусы на орбиту ────────────────────────
function Add-OrbitViruses($count, $speedMult) {
    $W = $script:panel.Width; $H = $script:panel.Height
    $cxF = [double]($W/2); $cyF = [double]($H/2)
    # базовая угловая скорость: ~1.5 оборота за 20 сек при 16мс/тик
    $baseSpd = [double](1.5 * 2 * [Math]::PI / (20000.0/16.0))
    for ($i=0; $i -lt $count; $i++) {
        $sz = $rng.Next(50,86)
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Width = $sz; $pb.Height = $sz
        $pb.SizeMode = 'StretchImage'
        $pb.Image = $script:virusImg
        $script:panel.Controls.Add($pb)
        $ox  = [double]($rng.Next(100, [int]($W*0.46)))
        $oy  = [double]($rng.Next(80,  [int]($H*0.46)))
        $ang = [double]($rng.NextDouble() * 2 * [Math]::PI)
        $spd = [double]($baseSpd * $speedMult * (0.7 + $rng.NextDouble()*0.6))
        if ($rng.Next(2) -eq 0) { $spd = -$spd }
        $script:vm.Add($pb, $ang, $spd, $ox, $oy, $cxF, $cyF)
    }
}

# ── StartPhase2 ───────────────────────────────────────────────────────────────
function StartPhase2 {
    if ($script:phase2) { return }   # защита от двойного вызова
    $tSpawn.Stop(); $tFallback.Stop()

    # Убрать Phase1 вирусы
    foreach ($pb in $script:spawnedPBs) {
        $script:panel.Controls.Remove($pb)
        $pb.Dispose()
    }
    $script:spawnedPBs.Clear()

    $script:vm = New-Object VirusOrbit
    $script:phase2 = $true

    Add-OrbitViruses 40 1.0

    $t1.Start(); $tStop.Start(); $tClose.Start()
}

# ── Таймер Phase1: спавн крупных вирусов ──────────────────────────────────────
$tSpawn = New-Object System.Windows.Forms.Timer
$tSpawn.Interval = 30   # быстрый спавн
$tSpawn.Add_Tick({
    $W = $script:panel.Width; $H = $script:panel.Height
    # Крупные вирусы: 160-800px (в ~4 раза больше чем раньше)
    $sz = $rng.Next(160, 801)
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Width  = $sz; $pb.Height = $sz
    $pb.SizeMode = 'StretchImage'
    $pb.Image  = $script:virusImg
    $pb.Left   = $rng.Next(-$sz/2, $W)
    $pb.Top    = $rng.Next(-$sz/2, $H)
    $script:panel.Controls.Add($pb)
    $script:spawnedPBs.Add($pb)
    $script:totalArea += [long]($sz * $sz)
    if ($script:totalArea -ge [long]($W * $H)) {
        StartPhase2
    }
})

$tFallback = New-Object System.Windows.Forms.Timer
$tFallback.Interval = 4000   # 4 сек максимум на Phase1
$tFallback.Add_Tick({
    StartPhase2
})

# ── Таймер Phase2: анимация ────────────────────────────────────────────────────
$t1 = New-Object System.Windows.Forms.Timer
$t1.Interval = 16
$t1.Add_Tick({
    $script:ticks++
    $script:vm.MoveAll()
    if (-not $script:stopped) {
        $ms = $script:ticks * 16
        if ($ms -lt 10000) {
            $script:a = ($script:a + 12) % 360
        } else {
            $prog = [Math]::Min(1.0, ($ms-10000)/10000.0)
            $script:a = ($script:a + (12*(1-$prog) + 0.2*$prog)) % 360
        }
    }
    $script:panel.Invalidate()
})

# ── tStop: результат + быстрые вирусы ─────────────────────────────────────────
$tStop = New-Object System.Windows.Forms.Timer
$tStop.Interval = 20000
$tStop.Add_Tick({
    $tStop.Stop()
    $script:stopped = $true
    $norm = ((90 - $script:a) % 360 + 360) % 360
    $idx  = [int]([Math]::Floor($norm / $script:sweep)) % $script:N
    $script:result = $script:lbl[$idx]
    Add-OrbitViruses 40 3.0   # в 3 раза быстрее
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
    $tSpawn.Start()
    $tFallback.Start()
})

[void]$script:form.ShowDialog()
