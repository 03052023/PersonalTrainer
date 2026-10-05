# render-launch-assets.ps1 — tela de lançamento e assets da abertura do Magister (T9.2, SPEC RF-50).
#
# Gera os assets [PROJ] que `project.yml` referencia em `UILaunchScreen` (owner notes item 3;
# docs/V23-UI-CONTRACT.md §4.2, ponto 1): a cor lisa `LaunchBackground` (azul-marinho do meio do
# degradê do ícone) e a imagem `LaunchFlower` (a flor Brisa com o halo, fundo transparente, 256 pt de
# largura, claro e escuro, @2x e @3x) — "idêntica ao ícone". Também escreve `launch-assets-check.png`,
# a folha de conferência (a flor sobre os dois fundos, nas duas aparências).
#
# A geometria da flor (Get-Petal/Get-Center/Get-Bounds) e as cores de cada aparência são as MESMAS de
# `docs/design/render-app-icon.ps1` (candidato 6 · Brisa, docs/design/icon-v22/render-icon-v22.ps1):
# duplicadas aqui de propósito, como aquele script já duplica do gerador de candidatos — são
# ferramentas de design irmãs (não o app: ARCHITECTURE §14 não se aplica a scripts de desenho), e cada
# uma fica determinística e legível sozinha. Nada de `Get-Random`: rodar de novo dá exatamente os
# mesmos PNG (mesmo SHA-256).
#
# Uso: powershell -ExecutionPolicy Bypass -File docs/design/v23-animation/render-launch-assets.ps1
#      [-ImageSet <pasta>] [-ColorSet <pasta>] [-CheckDir <pasta>]
param([string]$ImageSet = '', [string]$ColorSet = '', [string]$CheckDir = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
if ($ImageSet -eq '') { $ImageSet = Join-Path $repo 'PersonalTrainer\Resources\Assets.xcassets\LaunchFlower.imageset' }
if ($ColorSet -eq '') { $ColorSet = Join-Path $repo 'PersonalTrainer\Resources\Assets.xcassets\LaunchBackground.colorset' }
if ($CheckDir -eq '') { $CheckDir = $here }
New-Item -ItemType Directory -Force -Path $ImageSet, $ColorSet, $CheckDir | Out-Null

# ---------------- utilitários (idênticos a render-app-icon.ps1) ----------------
function HexColor([string]$hex, [int]$a = 255) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16)) }
function Mix($c1, $c2, [double]$t) { [System.Drawing.Color]::FromArgb(255, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t)) }
function WithAlpha($c, [int]$a) { [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF([single]$x, [single]$y) }
function Bez([double]$a, [double]$b, [double]$c, [double]$d, [double]$t) { $m = 1 - $t; $m*$m*$m*$a + 3*$m*$m*$t*$b + 3*$m*$t*$t*$c + $t*$t*$t*$d }
function BezD([double]$a, [double]$b, [double]$c, [double]$d, [double]$t) { $m = 1 - $t; 3*$m*$m*($b - $a) + 6*$m*$t*($c - $b) + 3*$t*$t*($d - $c) }
function Wob($list, [double]$t) { $s = 0.0; foreach ($w in $list) { $s += $w[0] * [Math]::Sin(2 * [Math]::PI * $w[1] * $t + $w[2]) }; $s }
function Prof([double]$t, [double]$tm, [double]$alpha, [double]$w0) {
  if ($t -le $tm) { $s = $t / $tm; return $w0 + (1 - $w0) * [Math]::Pow([Math]::Sin([Math]::PI / 2 * $s), $alpha) }
  $s = ($t - $tm) / (1 - $tm); [Math]::Sqrt([Math]::Max(0.0, 1 - $s * $s))
}

# ---------------- modelo da pétala Brisa (idêntico a render-app-icon.ps1) ----------------
function Get-Petal($sp, [double]$k) {
  $cnt = 200; $len0 = $sp.L; $halfW = $sp.W; $r0 = $sp.r0
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
  @{ Outline = $pts.ToArray(); Base = (& $toScreen 0 0); Tip = (& $toScreen $arU[$cnt] $arV[$cnt]) }
}

function Get-Center([double]$radius, $harm, [double]$k) {
  $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($j = 0; $j -lt 144; $j++) {
    $th = 2 * [Math]::PI * $j / 144; $rad = $radius
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
  foreach ($pt in $flower.Petals) { foreach ($q in $pt.Outline) {
    $r = [Math]::Sqrt($q.X * $q.X + $q.Y * $q.Y); if ($r -gt $maxR) { $maxR = $r } } }
  @{ maxR = $maxR }
}

# ---------------- geometria Brisa (docs/design/icon-v22/render-icon-v22.ps1, candidato 6; 1024 px de referência) ----
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
$bounds1 = Get-Bounds (Get-Flower 1.0)
"geometria Brisa: raio externo {0:N2} px (referência 1024)" -f $bounds1.maxR | Write-Host

# ---------------- aparências: as MESMAS cores de render-app-icon.ps1 $Looks.default/.dark — a tela de
# ---------------- lançamento deve ficar "idêntica ao ícone" (owner notes item 3) ----------------
$Looks = [ordered]@{
  light = @{ bgTop = '#2B3F58'; bgBot = '#1C2B40'; petal = '#F1EDE4'; tipTo = '#FFFFFF'; tip = 0.35; baseMix = 0.05; center = '#E9DCC6'; glowA = 55 }
  dark  = @{ bgTop = '#18222F'; bgBot = '#101822'; petal = '#E3DED3'; tipTo = '#F4F1EA'; tip = 0.30; baseMix = 0.06; center = '#D3C4AB'; glowA = 0 }
}
# Cor lisa da tela de lançamento (`UILaunchScreen`, project.yml): o meio do degradê do ícone — o
# formato só aceita uma cor sólida (docs/V23-UI-CONTRACT.md §4.2, ponto 1; owner notes item 3).
$LaunchBg = @{ light = '#24354C'; dark = '#141D29' }

# ---------------- render: flor + halo, fundo TRANSPARENTE, 256 pt de largura ----------------
function Render-Flower($look, [int]$scale) {
  $ptSize = 256; $px = $ptSize * $scale
  $bmp = New-Object System.Drawing.Bitmap($px, $px, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.CompositingQuality = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
  $g.Clear([System.Drawing.Color]::Transparent)
  $k = ($px / 2.0) / $bounds1.maxR
  $fl = Get-Flower $k
  $cx = $px / 2.0; $cy = $px / 2.0
  if ($look.glowA -gt 0) {
    $glowR = 430 * $k
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddEllipse([single]($cx - $glowR), [single]($cy - $glowR), [single](2 * $glowR), [single](2 * $glowR))
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp)
    $glow.CenterPoint = (P $cx $cy)
    $gc = Mix (HexColor $look.bgTop) (HexColor '#FFFFFF') 0.30
    $glow.CenterColor = [System.Drawing.Color]::FromArgb($look.glowA, $gc.R, $gc.G, $gc.B)
    $glow.SurroundColors = [System.Drawing.Color[]]@((HexColor $look.bgTop 0))
    $g.FillPath($glow, $gp); $glow.Dispose(); $gp.Dispose()
  }
  $g.TranslateTransform([single]$cx, [single]$cy)
  for ($i = 0; $i -lt 5; $i++) {
    $pt = $fl.Petals[$i]; $path = Path-Of $pt.Outline
    $base = HexColor $look.petal; $tipC = Mix $base (HexColor $look.tipTo) $look.tip
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($pt.Base, $pt.Tip, (Mix $base (HexColor $look.bgBot) $look.baseMix), $tipC)
    $lg.WrapMode = 'TileFlipXY'
    $g.FillPath($lg, $path); $lg.Dispose(); $path.Dispose()
  }
  $cp = Path-Of $fl.Center; $cc = HexColor $look.center
  $cb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 (-$Brisa.centerR * $k - 4)), (P 0 ($Brisa.centerR * $k + 4)), $cc, (Mix $cc (HexColor $look.bgTop) 0.18))
  $g.FillPath($cb, $cp); $cb.Dispose(); $cp.Dispose()
  $g.Dispose()
  $bmp
}

$images = [ordered]@{}
foreach ($appearance in @('light', 'dark')) {
  foreach ($scale in @(2, 3)) {
    $images["$appearance@${scale}x"] = Render-Flower $Looks[$appearance] $scale
  }
}
$images['light@2x'].Save((Join-Path $ImageSet 'LaunchFlower@2x.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$images['light@3x'].Save((Join-Path $ImageSet 'LaunchFlower@3x.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$images['dark@2x'].Save((Join-Path $ImageSet 'LaunchFlower-dark@2x.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$images['dark@3x'].Save((Join-Path $ImageSet 'LaunchFlower-dark@3x.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# ---------------- Contents.json (imageset e colorset) ----------------
$imageSetJson = @'
{
  "images" : [
    {
      "filename" : "LaunchFlower@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "LaunchFlower@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "LaunchFlower-dark@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "LaunchFlower-dark@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $ImageSet 'Contents.json'), $imageSetJson, (New-Object System.Text.UTF8Encoding($false)))

function HexComponents([string]$hex) {
  $h = $hex.TrimStart('#')
  @{ r = '0x' + $h.Substring(0,2).ToUpperInvariant(); g = '0x' + $h.Substring(2,2).ToUpperInvariant(); b = '0x' + $h.Substring(4,2).ToUpperInvariant() }
}
$lc = HexComponents $LaunchBg.light
$dc = HexComponents $LaunchBg.dark
$colorSetJson = @"
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "$($lc.b)",
          "green" : "$($lc.g)",
          "red" : "$($lc.r)"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "$($dc.b)",
          "green" : "$($dc.g)",
          "red" : "$($dc.r)"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"@
[System.IO.File]::WriteAllText((Join-Path $ColorSet 'Contents.json'), $colorSetJson, (New-Object System.Text.UTF8Encoding($false)))

# ---------------- folha de conferência: a flor sobre os dois fundos, nas duas aparências ----------------
$cellW = 300; $cellH = 340; $pad = 24
$sheetW = $pad * 3 + $cellW * 2
$sheetH = $pad * 3 + $cellH * 2 + 50
$sheet = New-Object System.Drawing.Bitmap $sheetW, $sheetH
$gs = [System.Drawing.Graphics]::FromImage($sheet)
$gs.SmoothingMode = 'AntiAlias'; $gs.InterpolationMode = 'HighQualityBicubic'; $gs.PixelOffsetMode = 'HighQuality'; $gs.TextRenderingHint = 'AntiAliasGridFit'
$gs.Clear((HexColor '#F2F2F7'))
$fTitle = New-Object System.Drawing.Font 'Segoe UI', 18, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fName = New-Object System.Drawing.Font 'Segoe UI', 13, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$ink = New-Object System.Drawing.SolidBrush((HexColor '#1C1C1E'))
$gs.DrawString('Magister · tela de lançamento (2.3, T9.2) — conferência', $fTitle, $ink, $pad, 16)

$appPaper = @{ light = '#F4EEE4'; dark = '#191715' }
$cells = @(
  @{ appearance = 'light'; bg = $LaunchBg.light;  label = 'Claro · tela de lançamento (UILaunchScreen)' },
  @{ appearance = 'dark';  bg = $LaunchBg.dark;   label = 'Escuro · tela de lançamento (UILaunchScreen)' },
  @{ appearance = 'light'; bg = $appPaper.light;  label = 'Claro · fundo do app (Theme.background)' },
  @{ appearance = 'dark';  bg = $appPaper.dark;   label = 'Escuro · fundo do app (Theme.background)' }
)
for ($i = 0; $i -lt $cells.Count; $i++) {
  $c = $cells[$i]; $col = $i % 2; $row = [int][Math]::Floor($i / 2.0)
  $x0 = $pad + $col * ($cellW + $pad); $y0 = 50 + $pad + $row * ($cellH + $pad)
  $bgBrush = New-Object System.Drawing.SolidBrush((HexColor $c.bg)); $gs.FillRectangle($bgBrush, $x0, $y0, $cellW, $cellH); $bgBrush.Dispose()
  $img = $images["$($c.appearance)@3x"]
  $drawSize = 220
  $gs.DrawImage($img, ($x0 + ($cellW - $drawSize) / 2), ($y0 + ($cellH - 40 - $drawSize) / 2), $drawSize, $drawSize)
  $gs.DrawString($c.label, $fName, $ink, $x0, ($y0 + $cellH - 30))
}
$sheet.Save((Join-Path $CheckDir 'launch-assets-check.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$gs.Dispose(); $sheet.Dispose()
foreach ($img in $images.Values) { $img.Dispose() }

"assets escritos em {0} e {1}; folha em {2}" -f $ImageSet, $ColorSet, (Join-Path $CheckDir 'launch-assets-check.png') | Write-Host
