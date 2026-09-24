# render-app-icon.ps1 — ícone final do Magister (decisão do dono, 2026-09-23): conceito A, cinco pétalas creme
# separadas e miolo areia sobre azul-marinho (#2B3F58 → #1C2B40). Sem texto, sem cantos arredondados (o iOS aplica a
# máscara), sem sombra pintada; só um halo muito leve atrás da flor na aparência padrão.
#
# Saídas:
#   <IconSet>\AppIcon.png         1024x1024, opaco — aparência padrão
#   <IconSet>\AppIcon-dark.png    1024x1024, opaco — aparência escura (iOS 18+)
#   <IconSet>\AppIcon-tinted.png  1024x1024, opaco, tons de cinza — aparência tingida (iOS 18+)
#   <CheckDir>\AppIcon-checks.png folha de conferência: 3 aparências, tamanhos reais e fundos claro/escuro
#
# Uso: powershell -ExecutionPolicy Bypass -File docs/design/render-app-icon.ps1 [-IconSet <pasta>] [-CheckDir <pasta>]
param([string]$IconSet = '', [string]$CheckDir = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent $here)
if ($IconSet -eq '') { $IconSet = Join-Path $repo 'PersonalTrainer\Resources\Assets.xcassets\AppIcon.appiconset' }
if ($CheckDir -eq '') { $CheckDir = Join-Path $here 'candidates' }
New-Item -ItemType Directory -Force -Path $IconSet, $CheckDir | Out-Null

# ---------------- aparências ----------------
$Looks = [ordered]@{
  default = @{ bgTop='#2B3F58'; bgBot='#1C2B40'; petal='#F1EDE4'; tipTo='#FFFFFF'; tip=0.35; baseMix=0.05; center='#E9DCC6'; glowA=55; gray=$false }
  dark    = @{ bgTop='#18222F'; bgBot='#101822'; petal='#E3DED3'; tipTo='#F4F1EA'; tip=0.30; baseMix=0.06; center='#D3C4AB'; glowA=0;  gray=$false }
  tinted  = @{ bgTop='#000000'; bgBot='#000000'; petal='#E4E4E4'; tipTo='#FAFAFA'; tip=0.40; baseMix=0.04; center='#BDBDBD'; glowA=0;  gray=$true }
}
# ---------------- geometria (1024 px) ----------------
$S = 1024; $r0 = 68; $r1 = 338; $halfW = 98; $wPos = 0.66; $baseK = 0.40; $rCenter = 52

function HexColor([string]$hex, [int]$a = 255) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16)) }
function Mix($c1, $c2, [double]$t) { [System.Drawing.Color]::FromArgb(255, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t)) }
function Lin([double]$v) { $v = $v / 255.0; if ($v -le 0.04045) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) } }
function RelLum($c) { 0.2126 * (Lin $c.R) + 0.7152 * (Lin $c.G) + 0.0722 * (Lin $c.B) }
function Contrast($a, $b) { $la = RelLum $a; $lb = RelLum $b; ([Math]::Max($la,$lb) + 0.05) / ([Math]::Min($la,$lb) + 0.05) }
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF([single]$x, [single]$y) }
function New-PetalPath {
  $L = $r1 - $r0; $yW = $r0 + $wPos * $L; $k = 0.5523
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddBezier((P 0 (-$r0)), (P ($halfW*$baseK) (-$r0)), (P $halfW (-($r0 + 0.26*$L))), (P $halfW (-$yW)))
  $p.AddBezier((P $halfW (-$yW)), (P $halfW (-($yW + $k*($r1-$yW)))), (P ($k*$halfW) (-$r1)), (P 0 (-$r1)))
  $p.AddBezier((P 0 (-$r1)), (P (-$k*$halfW) (-$r1)), (P (-$halfW) (-($yW + $k*($r1-$yW)))), (P (-$halfW) (-$yW)))
  $p.AddBezier((P (-$halfW) (-$yW)), (P (-$halfW) (-($r0 + 0.26*$L))), (P (-$halfW*$baseK) (-$r0)), (P 0 (-$r0)))
  $p.CloseFigure(); $p
}
function New-RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = 2 * $r
  $p.AddArc([single]$x, [single]$y, [single]$d, [single]$d, 180, 90); $p.AddArc([single]($x + $w - $d), [single]$y, [single]$d, [single]$d, 270, 90)
  $p.AddArc([single]($x + $w - $d), [single]($y + $h - $d), [single]$d, [single]$d, 0, 90); $p.AddArc([single]$x, [single]($y + $h - $d), [single]$d, [single]$d, 90, 90)
  $p.CloseFigure(); $p
}

# centro óptico: caixa envolvente das cinco pétalas centrada na tela
$minX = 1e9; $maxX = -1e9; $minY = 1e9; $maxY = -1e9
for ($i = 0; $i -lt 5; $i++) {
  $pp = New-PetalPath; $m = New-Object System.Drawing.Drawing2D.Matrix; $m.Rotate([single](72 * $i)); $pp.Transform($m); $pp.Flatten()
  $b = $pp.GetBounds(); $minX = [Math]::Min($minX, $b.Left); $maxX = [Math]::Max($maxX, $b.Right); $minY = [Math]::Min($minY, $b.Top); $maxY = [Math]::Max($maxY, $b.Bottom)
}
$cx = $S / 2.0; $cy = $S / 2.0 - ($minY + $maxY) / 2.0

function Render-Icon($look) {
  $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.CompositingQuality = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 -2), (P 0 ($S + 2)), (HexColor $look.bgTop), (HexColor $look.bgBot))
  $g.FillRectangle($bg, 0, 0, $S, $S); $bg.Dispose()
  if ($look.glowA -gt 0) {
    $glowR = 430; $gp = New-Object System.Drawing.Drawing2D.GraphicsPath; $gp.AddEllipse([single]($cx - $glowR), [single]($cy - $glowR), [single](2*$glowR), [single](2*$glowR))
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp); $glow.CenterPoint = (P $cx $cy)
    $gc = Mix (HexColor $look.bgTop) (HexColor '#FFFFFF') 0.30
    $glow.CenterColor = [System.Drawing.Color]::FromArgb($look.glowA, $gc.R, $gc.G, $gc.B); $glow.SurroundColors = [System.Drawing.Color[]]@((HexColor $look.bgTop 0))
    $g.FillPath($glow, $gp); $glow.Dispose(); $gp.Dispose()
  }
  for ($i = 0; $i -lt 5; $i++) {
    $petal = New-PetalPath; $base = HexColor $look.petal
    $cBase = Mix $base (HexColor $look.bgBot) $look.baseMix; $cTip = Mix $base (HexColor $look.tipTo) $look.tip
    $g.ResetTransform(); $g.TranslateTransform([single]$cx, [single]$cy); $g.RotateTransform([single](72 * $i))
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 (-$r0 + 2)), (P 0 (-$r1 - 2)), $cBase, $cTip); $lg.WrapMode = 'TileFlipXY'
    $g.FillPath($lg, $petal); $lg.Dispose(); $petal.Dispose()
  }
  $g.ResetTransform()
  $cp = New-Object System.Drawing.Drawing2D.GraphicsPath; $cp.AddEllipse([single]($cx - $rCenter), [single]($cy - $rCenter), [single](2*$rCenter), [single](2*$rCenter))
  $cb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P $cx ($cy - $rCenter - 1)), (P $cx ($cy + $rCenter + 1)), (HexColor $look.center), (Mix (HexColor $look.center) (HexColor $look.bgTop) 0.18))
  $g.FillPath($cb, $cp); $cb.Dispose(); $cp.Dispose(); $g.Dispose()
  if ($look.gray) {
    # garante tons de cinza puros (R = G = B), que é o que o iOS espera na aparência tingida:
    # a mesma soma ponderada vai para os três canais.
    $cm = New-Object System.Drawing.Imaging.ColorMatrix(,[single[][]]@(
      [single[]]@(0.299, 0.299, 0.299, 0, 0),
      [single[]]@(0.587, 0.587, 0.587, 0, 0),
      [single[]]@(0.114, 0.114, 0.114, 0, 0),
      [single[]]@(0, 0, 0, 1, 0),
      [single[]]@(0, 0, 0, 0, 1)))
    $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cm)
    $grayBmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $gg = [System.Drawing.Graphics]::FromImage($grayBmp)
    $gg.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, $S, $S), 0, 0, $S, $S, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    $gg.Dispose(); $ia.Dispose(); $bmp.Dispose(); $bmp = $grayBmp
  }
  $bmp
}

$icons = [ordered]@{}
foreach ($k in $Looks.Keys) { $icons[$k] = Render-Icon $Looks[$k] }
$icons.default.Save((Join-Path $IconSet 'AppIcon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$icons.dark.Save((Join-Path $IconSet 'AppIcon-dark.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$icons.tinted.Save((Join-Path $IconSet 'AppIcon-tinted.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# ---------------- folha de conferência ----------------
$W = 900; $H = 560
$sheet = New-Object System.Drawing.Bitmap $W, $H
$gs = [System.Drawing.Graphics]::FromImage($sheet); $gs.SmoothingMode = 'AntiAlias'; $gs.InterpolationMode = 'HighQualityBicubic'; $gs.TextRenderingHint = 'AntiAlias'
$gs.Clear((HexColor '#F2F2F7'))
$font = New-Object System.Drawing.Font 'Segoe UI', 14, ([System.Drawing.FontStyle]::Bold)
$names = @('Padrão', 'Modo escuro', 'Tingido (o iOS pinta por cima)')
$i = 0
foreach ($k in $icons.Keys) {
  $x = 30 + $i * 290; $y = 20
  $gs.SetClip((New-RoundRect $x $y 250 250 56)); $gs.DrawImage($icons[$k], (New-Object System.Drawing.Rectangle $x, $y, 250, 250)); $gs.ResetClip()
  $gs.DrawString($names[$i], $font, [System.Drawing.Brushes]::Black, (New-Object System.Drawing.RectangleF ($x - 4), ($y + 256), 280, 30))
  $i++
}
# tamanhos reais sobre papel de parede claro e escuro: 120 px (tela inicial), 80 px (Spotlight), 58 px (Ajustes)
$halves = @(@{ bg='#FFFFFF'; x=30 }, @{ bg='#1C1C1E'; x=465 })
foreach ($hv in $halves) {
  $gs.FillRectangle((New-Object System.Drawing.SolidBrush (HexColor $hv.bg)), $hv.x, 320, 405, 210)
  $src = if ($hv.bg -eq '#FFFFFF') { $icons.default } else { $icons.dark }
  $sx = $hv.x + 30
  foreach ($size in 120, 80, 58) {
    $yy = 320 + (210 - $size) / 2
    $gs.SetClip((New-RoundRect $sx $yy $size $size ($size * 0.225))); $gs.DrawImage($src, (New-Object System.Drawing.Rectangle $sx, $yy, $size, $size)); $gs.ResetClip()
    $sx += $size + 40
  }
}
$checkFile = Join-Path $CheckDir 'AppIcon-checks.png'
$sheet.Save($checkFile, [System.Drawing.Imaging.ImageFormat]::Png); $gs.Dispose(); $sheet.Dispose()

# ---------------- medidas para o DESIGN.md ----------------
$d = $Looks.default
"centro da flor: ({0:N1}; {1:N1}); símbolo {2:N0} x {3:N0} px ({4:P0} x {5:P0} do lado); raio externo {6:N0} px" -f $cx, $cy, ($maxX - $minX), ($maxY - $minY), (($maxX - $minX) / $S), (($maxY - $minY) / $S), $r1
"pétala creme x fundo (topo / base): {0:N2}:1 / {1:N2}:1; miolo x fundo: {2:N2}:1" -f (Contrast (HexColor $d.petal) (HexColor $d.bgTop)), (Contrast (HexColor $d.petal) (HexColor $d.bgBot)), (Contrast (HexColor $d.center) (HexColor $d.bgTop))
"escuro: pétala x fundo {0:N2}:1; bloco padrão x papel claro #F2F2F7 {1:N2}:1, x escuro #1C1C1E {2:N2}:1" -f (Contrast (HexColor $Looks.dark.petal) (HexColor $Looks.dark.bgTop)), (Contrast (HexColor $d.bgTop) (HexColor '#F2F2F7')), (Contrast (HexColor $d.bgBot) (HexColor '#1C1C1E'))
foreach ($k in $icons.Keys) { $icons[$k].Dispose() }
"conferência: " + $checkFile
