# render-a-navy.ps1 — conceito A (5 pétalas separadas, miolo claro) sobre o azul-marinho da opção 5 (#2B3F58 → #1C2B40),
# com pétalas bem claras. Ordem horária a partir do topo (DESIGN §4): Longevidade, Hipertrofia, Força, Combate, Resistência.
# Uso: powershell -ExecutionPolicy Bypass -File render-a-navy.ps1 [-OutDir <pasta>]
param([string]$OutDir = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
if ($OutDir -eq '') { $OutDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'navy-light' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$navyTop = '#2B3F58'; $navyBot = '#1C2B40'
$variants = @(
  @{ key='n1'; label='Todas creme, miolo areia'; center='#E9DCC6'; tipTo='#FFFFFF'; tip=0.35
     petals=@('#F1EDE4','#F1EDE4','#F1EDE4','#F1EDE4','#F1EDE4') },
  @{ key='n2'; label='Quase brancas, tons sutis'; center='#FAF7F1'; tipTo='#FFFFFF'; tip=0.30
     petals=@('#E2E8DA','#EFDFD6','#EEE5D4','#E7DDE5','#DAE4ED') },
  @{ key='n3'; label='Claras, cores mais visíveis'; center='#FAF7F1'; tipTo='#FFFFFF'; tip=0.25
     petals=@('#D3DEC8','#E8CCBE','#E6D6BC','#DBC9D8','#C6D7E5') }
)
$S = 1024; $r0 = 68; $r1 = 338; $halfW = 98; $wPos = 0.66; $baseK = 0.40; $rCenter = 52

function HexColor([string]$hex, [int]$a = 255) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16)) }
function Mix($c1, $c2, [double]$t, [int]$a = 255) { [System.Drawing.Color]::FromArgb($a, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t)) }
function Lin([double]$v) { $v = $v / 255.0; if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) } }
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

# centro óptico (mesmo cálculo do conceito A)
$minY = 1e9; $maxY = -1e9
for ($i = 0; $i -lt 5; $i++) { $pp = New-PetalPath; $m = New-Object System.Drawing.Drawing2D.Matrix; $m.Rotate([single](72 * $i)); $pp.Transform($m); $pp.Flatten(); $b = $pp.GetBounds(); $minY = [Math]::Min($minY, $b.Top); $maxY = [Math]::Max($maxY, $b.Bottom) }
$cx = $S / 2.0; $cy = $S / 2.0 - ($minY + $maxY) / 2.0

$rendered = @()
foreach ($v in $variants) {
  $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.CompositingQuality = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
  $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 -2), (P 0 ($S + 2)), (HexColor $navyTop), (HexColor $navyBot))
  $g.FillRectangle($bgBrush, 0, 0, $S, $S)
  # halo sutil atrás da flor
  $glowR = 430; $gp = New-Object System.Drawing.Drawing2D.GraphicsPath; $gp.AddEllipse([single]($cx - $glowR), [single]($cy - $glowR), [single](2*$glowR), [single](2*$glowR))
  $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp); $glow.CenterPoint = (P $cx $cy)
  $glowC = Mix (HexColor $navyTop) (HexColor '#FFFFFF') 0.30
  $glow.CenterColor = [System.Drawing.Color]::FromArgb(55, $glowC.R, $glowC.G, $glowC.B); $glow.SurroundColors = [System.Drawing.Color[]]@((HexColor $navyTop 0))
  $g.FillPath($glow, $gp)
  for ($i = 0; $i -lt 5; $i++) {
    $petal = New-PetalPath; $base = HexColor $v.petals[$i]
    # base levemente sombreada pelo fundo, ponta clareando: dá volume sem contorno
    $cBase = Mix $base (HexColor $navyBot) 0.05; $cTip = Mix $base (HexColor $v.tipTo) $v.tip
    $g.ResetTransform(); $g.TranslateTransform([single]$cx, [single]$cy); $g.RotateTransform([single](72 * $i))
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 (-$r0 + 2)), (P 0 (-$r1 - 2)), $cBase, $cTip); $lg.WrapMode = 'TileFlipXY'
    $g.FillPath($lg, $petal); $lg.Dispose(); $petal.Dispose()
  }
  $g.ResetTransform()
  $cp = New-Object System.Drawing.Drawing2D.GraphicsPath; $cp.AddEllipse([single]($cx - $rCenter), [single]($cy - $rCenter), [single](2*$rCenter), [single](2*$rCenter))
  $cBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P $cx ($cy - $rCenter - 1)), (P $cx ($cy + $rCenter + 1)), (HexColor $v.center), (Mix (HexColor $v.center) (HexColor $navyTop) 0.18))
  $g.FillPath($cBrush, $cp); $g.Dispose()
  $file = Join-Path $OutDir ("icon-{0}.png" -f $v.key); $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  $minC = 99.0; foreach ($p in $v.petals) { $minC = [Math]::Min($minC, (Contrast (HexColor $p) (HexColor $navyTop))) }
  "{0} ({1}): menor contraste pétala x fundo = {2:N2}:1" -f $v.key, $v.label, $minC
  $rendered += @{ key = $v.key; label = $v.label; file = $file }
}

# folha de comparação 2 x 2: a opção 5 original como referência + as três variantes, cada uma com prévia em fundo escuro e claro
$ref = Join-Path $OutDir 'ref-option5.png'
$tiles = @()
if (Test-Path $ref) { $tiles += @{ label = 'Referência: opção 5 original'; file = $ref } }
$tiles += $rendered
$W = 760; $H = 930
$sheet = New-Object System.Drawing.Bitmap $W, $H
$gs = [System.Drawing.Graphics]::FromImage($sheet); $gs.SmoothingMode = 'AntiAlias'; $gs.InterpolationMode = 'HighQualityBicubic'; $gs.TextRenderingHint = 'AntiAlias'
$gs.Clear((HexColor '#F2F2F7'))
$font = New-Object System.Drawing.Font 'Segoe UI', 14, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $tiles.Count; $i++) {
  $img = [System.Drawing.Image]::FromFile($tiles[$i].file)
  $col = $i % 2; $row = [Math]::Floor($i / 2); $x = 45 + $col * 355; $y = 25 + $row * 450
  $gs.SetClip((New-RoundRect $x $y 270 270 60)); $gs.DrawImage($img, (New-Object System.Drawing.Rectangle $x, $y, 270, 270)); $gs.ResetClip()
  $caption = $tiles[$i].label
  if ($tiles[$i].key) { $caption = ("{0} · {1}" -f ($i - ($tiles.Count - $rendered.Count) + 1), $tiles[$i].label) }
  $gs.DrawString($caption, $font, [System.Drawing.Brushes]::Black, (New-Object System.Drawing.RectangleF ($x - 5), ($y + 276), 300, 40))
  $gs.FillRectangle((New-Object System.Drawing.SolidBrush (HexColor '#1C1C1E')), $x, $y + 318, 135, 95)
  $gs.SetClip((New-RoundRect ($x + 34) ($y + 331) 68 68 15)); $gs.DrawImage($img, (New-Object System.Drawing.Rectangle ($x + 34), ($y + 331), 68, 68)); $gs.ResetClip()
  $gs.FillRectangle((New-Object System.Drawing.SolidBrush (HexColor '#FFFFFF')), $x + 135, $y + 318, 135, 95)
  $gs.SetClip((New-RoundRect ($x + 168) ($y + 331) 68 68 15)); $gs.DrawImage($img, (New-Object System.Drawing.Rectangle ($x + 168), ($y + 331), 68, 68)); $gs.ResetClip()
  $img.Dispose()
}
$sheet.Save((Join-Path $OutDir 'compare.png'), [System.Drawing.Imaging.ImageFormat]::Png); $gs.Dispose(); $sheet.Dispose()
"folha: " + (Join-Path $OutDir 'compare.png')
