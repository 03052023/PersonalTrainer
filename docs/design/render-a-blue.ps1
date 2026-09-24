# render-a-blue.ps1 — conceito A (5 pétalas separadas, cada uma de uma cor; miolo claro) sobre fundos azuis.
# Ordem horária a partir do topo (DESIGN §4): Longevidade, Hipertrofia, Força, Combate, Resistência.
# Cada objetivo mantém a mesma família de cor em todas as variantes, para virar a cor do objetivo no app.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'blue-a'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$variants = @(
  @{ key='a1'; label='Azul profundo + terrosos claros'; bgTop='#3E5F7E'; bgBot='#2C4763'; center='#F5EFE3'; tipTo='#FFFFFF'; tip=0.10
     petals=@('#A9B98F','#E0927A','#C9A27F','#C9A0BC','#9FB2C2') },
  @{ key='a2'; label='Azul profundo + quentes'; bgTop='#3E5F7E'; bgBot='#2C4763'; center='#F7F1E6'; tipTo='#FFFFFF'; tip=0.08
     petals=@('#C9C27A','#E88A6E','#E3B35C','#D69A9A','#EFD9B4') },
  @{ key='a3'; label='Azul claro + terrosos médios'; bgTop='#D8E6EF'; bgBot='#BFD3E2'; center='#F7F2E8'; tipTo='#D8E6EF'; tip=0.12
     petals=@('#5E6E50','#9A553E','#80603F','#7A566F','#536676') },
  @{ key='a4'; label='Azul médio + pastéis'; bgTop='#5F86A6'; bgBot='#476C8C'; center='#FFFFFF'; tipTo='#FFFFFF'; tip=0.06
     petals=@('#CFE0C3','#F3B8A0','#F2D6A2','#E8C6D8','#F4EEE2') },
  @{ key='a5'; label='Azul-noite + joias suaves'; bgTop='#243A55'; bgBot='#18283D'; center='#F3EDE1'; tipTo='#FFFFFF'; tip=0.10
     petals=@('#9DBB8A','#C97B5A','#D9B25E','#A77AA6','#5FA8A0') },
  @{ key='a6'; label='Azul profundo + frios com um quente'; bgTop='#3E5F7E'; bgBot='#2C4763'; center='#F7F3EA'; tipTo='#FFFFFF'; tip=0.08
     petals=@('#B5C99A','#E8B08F','#E8CFA3','#B7A9D9','#7FC1B6') }
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
  $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 -2), (P 0 ($S + 2)), (HexColor $v.bgTop), (HexColor $v.bgBot))
  $g.FillRectangle($bgBrush, 0, 0, $S, $S)
  # halo sutil atrás da flor (clareia o fundo em direção ao miolo)
  $glowR = 430; $gp = New-Object System.Drawing.Drawing2D.GraphicsPath; $gp.AddEllipse([single]($cx - $glowR), [single]($cy - $glowR), [single](2*$glowR), [single](2*$glowR))
  $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp); $glow.CenterPoint = (P $cx $cy)
  $glowC = Mix (HexColor $v.bgTop) (HexColor '#FFFFFF') 0.35
  $glow.CenterColor = (HexColor ('#{0:X2}{1:X2}{2:X2}' -f $glowC.R, $glowC.G, $glowC.B) 60); $glow.SurroundColors = [System.Drawing.Color[]]@((HexColor $v.bgTop 0))
  $g.FillPath($glow, $gp)
  for ($i = 0; $i -lt 5; $i++) {
    $petal = New-PetalPath; $base = HexColor $v.petals[$i]
    $cBase = Mix $base (HexColor $v.bgBot) 0.08; $cTip = Mix $base (HexColor $v.tipTo) $v.tip
    $g.ResetTransform(); $g.TranslateTransform([single]$cx, [single]$cy); $g.RotateTransform([single](72 * $i))
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 (-$r0 + 2)), (P 0 (-$r1 - 2)), $cBase, $cTip); $lg.WrapMode = 'TileFlipXY'
    $g.FillPath($lg, $petal); $lg.Dispose(); $petal.Dispose()
  }
  $g.ResetTransform()
  $cp = New-Object System.Drawing.Drawing2D.GraphicsPath; $cp.AddEllipse([single]($cx - $rCenter), [single]($cy - $rCenter), [single](2*$rCenter), [single](2*$rCenter))
  $cBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P $cx ($cy - $rCenter - 1)), (P $cx ($cy + $rCenter + 1)), (HexColor $v.center), (Mix (HexColor $v.center) (HexColor $v.bgTop) 0.25))
  $g.FillPath($cBrush, $cp); $g.Dispose()
  $file = Join-Path $outDir ("icon-{0}.png" -f $v.key); $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  $minC = 99; foreach ($p in $v.petals) { $minC = [Math]::Min($minC, (Contrast (HexColor $p) (HexColor $v.bgBot))) }
  "{0} ({1}): menor contraste pétala x fundo = {2:N2}:1" -f $v.key, $v.label, $minC
  $rendered += @{ key = $v.key; label = $v.label; file = $file }
}

# folha de comparação: 3 x 2, cada ícone com prévia real em fundo escuro e claro
$W = 1110; $H = 930
$sheet = New-Object System.Drawing.Bitmap $W, $H
$gs = [System.Drawing.Graphics]::FromImage($sheet); $gs.SmoothingMode = 'AntiAlias'; $gs.InterpolationMode = 'HighQualityBicubic'; $gs.TextRenderingHint = 'AntiAlias'
$gs.Clear((HexColor '#F2F2F7'))
$font = New-Object System.Drawing.Font 'Segoe UI', 15, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $rendered.Count; $i++) {
  $img = [System.Drawing.Image]::FromFile($rendered[$i].file)
  $col = $i % 3; $row = [Math]::Floor($i / 3); $x = 45 + $col * 355; $y = 25 + $row * 450
  $gs.SetClip((New-RoundRect $x $y 270 270 60)); $gs.DrawImage($img, (New-Object System.Drawing.Rectangle $x, $y, 270, 270)); $gs.ResetClip()
  $gs.DrawString(("{0} · {1}" -f ($i + 1), $rendered[$i].label), $font, [System.Drawing.Brushes]::Black, $x - 5, $y + 278)
  $gs.FillRectangle((New-Object System.Drawing.SolidBrush (HexColor '#1C1C1E')), $x, $y + 312, 135, 95)
  $gs.SetClip((New-RoundRect ($x + 34) ($y + 325) 68 68 15)); $gs.DrawImage($img, (New-Object System.Drawing.Rectangle ($x + 34), ($y + 325), 68, 68)); $gs.ResetClip()
  $gs.FillRectangle((New-Object System.Drawing.SolidBrush (HexColor '#FFFFFF')), $x + 135, $y + 312, 135, 95)
  $gs.SetClip((New-RoundRect ($x + 168) ($y + 325) 68 68 15)); $gs.DrawImage($img, (New-Object System.Drawing.Rectangle ($x + 168), ($y + 325), 68, 68)); $gs.ResetClip()
  $img.Dispose()
}
$sheet.Save((Join-Path $outDir 'compare.png'), [System.Drawing.Imaging.ImageFormat]::Png); $gs.Dispose(); $sheet.Dispose()
"folha: " + (Join-Path $outDir 'compare.png')
