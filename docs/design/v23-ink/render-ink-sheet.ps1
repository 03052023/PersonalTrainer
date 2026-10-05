# render-ink-sheet.ps1 — folha de conferência da direção Tinta e papel (DESIGN §14; docs/V23-UI-CONTRACT.md
# §4.1 item 9): sem simulador, é o único jeito de ver a flor em aguada, o ensō, a marca de tinta, a aguada
# de montanha, o cartão sobre papel e o contraste da paleta, todos com os MESMOS NÚMEROS do Swift
# (Theme.swift, FlowerView.swift, EnsoRingView.swift, InkMarkView.swift, MountainWashView.swift,
# PaperBackground.swift) — não é o mesmo motor de desenho (GDI+ aqui, Canvas/SwiftUI lá), então a
# conferência é de proporção e leitura, não de pixel a pixel.
#
# Geometria da pétala Brisa portada de docs/design/render-app-icon.ps1 (mesmos $Brisa.per); nada de
# Get-Random em lugar nenhum do script.
#
# Saídas: docs/design/v23-ink/ink-sheet.png (aparência clara) e ink-sheet-dark.png (escura).
#
# Uso: powershell -ExecutionPolicy Bypass -File docs/design/v23-ink/render-ink-sheet.ps1 [-OutDir <pasta>]
param([string]$OutDir = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($OutDir -eq '') { $OutDir = $here }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---------------- utilitários de cor (iguais a render-app-icon.ps1) ----------------
function HexColor([string]$hex, [int]$a = 255) {
  $h = $hex.TrimStart('#')
  [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16))
}
function WithAlpha($c, [int]$a) { [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function Mix($c1, $c2, [double]$t) {
  [System.Drawing.Color]::FromArgb(255, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t))
}
# Mesma fórmula de `Theme.mixedHex(_:_:fraction:)`: RGB simples, não perceptual.
function MixHex([string]$a, [string]$b, [double]$t) {
  $ca = HexColor $a; $cb = HexColor $b
  $r = Mix $ca $cb $t
  '#{0:X2}{1:X2}{2:X2}' -f $r.R, $r.G, $r.B
}
function Lin([double]$v) { $v = $v / 255.0; if ($v -le 0.04045) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) } }
function RelLum($c) { 0.2126 * (Lin $c.R) + 0.7152 * (Lin $c.G) + 0.0722 * (Lin $c.B) }
function Contrast($a, $b) { $la = RelLum $a; $lb = RelLum $b; ([Math]::Max($la,$lb) + 0.05) / ([Math]::Min($la,$lb) + 0.05) }
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF([single]$x, [single]$y) }
function Bez([double]$a, [double]$b, [double]$c, [double]$d, [double]$t) { $m = 1 - $t; $m*$m*$m*$a + 3*$m*$m*$t*$b + 3*$m*$t*$t*$c + $t*$t*$t*$d }
function BezD([double]$a, [double]$b, [double]$c, [double]$d, [double]$t) { $m = 1 - $t; 3*$m*$m*($b - $a) + 6*$m*$t*($c - $b) + 3*$t*$t*($d - $c) }
function Wob($list, [double]$t) { $s = 0.0; foreach ($w in $list) { $s += $w[0] * [Math]::Sin(2 * [Math]::PI * $w[1] * $t + $w[2]) }; $s }
function Prof([double]$t, [double]$tm, [double]$alpha, [double]$w0) {
  if ($t -le $tm) { $s = $t / $tm; return $w0 + (1 - $w0) * [Math]::Pow([Math]::Sin([Math]::PI / 2 * $s), $alpha) }
  $s = ($t - $tm) / (1 - $tm); [Math]::Sqrt([Math]::Max(0.0, 1 - $s * $s))
}
function New-RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = 2 * $r
  $p.AddArc([single]$x, [single]$y, [single]$d, [single]$d, 180, 90); $p.AddArc([single]($x + $w - $d), [single]$y, [single]$d, [single]$d, 270, 90)
  $p.AddArc([single]($x + $w - $d), [single]($y + $h - $d), [single]$d, [single]$d, 0, 90); $p.AddArc([single]$x, [single]($y + $h - $d), [single]$d, [single]$d, 90, 90)
  $p.CloseFigure(); $p
}

# ---------------- Theme.swift, portado (mesmos hexadecimais e nomes de HexPair) ----------------
$Theme = [ordered]@{
  background = @{ light = '#F4EEE4'; dark = '#191715' }
  surface = @{ light = '#FCF9F3'; dark = '#25211E' }
  textPrimary = @{ light = '#27221F'; dark = '#EEE7DC' }
  textSecondary = @{ light = '#635850'; dark = '#B2A595' }
  accent = @{ light = '#2B4D6B'; dark = '#A4BDD6' }
  onAccent = @{ light = '#FCF9F3'; dark = '#191715' }
  accentSoft = @{ light = '#DEE5EA'; dark = '#27313B' }
  inkMuted = @{ light = '#4A4139'; dark = '#CFC4B5' }
  line = @{ light = '#DAD1C4'; dark = '#3A332D' }
  goalHypertrophy = @{ light = '#8E3E2C'; dark = '#E09A82' }
  goalStrength = @{ light = '#6F5238'; dark = '#CDAA86' }
  goalEndurance = @{ light = '#3A6765'; dark = '#93C2BE' }
  goalLongevity = @{ light = '#50613F'; dark = '#AFC194' }
  goalCombat = @{ light = '#6C4862'; dark = '#CFA6C3' }
  health = @{ light = '#775816'; dark = '#D7B568' }
  flowerCenter = @{ light = '#E7D9C2'; dark = '#CDBEA4' }
}

# ---------------- geometria Brisa (idêntica a docs/design/render-app-icon.ps1 e a BrisaGeometry.swift) --
$Brisa = @{
  rot = -5; r0 = 70; tm = 0.62; alpha = 0.68; w0 = 0.0; asymK = 1.3
  centerR = 52; centerHarm = @(@(0.025, 2, 0.6), @(0.018, 3, 2.1))
  per = @(
    @{ L = 270; W = 97;  dAng = 0.0;  tilt = -11; b2 = 0.10; b3 = 0.26; lean = 0.06; asym = 0.12; wobP = @(,@(0.020, 1.6, 0.4)); wobM = @(,@(0.016, 2.1, 2.2)) },
    @{ L = 252; W = 103; dAng = 2.5;  tilt = -7;  b2 = 0.07; b3 = 0.18; lean = 0.03; asym = 0.09; wobP = @(,@(0.018, 1.9, 1.1)); wobM = @(,@(0.020, 1.4, 4.0)) },
    @{ L = 275; W = 95;  dAng = 1.0;  tilt = -14; b2 = 0.12; b3 = 0.30; lean = 0.07; asym = 0.14; wobP = @(,@(0.016, 2.3, 5.0)); wobM = @(,@(0.018, 1.7, 0.9)) },
    @{ L = 257; W = 101; dAng = -1.0; tilt = -8;  b2 = 0.08; b3 = 0.20; lean = 0.04; asym = 0.10; wobP = @(,@(0.020, 1.5, 3.3)); wobM = @(,@(0.015, 2.4, 1.8)) },
    @{ L = 264; W = 97;  dAng = -2.5; tilt = -12; b2 = 0.10; b3 = 0.25; lean = 0.06; asym = 0.12; wobP = @(,@(0.018, 2.0, 2.7)); wobM = @(,@(0.019, 1.8, 5.6)) }
  )
}
# índice = petalIndex (0 topo, sentido horário); nomes só para rótulos da folha.
$GoalNames = @('Longevidade', 'Hipertrofia', 'Força', 'Combate', 'Cardio')
$GoalTokens = @('goalLongevity', 'goalHypertrophy', 'goalStrength', 'goalCombat', 'goalEndurance')

function Get-Petal($sp, [double]$k) {
  $cnt = 120; $len0 = $sp.L; $halfW = $sp.W; $r0 = $sp.r0
  $q1 = $sp.b1 * $len0; $q2 = $sp.b2 * $len0; $q3 = $sp.b3 * $len0
  $tau = $sp.tilt * [Math]::PI / 180; $ct = [Math]::Cos($tau); $st = [Math]::Sin($tau)
  $angR = $sp.ang * [Math]::PI / 180; $ca = [Math]::Cos($angR); $sa = [Math]::Sin($angR)
  $arU = New-Object 'double[]' ($cnt + 1); $arV = New-Object 'double[]' ($cnt + 1); $arNU = New-Object 'double[]' ($cnt + 1); $arNV = New-Object 'double[]' ($cnt + 1)
  $arWP = New-Object 'double[]' ($cnt + 1); $arWM = New-Object 'double[]' ($cnt + 1)
  for ($j = 0; $j -le $cnt; $j++) {
    $tt = (1 - [Math]::Cos([Math]::PI * $j / $cnt)) / 2
    $su = Bez 0 ($len0/3) (2*$len0/3) $len0 $tt; $sv = Bez 0 $q1 $q2 $q3 $tt
    $du = BezD 0 ($len0/3) (2*$len0/3) $len0 $tt; $dv = BezD 0 $q1 $q2 $q3 $tt; $dl = [Math]::Sqrt($du*$du + $dv*$dv)
    $asymT = [Math]::Pow($tt, $sp.asymK)
    $arU[$j] = $su; $arV[$j] = $sv; $arNU[$j] = -$dv / $dl; $arNV[$j] = $du / $dl
    $arWP[$j] = $halfW * (Prof $tt ($sp.tm + $sp.lean) $sp.alpha $sp.w0) * (1 + $sp.asym * $asymT) * (1 + (Wob $sp.wobP $tt))
    $arWM[$j] = $halfW * (Prof $tt ($sp.tm - $sp.lean) $sp.alpha $sp.w0) * (1 - $sp.asym * $asymT) * (1 + (Wob $sp.wobM $tt))
  }
  $toScreen = {
    param([double]$pu, [double]$pv)
    $u2 = $pu * $ct - $pv * $st; $v2 = $pu * $st + $pv * $ct
    $x = $v2; $y = -($r0 + $u2)
    New-Object System.Drawing.PointF([single]($k * ($x * $ca - $y * $sa)), [single]($k * ($x * $sa + $y * $ca)))
  }
  $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($j = 0; $j -le $cnt; $j++) { $pts.Add((& $toScreen ($arU[$j] + $arNU[$j] * $arWP[$j]) ($arV[$j] + $arNV[$j] * $arWP[$j]))) }
  for ($j = $cnt - 1; $j -ge 0; $j--) { $pts.Add((& $toScreen ($arU[$j] - $arNU[$j] * $arWM[$j]) ($arV[$j] - $arNV[$j] * $arWM[$j]))) }
  @{ Outline = $pts.ToArray(); Angle = $sp.ang }
}
function Get-Center([double]$radius, $harm, [double]$k) {
  $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($j = 0; $j -lt 96; $j++) {
    $th = 2 * [Math]::PI * $j / 96; $rad = $radius
    foreach ($h in $harm) { $rad += $radius * $h[0] * [Math]::Sin($h[1] * $th + $h[2]) }
    $pts.Add((P ($k * $rad * [Math]::Sin($th)) (-$k * $rad * [Math]::Cos($th))))
  }
  $pts.ToArray()
}
function Get-Flower([double]$k) {
  $petals = @()
  for ($i = 0; $i -lt 5; $i++) {
    $p = $Brisa.per[$i]
    $sp = @{ r0 = $Brisa.r0; L = $p.L; W = $p.W; tm = $Brisa.tm; alpha = $Brisa.alpha; w0 = $Brisa.w0
             lean = $p.lean; b1 = 0.0; b2 = $p.b2; b3 = $p.b3; tilt = $p.tilt; asym = $p.asym; asymK = $Brisa.asymK
             wobP = $p.wobP; wobM = $p.wobM; ang = ($Brisa.rot + 72 * $i + $p.dAng) }
    $petals += ,(Get-Petal $sp $k)
  }
  @{ Petals = $petals; Center = (Get-Center $Brisa.centerR $Brisa.centerHarm $k) }
}
function Path-Of($pts) { $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddPolygon($pts); $p }
function Get-Bounds($flower) {
  $maxR = 0
  foreach ($pt in $flower.Petals) { foreach ($q in $pt.Outline) { $r = [Math]::Sqrt($q.X*$q.X + $q.Y*$q.Y); if ($r -gt $maxR) { $maxR = $r } } }
  $maxR
}
$maxR1 = Get-Bounds (Get-Flower 1.0)

# ---------------- flor em aguada (FlowerView.swift: petal(for:), notanGradient, painted border) --------
# Números iguais a FlowerView.swift: washOpacity 0.07, notanBaseFraction 0.22, notanTipFraction 0.30,
# paintedBorderMinSize 120, paintedBorderFraction 0.35, paintedBorderWidth 1.25, outlineWidth 1.5.
function Draw-InkFlower($g, [double]$cx, [double]$cy, [double]$size, [string[]]$activeTokens, $pal) {
  $k = ($size / 2) / $maxR1
  $fl = Get-Flower $k
  $state = $g.Save(); $g.TranslateTransform([single]$cx, [single]$cy)
  for ($i = 0; $i -lt 5; $i++) {
    $pt = $fl.Petals[$i]; $path = Path-Of $pt.Outline
    $token = $GoalTokens[$i]
    $activeIndex = [array]::IndexOf($activeTokens, $token)
    if ($activeIndex -ge 0) {
      $goalHex = $Theme[$token][$pal]
      $inkHex = $Theme.textPrimary[$pal]
      $paperHex = $Theme.surface[$pal]
      $baseHex = MixHex $goalHex $inkHex 0.22
      $tipHex = MixHex $goalHex $paperHex 0.30
      # eixo real da pétala (mesmo ângulo usado no Swift), base perto do miolo → ponta.
      $ang = $pt.Angle * [Math]::PI / 180
      $dx = [Math]::Sin($ang); $dy = -[Math]::Cos($ang)
      $baseR = $size * 0.12; $tipR = $size * 0.82 / 2
      $p0 = P ($baseR * 0.5 * $dx * 2) ($baseR * 0.5 * $dy * 2)
      $p1 = P ($tipR * $dx) ($tipR * $dy)
      $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($p0, $p1, (HexColor $baseHex), (HexColor $tipHex)); $lg.WrapMode = 'TileFlipXY'
      $g.FillPath($lg, $path); $lg.Dispose()
      if ($size -ge 120) {
        $borderHex = MixHex $goalHex $inkHex 0.35
        $pen = New-Object System.Drawing.Pen((HexColor $borderHex), 1.25)
        $g.DrawPath($pen, $path); $pen.Dispose()
      }
    } else {
      $wash = New-Object System.Drawing.SolidBrush((HexColor $Theme.inkMuted[$pal] 18))  # 0.07 * 255 ≈ 18
      $g.FillPath($wash, $path); $wash.Dispose()
      $pen = New-Object System.Drawing.Pen((HexColor $Theme.textSecondary[$pal]), 1.5)
      $g.DrawPath($pen, $path); $pen.Dispose()
    }
    $path.Dispose()
  }
  $cp = Path-Of $fl.Center; $cb = New-Object System.Drawing.SolidBrush((HexColor $Theme.flowerCenter[$pal]))
  $g.FillPath($cb, $cp); $cb.Dispose(); $cp.Dispose()
  $g.Restore($state)
}

# ---------------- ensō (EnsoRingView.swift) ----------------
function Draw-Enso($g, [double]$cx, [double]$cy, [double]$diameter, [double]$progress, $pal) {
  $gapDeg = 30.0; $sweepDeg = 360.0 - $gapDeg; $startDeg = 180.0 + $gapDeg / 2
  $flyFrac = 0.08; $segments = 24
  $maxW = $diameter * 0.11; $minW = $diameter * 0.035; $trackW = $diameter * 0.05
  $radius = $diameter / 2 - $maxW / 2
  function ArcRect([double]$r) { New-Object System.Drawing.RectangleF([single]($cx - $r), [single]($cy - $r), [single](2*$r), [single](2*$r)) }
  # graus "app" (0 = topo, horário) → graus GDI+ (0 = direita, sentido horário já é o padrão do DrawArc)
  function ToGdi([double]$appDeg) { $appDeg - 90 }

  $trackPen = New-Object System.Drawing.Pen((HexColor $Theme.line[$pal]), $trackW); $trackPen.StartCap = 'Round'; $trackPen.EndCap = 'Round'
  $g.DrawArc($trackPen, (ArcRect $radius), (ToGdi $startDeg), $sweepDeg); $trackPen.Dispose()

  $painted = $sweepDeg * [Math]::Min(1.0, [Math]::Max(0.0, $progress))
  if ($painted -le 0) { return }
  $flying = $painted * $flyFrac
  $solid = $painted - $flying
  if ($solid -gt 0) {
    for ($i = 0; $i -lt $segments; $i++) {
      $a0 = $startDeg + $solid * $i / $segments; $a1 = $startDeg + $solid * ($i + 1) / $segments
      if ($a1 -le $a0) { continue }
      $wf = ($i + 0.5) / $segments
      $w = $maxW + ($minW - $maxW) * $wf
      $pen = New-Object System.Drawing.Pen((HexColor $Theme.accent[$pal]), $w); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
      $g.DrawArc($pen, (ArcRect $radius), (ToGdi $a0), ($a1 - $a0)); $pen.Dispose()
    }
  }
  if ($flying -gt 0) {
    $step = $maxW * 0.18
    $threads = @(@(-$step, 40), @(0, 60), @($step, 40))
    $startA = $startDeg + $solid
    foreach ($th in $threads) {
      $pen = New-Object System.Drawing.Pen((HexColor $Theme.accent[$pal] $th[1]), ($minW * 0.4))
      $g.DrawArc($pen, (ArcRect ($radius + $th[0])), (ToGdi $startA), $flying); $pen.Dispose()
    }
  }
}

# ---------------- marca de tinta (InkMarkView.swift) ----------------
function Draw-InkMark($g, [double]$x, [double]$y, [double]$width, [double]$progress, [bool]$hasData, $pal, [string]$tintHex) {
  $trackW = 1.0; $maxW = 5.0; $minW = 2.0; $flyFrac = 0.08; $segments = 14
  $midY = [single]($y + 3)
  if ($hasData) {
    $trackPen = New-Object System.Drawing.Pen((HexColor $Theme.line[$pal]), $trackW)
    $g.DrawLine($trackPen, [single]$x, $midY, [single]($x + $width), $midY); $trackPen.Dispose()
  } else {
    $trackPen = New-Object System.Drawing.Pen((HexColor $Theme.line[$pal]), $trackW); $trackPen.DashPattern = @(3, 3)
    $g.DrawLine($trackPen, [single]$x, $midY, [single]($x + $width), $midY); $trackPen.Dispose()
    return
  }
  $painted = $width * [Math]::Min(1.0, [Math]::Max(0.0, $progress))
  if ($painted -le 0) { return }
  $flying = $painted * $flyFrac
  $solid = $painted - $flying
  if ($solid -gt 0) {
    for ($i = 0; $i -lt $segments; $i++) {
      $x0 = $solid * $i / $segments; $x1 = $solid * ($i + 1) / $segments
      if ($x1 -le $x0) { continue }
      $wf = ($i + 0.5) / $segments
      $w = $maxW + ($minW - $maxW) * $wf
      $pen = New-Object System.Drawing.Pen((HexColor $tintHex), $w); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
      $g.DrawLine($pen, [single]($x + $x0), $midY, [single]($x + $x1), $midY); $pen.Dispose()
    }
  }
  if ($flying -gt 0) {
    $offsets = @(-1, 0, 1)
    foreach ($o in $offsets) {
      $pen = New-Object System.Drawing.Pen((HexColor $tintHex 217), ($minW * 0.4))
      $g.DrawLine($pen, [single]($x + $solid), ($midY + $o), [single]($x + $painted), ($midY + $o)); $pen.Dispose()
    }
  }
}

# ---------------- aguada de montanha (MountainWashView.swift) ----------------
function Get-Ridge([double]$baseline, $peaks) {
  $pts = @()
  for ($i = 0; $i -le 48; $i++) {
    $x = $i / 48.0; $y = $baseline
    foreach ($pk in $peaks) { $d = ($x - $pk[0]) / $pk[2]; $y -= $pk[1] * [Math]::Exp(-$d*$d) }
    $pts += ,(@($x, $y))
  }
  $pts
}
function Draw-MountainWash($g, [double]$x, [double]$y, [double]$w, [double]$h, $pal) {
  $layers = @(
    @{ Ridge = (Get-Ridge 0.62 @(@(0.16,0.24,0.20), @(0.52,0.32,0.24), @(0.86,0.20,0.18))); Peak = 0.04; GradStart = 0.30 },
    @{ Ridge = (Get-Ridge 0.80 @(@(0.04,0.18,0.16), @(0.38,0.36,0.22), @(0.70,0.26,0.18), @(0.97,0.14,0.14))); Peak = 0.07; GradStart = 0.55 }
  )
  $ink = HexColor $Theme.textPrimary[$pal]
  foreach ($layer in $layers) {
    $poly = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    foreach ($pt in $layer.Ridge) { $poly.Add((P ($x + $pt[0]*$w) ($y + $pt[1]*$h))) }
    $poly.Add((P ($x + $w) ($y + $h))); $poly.Add((P $x ($y + $h)))
    $path = Path-Of $poly.ToArray()
    $peakA = [int](255 * $layer.Peak)
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
      (P ($x + $w/2) ($y + $h * $layer.GradStart)), (P ($x + $w/2) ($y + $h)),
      (WithAlpha $ink $peakA), (WithAlpha $ink 0))
    $lg.WrapMode = 'TileFlipXY'
    $g.FillPath($lg, $path); $lg.Dispose(); $path.Dispose()
  }
}

# ---------------- folha (uma aparência por chamada) ----------------
function Render-Sheet([string]$pal) {
  $W = 1040
  $rowFlowerY = 60; $rowFlowerH = 168 + 40 + 56 + 40
  $rowEnsoY = $rowFlowerY + $rowFlowerH + 20; $rowEnsoH = 100
  $rowMarkY = $rowEnsoY + $rowEnsoH + 20; $rowMarkH = 130
  $rowMountainY = $rowMarkY + $rowMarkH + 20; $rowMountainH = 160
  $rowCardY = $rowMountainY + $rowMountainH + 20; $rowCardH = 150
  $rowPaletteY = $rowCardY + $rowCardH + 20; $rowPaletteH = 40 + 17 * 24
  $H = $rowPaletteY + $rowPaletteH + 30

  $bmp = New-Object System.Drawing.Bitmap $W, $H
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $pageBg = if ($pal -eq 'dark') { '#0E0C0B' } else { '#EDE6D8' }
  $g.Clear((HexColor $pageBg))
  $ink = New-Object System.Drawing.SolidBrush((HexColor $Theme.textPrimary[$pal]))
  $ink2 = New-Object System.Drawing.SolidBrush((HexColor $Theme.textSecondary[$pal]))
  $fTitle = New-Object System.Drawing.Font 'Segoe UI', 18, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $fName = New-Object System.Drawing.Font 'Segoe UI', 14, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $fSmall = New-Object System.Drawing.Font 'Segoe UI', 12, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $label = if ($pal -eq 'dark') { 'escura' } else { 'clara' }
  $g.DrawString("Magister . Tinta e papel (T9.1) . conferencia ($label)", $fTitle, $ink, 24, 18)

  # --- flores: 56 pt e 168 pt, com 0/1/2 objetivos ativos ---
  $g.DrawString('Flor em aguada: 0, 1 e 2 objetivos ativos (56 pt e 168 pt)', $fName, $ink, 24, ($rowFlowerY - 26))
  $scenarios = @(
    @{ Tokens = @(); Label = 'nenhum' },
    @{ Tokens = @('goalHypertrophy'); Label = 'Hipertrofia' },
    @{ Tokens = @('goalHypertrophy', 'goalEndurance'); Label = 'Hipertrofia + Cardio' }
  )
  $colW = 320
  for ($i = 0; $i -lt $scenarios.Count; $i++) {
    $sc = $scenarios[$i]
    $colX = 24 + $i * $colW
    Draw-InkFlower $g ($colX + 84) ($rowFlowerY + 84) 168 $sc.Tokens $pal
    Draw-InkFlower $g ($colX + 84 + 168 + 40 + 28) ($rowFlowerY + 84) 56 $sc.Tokens $pal
    $g.DrawString($sc.Label, $fSmall, $ink2, $colX, ($rowFlowerY + 168 + 8))
  }

  # --- ensō: 0, 0,5, 1 ---
  $g.DrawString('Enso (descanso): progresso 0, 0,5 e 1', $fName, $ink, 24, ($rowEnsoY - 26))
  $ensoProgress = @(0.0, 0.5, 1.0)
  for ($i = 0; $i -lt $ensoProgress.Count; $i++) {
    $cx = 24 + 48 + $i * 140
    Draw-Enso $g $cx ($rowEnsoY + 48) 88 $ensoProgress[$i] $pal
    $lbl = '{0:N1}' -f $ensoProgress[$i]
    $g.DrawString($lbl, $fSmall, $ink2, ($cx - 14), ($rowEnsoY + 96))
  }

  # --- marca de tinta: 0, 0,6, 1, sem dados ---
  $g.DrawString('Marca de tinta: 0, 0,6, 1 e sem dados', $fName, $ink, 24, ($rowMarkY - 26))
  $markRows = @(
    @{ Progress = 0.0; HasData = $true; Label = '0' },
    @{ Progress = 0.6; HasData = $true; Label = '0,6' },
    @{ Progress = 1.0; HasData = $true; Label = '1' },
    @{ Progress = 0.0; HasData = $false; Label = 'sem dados' }
  )
  for ($i = 0; $i -lt $markRows.Count; $i++) {
    $row = $markRows[$i]
    $y0 = $rowMarkY + $i * 28
    Draw-InkMark $g 24 $y0 260 $row.Progress $row.HasData $pal $Theme.inkMuted[$pal]
    $g.DrawString($row.Label, $fSmall, $ink2, 300, $y0)
  }

  # --- aguada de montanha ---
  $g.DrawString('Aguada de montanha', $fName, $ink, 24, ($rowMountainY - 26))
  Draw-MountainWash $g 24 $rowMountainY 560 130 $pal

  # --- cartao sobre papel ---
  $g.DrawString('Cartao sobre papel (paperBackground + inkCard)', $fName, $ink, 24, ($rowCardY - 26))
  $paperBrush = New-Object System.Drawing.SolidBrush((HexColor $Theme.background[$pal]))
  $g.FillRectangle($paperBrush, 24, $rowCardY, 300, $rowCardH); $paperBrush.Dispose()
  $cardRect = New-RoundRect 54 ($rowCardY + 24) 240 ($rowCardH - 48) 16
  $cardBrush = New-Object System.Drawing.SolidBrush((HexColor $Theme.surface[$pal]))
  $g.FillPath($cardBrush, $cardRect); $cardBrush.Dispose()
  $cardPen = New-Object System.Drawing.Pen((HexColor $Theme.line[$pal]), 0.5)
  $g.DrawPath($cardPen, $cardRect); $cardPen.Dispose(); $cardRect.Dispose()

  # --- paleta e contrastes ---
  $g.DrawString('Paleta e contraste (WCAG, sobre background / surface)', $fName, $ink, 24, ($rowPaletteY - 6))
  $tokens = @('textPrimary', 'textSecondary', 'accent', 'onAccent', 'goalHypertrophy', 'goalStrength', 'goalEndurance', 'goalLongevity', 'goalCombat', 'health')
  $y0 = $rowPaletteY + 28
  foreach ($tok in $tokens) {
    $hex = $Theme[$tok][$pal]
    $swatch = New-Object System.Drawing.SolidBrush((HexColor $hex))
    $g.FillRectangle($swatch, 24, $y0, 20, 16); $swatch.Dispose()
    $cBg = Contrast (HexColor $hex) (HexColor $Theme.background[$pal])
    $cSurf = Contrast (HexColor $hex) (HexColor $Theme.surface[$pal])
    $txt = '{0} {1} . fundo {2:N2}:1 . cartao {3:N2}:1' -f $tok, $hex, $cBg, $cSurf
    $g.DrawString($txt, $fSmall, $ink, 54, ($y0 - 2))
    $y0 += 24
  }

  $ink.Dispose(); $ink2.Dispose()
  $bmp
}

$lightSheet = Render-Sheet 'light'
$darkSheet = Render-Sheet 'dark'
$lightSheet.Save((Join-Path $OutDir 'ink-sheet.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$darkSheet.Save((Join-Path $OutDir 'ink-sheet-dark.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$lightSheet.Dispose(); $darkSheet.Dispose()

"folhas: $(Join-Path $OutDir 'ink-sheet.png') e $(Join-Path $OutDir 'ink-sheet-dark.png')"
