# render-app-icon.ps1 — ícone final do Magister. Desde a 2.2 (decisão do dono, 2026-09-27, SPEC decisão 18,
# `docs/V22-CONTRACT.md` tarefa `flower`), o desenho é o candidato "6 · Brisa" escolhido em
# `docs/design/icon-v22/render-icon-v22.ps1`: cinco pétalas em gota que nascem de uma espinha levemente curva e giram
# um pouco no mesmo sentido, como uma flor mexida pelo vento, miolo areia levemente irregular, sobre azul-marinho
# (`#2B3F58` → `#1C2B40`). Sem texto, sem cantos arredondados (o iOS aplica a máscara), sem sombra pintada; só um halo
# muito leve e um sombreado de volume discreto atrás/sobre a flor na aparência padrão (DESIGN.md §2).
#
# Toda irregularidade é DETERMINÍSTICA (os números de $Brisa abaixo, nada de Get-Random): rodar o script de novo dá
# exatamente os mesmos PNG (mesmo SHA-256).
#
# Saídas:
#   <IconSet>\AppIcon.png         1024x1024, opaco — aparência padrão
#   <IconSet>\AppIcon-dark.png    1024x1024, opaco — aparência escura (iOS 18+)
#   <IconSet>\AppIcon-tinted.png  1024x1024, opaco, tons de cinza — aparência tingida (iOS 18+)
#   <CheckDir>\AppIcon-checks.png folha de conferência: as 3 aparências, 60 px sobre papel de parede claro e escuro,
#                                 e a FlowerView do app (56 pt, Longevidade ativa) nos dois fundos do app
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

$S = 1024

# ---------------- aparências (DESIGN §2) ----------------
# `light` = sombreado de volume por pétala (@(alfa da luz, alfa da sombra), 0-255): só a padrão tem, igual ao
# candidato Brisa do gerador de ícones v2.2. `glowA` = alfa do halo atrás da flor.
$Looks = [ordered]@{
  default = @{ bgTop = '#2B3F58'; bgBot = '#1C2B40'; petal = '#F1EDE4'; tipTo = '#FFFFFF'; tip = 0.35; baseMix = 0.05; center = '#E9DCC6'; glowA = 55; gray = $false; light = @(0, 18) }
  dark    = @{ bgTop = '#18222F'; bgBot = '#101822'; petal = '#E3DED3'; tipTo = '#F4F1EA'; tip = 0.30; baseMix = 0.06; center = '#D3C4AB'; glowA = 0;  gray = $false; light = @(0, 0) }
  tinted  = @{ bgTop = '#000000'; bgBot = '#000000'; petal = '#E4E4E4'; tipTo = '#FAFAFA'; tip = 0.40; baseMix = 0.04; center = '#BDBDBD'; glowA = 0;  gray = $true;  light = @(0, 0) }
}

# ---------------- geometria Brisa (parâmetros de $Candidates['brisa'] em docs/design/icon-v22/render-icon-v22.ps1)
# ---------------- (1024 px de referência) ----------------
# r0, tm, alpha, w0, asymK são comuns às 5 pétalas; cada uma tem seu próprio comprimento (L), meia-largura (W),
# ajuste de ângulo (dAng), inclinação (tilt), curva da espinha (b2, b3), lean e assimetria (asym), mais a ondulação
# de borda feita à mão (wobP/wobM). `rot` é o giro geral da flor. Ver `render-icon-v22.ps1` para o modelo completo
# (com pétalas torcidas, riscadas etc.); aqui só a Brisa, que não usa base alargada (w0 = 0), torção nem riscos.
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

# Paleta do app (DESIGN §3, tokens `background`/`textSecondary`/`goalLongevity`/`flowerCenter`), só para a folha de
# conferência mostrar a `FlowerView` de verdade (Longevidade ativa, pétala 1, topo).
$App = @{
  light = @{ bg = '#F2EBE0'; line = '#6B5A4C'; active = '#56654A'; center = '#E9DCC6' }
  dark  = @{ bg = '#1C1714'; line = '#BCAB98'; active = '#A9B98F'; center = '#D3C4AB' }
}

# ---------------- utilitários ----------------
function HexColor([string]$hex, [int]$a = 255) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16)) }
function Mix($c1, $c2, [double]$t) { [System.Drawing.Color]::FromArgb(255, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t)) }
function WithAlpha($c, [int]$a) { [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function Lin([double]$v) { $v = $v / 255.0; if ($v -le 0.04045) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) } }
function RelLum($c) { 0.2126 * (Lin $c.R) + 0.7152 * (Lin $c.G) + 0.0722 * (Lin $c.B) }
function Contrast($a, $b) { $la = RelLum $a; $lb = RelLum $b; ([Math]::Max($la,$lb) + 0.05) / ([Math]::Min($la,$lb) + 0.05) }
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF([single]$x, [single]$y) }
function Bez([double]$a, [double]$b, [double]$c, [double]$d, [double]$t) { $m = 1 - $t; $m*$m*$m*$a + 3*$m*$m*$t*$b + 3*$m*$t*$t*$c + $t*$t*$t*$d }
function BezD([double]$a, [double]$b, [double]$c, [double]$d, [double]$t) { $m = 1 - $t; 3*$m*$m*($b - $a) + 6*$m*$t*($c - $b) + 3*$t*$t*($d - $c) }
# Ondulação de borda "feita à mão": soma de senos de baixa frequência com fases fixas; cada item é @(amplitude, ciclos, fase).
function Wob($list, [double]$t) { $s = 0.0; foreach ($w in $list) { $s += $w[0] * [Math]::Sin(2 * [Math]::PI * $w[1] * $t + $w[2]) }; $s }
# Perfil de largura ao longo da pétala (0 = junto ao miolo, 1 = ponta): sobe em seno até a largura máxima em $tm e
# fecha num quarto de elipse, que dá a ponta redonda da gota.
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

# ---------------- modelo da pétala Brisa ----------------
# Coordenadas locais (u, v): u = para fora, a partir da base da pétala (a r0 do centro); v = sentido horário.
# A Brisa não usa base alargada (w0 = 0: a base já sai arredondada, tangente perpendicular à espinha), torção nem
# riscos, então `Get-Petal` só precisa do contorno.
function Get-Petal($sp, [double]$k) {
  $cnt = 200; $len0 = $sp.L; $halfW = $sp.W; $r0 = $sp.r0
  $q1 = $sp.b1 * $len0; $q2 = $sp.b2 * $len0; $q3 = $sp.b3 * $len0
  $tau = $sp.tilt * [Math]::PI / 180; $ct = [Math]::Cos($tau); $st = [Math]::Sin($tau)
  $angR = $sp.ang * [Math]::PI / 180; $ca = [Math]::Cos($angR); $sa = [Math]::Sin($angR)
  $arU = New-Object 'double[]' ($cnt + 1); $arV = New-Object 'double[]' ($cnt + 1); $arNU = New-Object 'double[]' ($cnt + 1); $arNV = New-Object 'double[]' ($cnt + 1)
  $arWP = New-Object 'double[]' ($cnt + 1); $arWM = New-Object 'double[]' ($cnt + 1)
  for ($j = 0; $j -le $cnt; $j++) {
    $tt = (1 - [Math]::Cos([Math]::PI * $j / $cnt)) / 2   # mais amostras nas duas pontas, onde a largura muda rápido
    $su = Bez 0 ($len0/3) (2*$len0/3) $len0 $tt; $sv = Bez 0 $q1 $q2 $q3 $tt
    $du = BezD 0 ($len0/3) (2*$len0/3) $len0 $tt; $dv = BezD 0 $q1 $q2 $q3 $tt; $dl = [Math]::Sqrt($du*$du + $dv*$dv)
    $asymT = [Math]::Pow($tt, $sp.asymK)
    $arU[$j] = $su; $arV[$j] = $sv; $arNU[$j] = -$dv / $dl; $arNV[$j] = $du / $dl
    $arWP[$j] = $halfW * (Prof $tt ($sp.tm + $sp.lean) $sp.alpha $sp.w0) * (1 + $sp.asym * $asymT) * (1 + (Wob $sp.wobP $tt))
    $arWM[$j] = $halfW * (Prof $tt ($sp.tm - $sp.lean) $sp.alpha $sp.w0) * (1 - $sp.asym * $asymT) * (1 + (Wob $sp.wobM $tt))
  }
  # (u, v) → tela, com o centro da flor em (0, 0) e escala $k: primeiro inclina (tilt) em torno da base da pétala,
  # depois afasta $r0 do centro e, por fim, gira pelo ângulo total da pétala ($sp.ang = giro geral + 72°×i + dAng).
  $toScreen = {
    param([double]$pu, [double]$pv)
    $u2 = $pu * $ct - $pv * $st; $v2 = $pu * $st + $pv * $ct
    $x = $v2; $y = -($r0 + $u2)
    New-Object System.Drawing.PointF([single]($k * ($x * $ca - $y * $sa)), [single]($k * ($x * $sa + $y * $ca)))
  }
  $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($j = 0; $j -le $cnt; $j++) { $pts.Add((& $toScreen ($arU[$j] + $arNU[$j] * $arWP[$j]) ($arV[$j] + $arNV[$j] * $arWP[$j]))) }
  for ($j = $cnt - 1; $j -ge 0; $j--) { $pts.Add((& $toScreen ($arU[$j] - $arNU[$j] * $arWM[$j]) ($arV[$j] - $arNV[$j] * $arWM[$j]))) }
  $mid = [int]($cnt * 0.42)
  @{
    Outline = $pts.ToArray()
    Base    = (& $toScreen 0 0)
    Tip     = (& $toScreen $arU[$cnt] $arV[$cnt])
    Mid     = (& $toScreen $arU[$mid] $arV[$mid])
    MidN    = (& $toScreen ($arU[$mid] + $arNU[$mid] * $halfW) ($arV[$mid] + $arNV[$mid] * $halfW))
  }
}

# Miolo: disco levemente irregular (harmônicos fixos, $Brisa.centerHarm), não um círculo perfeito.
function Get-Center([double]$radius, $harm, [double]$k) {
  $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($j = 0; $j -lt 144; $j++) {
    $th = 2 * [Math]::PI * $j / 144; $rad = $radius
    foreach ($h in $harm) { $rad += $radius * $h[0] * [Math]::Sin($h[1] * $th + $h[2]) }
    $pts.Add((P ($k * $rad * [Math]::Sin($th)) (-$k * $rad * [Math]::Cos($th))))
  }
  $pts.ToArray()
}

# As 5 pétalas de $Brisa (pétala i usa $Brisa.per[i], o giro geral $Brisa.rot e o dAng dela) + o miolo, numa escala $k.
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
  $minX = 1e9; $maxX = -1e9; $minY = 1e9; $maxY = -1e9; $maxR = 0
  foreach ($pt in $flower.Petals) { foreach ($q in $pt.Outline) {
    if ($q.X -lt $minX) { $minX = $q.X }; if ($q.X -gt $maxX) { $maxX = $q.X }; if ($q.Y -lt $minY) { $minY = $q.Y }; if ($q.Y -gt $maxY) { $maxY = $q.Y }
    $r = [Math]::Sqrt($q.X * $q.X + $q.Y * $q.Y); if ($r -gt $maxR) { $maxR = $r } } }
  @{ minX = $minX; maxX = $maxX; minY = $minY; maxY = $maxY; maxR = $maxR }
}

# Menor distância entre pétalas vizinhas e entre pétala e miolo (px do ícone de 1024): confirma que "as pétalas não
# se tocam" continua verdade e se o vão sobrevive a 60 px (1 px a 60 px = 17 px no 1024).
function Get-Gaps($flower) {
  $minPP = 1e9; $minPC = 1e9
  $sub = @(); foreach ($pt in $flower.Petals) { $o = $pt.Outline; $l = @(); for ($j = 0; $j -lt $o.Count; $j += 3) { $l += ,$o[$j] }; $sub += ,$l }
  for ($i = 0; $i -lt 5; $i++) {
    $a = $sub[$i]; $b = $sub[($i + 1) % 5]; $minPair = 1e9
    foreach ($p in $a) { foreach ($q in $b) { $dx = $p.X - $q.X; $dy = $p.Y - $q.Y; $d = $dx*$dx + $dy*$dy; if ($d -lt $minPair) { $minPair = $d } } }
    if ($minPair -lt $minPP) { $minPP = $minPair }
    foreach ($p in $a) { $d = [Math]::Sqrt($p.X*$p.X + $p.Y*$p.Y); if ($d -lt $minPC) { $minPC = $d } }
  }
  $cR = 0; foreach ($q in $flower.Center) { $r = [Math]::Sqrt($q.X*$q.X + $q.Y*$q.Y); if ($r -gt $cR) { $cR = $r } }
  @{ petal = [Math]::Sqrt($minPP); center = $minPC - $cR }
}

# ---------------- geometria (uma vez; não depende da aparência) ----------------
$flowerAt1 = Get-Flower 1.0
$bounds1 = Get-Bounds $flowerAt1
$gaps1 = Get-Gaps $flowerAt1
$cx = $S / 2.0 - ($bounds1.minX + $bounds1.maxX) / 2.0; $cy = $S / 2.0 - ($bounds1.minY + $bounds1.maxY) / 2.0
"geometria Brisa (1024 px): símbolo {0:N0} x {1:N0} px, raio externo {2:N0} px (recorte do Watch: 512), vão mínimo entre pétalas {3:N1} px, pétala-miolo {4:N1} px" -f ($bounds1.maxX - $bounds1.minX), ($bounds1.maxY - $bounds1.minY), $bounds1.maxR, $gaps1.petal, $gaps1.center | Write-Host

# ---------------- render do ícone 1024 ----------------
function Render-Icon($look) {
  $fl = Get-Flower 1.0
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
  $g.TranslateTransform([single]$cx, [single]$cy)
  $white = HexColor '#FFFFFF'
  for ($i = 0; $i -lt 5; $i++) {
    $pt = $fl.Petals[$i]; $path = Path-Of $pt.Outline
    $base = HexColor $look.petal; $tipC = Mix $base (HexColor $look.tipTo) $look.tip
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($pt.Base, $pt.Tip, (Mix $base (HexColor $look.bgBot) $look.baseMix), $tipC); $lg.WrapMode = 'TileFlipXY'
    $g.FillPath($lg, $path); $lg.Dispose()
    if ($look.light[0] -gt 0 -or $look.light[1] -gt 0) {
      # volume: luz num flanco e sombra no outro, na direção que a pétala aponta (mesma ideia do candidato Brisa).
      $pa = $pt.MidN; $pb = P (2 * $pt.Mid.X - $pt.MidN.X) (2 * $pt.Mid.Y - $pt.MidN.Y)
      $sh = New-Object System.Drawing.Drawing2D.LinearGradientBrush($pa, $pb, (WithAlpha $white $look.light[0]), (WithAlpha (HexColor '#6E6150') $look.light[1])); $sh.WrapMode = 'TileFlipXY'
      $g.FillPath($sh, $path); $sh.Dispose()
    }
    $path.Dispose()
  }
  $cp = Path-Of $fl.Center; $cc = HexColor $look.center
  $cb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 (-$Brisa.centerR - 4)), (P 0 ($Brisa.centerR + 4)), $cc, (Mix $cc (HexColor $look.bgTop) 0.18))
  $g.FillPath($cb, $cp); $cb.Dispose(); $cp.Dispose(); $g.Dispose()
  if ($look.gray) {
    # garante tons de cinza puros (R = G = B), que é o que o iOS espera na aparência tingida: a mesma soma
    # ponderada vai para os três canais.
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

# ---------------- reduções de qualidade (progressivas, em etapas de 1/2: a bicúbica do GDI+ serrilha em reduções
# ---------------- grandes de uma vez só, e 1024 → 60 px é 17x) ----------------
function Scale-Down($src, [int]$size) {
  $cur = $src; $own = $false
  while ($cur.Width -ge 2 * $size) {
    $n = [int]($cur.Width / 2); $nb = New-Object System.Drawing.Bitmap($n, $n)
    $gg = [System.Drawing.Graphics]::FromImage($nb); $gg.InterpolationMode = 'HighQualityBicubic'; $gg.PixelOffsetMode = 'HighQuality'
    $gg.DrawImage($cur, (New-Object System.Drawing.Rectangle 0, 0, $n, $n)); $gg.Dispose()
    if ($own) { $cur.Dispose() }; $cur = $nb; $own = $true
  }
  $out = New-Object System.Drawing.Bitmap($size, $size)
  $gg = [System.Drawing.Graphics]::FromImage($out); $gg.InterpolationMode = 'HighQualityBicubic'; $gg.PixelOffsetMode = 'HighQuality'
  $gg.DrawImage($cur, (New-Object System.Drawing.Rectangle 0, 0, $size, $size)); $gg.Dispose()
  if ($own) { $cur.Dispose() }
  $out
}
function Draw-Masked($g, $bmp, [double]$x, [double]$y, [int]$size) {
  $small = Scale-Down $bmp $size
  $rr = New-RoundRect $x $y $size $size ($size * 0.225)
  $g.SetClip($rr); $g.DrawImage($small, [single]$x, [single]$y, [single]$size, [single]$size); $g.ResetClip(); $rr.Dispose(); $small.Dispose()
}

# Como a flor fica dentro do app (`FlowerView`): mesma geometria, pétala ativa (Longevidade, i = 0) preenchida com a
# cor dela e as outras em contorno de 1,5 pt (aqui 3 px, na escala de preview) em `textSecondary`; $size = diâmetro
# ponta a ponta em px.
function Draw-AppFlower($g, [double]$cx2, [double]$cy2, [double]$size, $pal) {
  $k = ($size / 2) / $bounds1.maxR
  $fl = Get-Flower $k
  $state = $g.Save(); $g.TranslateTransform([single]$cx2, [single]$cy2)
  $pen = New-Object System.Drawing.Pen((HexColor $pal.line), 3.0); $pen.LineJoin = 'Round'
  for ($i = 0; $i -lt 5; $i++) {
    $pt = $fl.Petals[$i]; $path = Path-Of $pt.Outline
    if ($i -eq 0) { $br = New-Object System.Drawing.SolidBrush((HexColor $pal.active)); $g.FillPath($br, $path); $br.Dispose() }
    else { $g.DrawPath($pen, $path) }
    $path.Dispose()
  }
  $cp = Path-Of $fl.Center; $br = New-Object System.Drawing.SolidBrush((HexColor $pal.center)); $g.FillPath($br, $cp); $br.Dispose(); $cp.Dispose()
  $pen.Dispose(); $g.Restore($state)
}

# ---------------- folha de conferência ----------------
$W = 940; $mg = 30
$row1Y = 55; $row1H = 246 + 40
$row2Y = $row1Y + $row1H + 30; $row2H = 3 * 120
$row3Y = $row2Y + $row2H + 30; $row3H = 146 + 30
$H = $row3Y + $row3H + 30
$sheet = New-Object System.Drawing.Bitmap $W, $H
$gs = [System.Drawing.Graphics]::FromImage($sheet)
$gs.SmoothingMode = 'AntiAlias'; $gs.InterpolationMode = 'HighQualityBicubic'; $gs.PixelOffsetMode = 'HighQuality'; $gs.TextRenderingHint = 'AntiAliasGridFit'
$gs.Clear((HexColor '#F2F2F7'))
$fTitle = New-Object System.Drawing.Font 'Segoe UI', 18, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fName = New-Object System.Drawing.Font 'Segoe UI', 15, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fSmall = New-Object System.Drawing.Font 'Segoe UI', 12, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$ink = New-Object System.Drawing.SolidBrush((HexColor '#1C1C1E')); $ink2 = New-Object System.Drawing.SolidBrush((HexColor '#6B6B70'))
$gs.DrawString('Magister · ícone Brisa (2.2) — conferência', $fTitle, $ink, $mg, 18)

# linha 1: as 3 aparências, grandes
$names = @{ default = 'Padrão'; dark = 'Modo escuro'; tinted = 'Tingido (o iOS pinta por cima)' }
$i = 0
foreach ($k in $icons.Keys) {
  $x0 = $mg + $i * 300
  Draw-Masked $gs $icons[$k] $x0 $row1Y 246
  $gs.DrawString($names[$k], $fName, $ink, $x0, ($row1Y + 246 + 6))
  $i++
}

# linha 2: 60 px sobre papel de parede claro e escuro, para as 3 aparências
$gs.DrawString('60 px sobre papel de parede claro e escuro', $fName, $ink, $mg, ($row2Y - 26))
$i = 0
foreach ($k in $icons.Keys) {
  $y0 = $row2Y + $i * 120
  $gs.DrawString($names[$k], $fSmall, $ink2, $mg, ($y0 + 30))
  $bx = $mg + 160
  $b1 = New-Object System.Drawing.SolidBrush((HexColor '#FFFFFF')); $gs.FillRectangle($b1, $bx, $y0, 96, 96); $b1.Dispose()
  $b2 = New-Object System.Drawing.SolidBrush((HexColor '#1C1C1E')); $gs.FillRectangle($b2, ($bx + 110), $y0, 96, 96); $b2.Dispose()
  Draw-Masked $gs $icons[$k] ($bx + 18) ($y0 + 18) 60
  Draw-Masked $gs $icons[$k] ($bx + 128) ($y0 + 18) 60
  $i++
}

# linha 3: a FlowerView do app (56 pt, Longevidade ativa), no fundo claro e escuro do app
$gs.DrawString('A flor do app (FlowerView, 56 pt, Longevidade ativa)', $fName, $ink, $mg, ($row3Y - 26))
$b3 = New-Object System.Drawing.SolidBrush((HexColor $App.light.bg)); $gs.FillRectangle($b3, $mg, $row3Y, 146, 146); $b3.Dispose()
$b4 = New-Object System.Drawing.SolidBrush((HexColor $App.dark.bg)); $gs.FillRectangle($b4, ($mg + 166), $row3Y, 146, 146); $b4.Dispose()
Draw-AppFlower $gs ($mg + 73) ($row3Y + 73) 56 $App.light
Draw-AppFlower $gs ($mg + 166 + 73) ($row3Y + 73) 56 $App.dark

$checkFile = Join-Path $CheckDir 'AppIcon-checks.png'
$sheet.Save($checkFile, [System.Drawing.Imaging.ImageFormat]::Png)
$gs.Dispose(); $sheet.Dispose()
foreach ($k in $icons.Keys) { $icons[$k].Dispose() }

# ---------------- medidas para o DESIGN.md ----------------
$d = $Looks.default
"pétala creme x fundo (topo / base): {0:N2}:1 / {1:N2}:1; miolo x fundo: {2:N2}:1" -f (Contrast (HexColor $d.petal) (HexColor $d.bgTop)), (Contrast (HexColor $d.petal) (HexColor $d.bgBot)), (Contrast (HexColor $d.center) (HexColor $d.bgTop))
"escuro: pétala x fundo {0:N2}:1; bloco padrão x papel claro #F2F2F7 {1:N2}:1, x escuro #1C1C1E {2:N2}:1" -f (Contrast (HexColor $Looks.dark.petal) (HexColor $Looks.dark.bgTop)), (Contrast (HexColor $d.bgTop) (HexColor '#F2F2F7')), (Contrast (HexColor $d.bgBot) (HexColor '#1C1C1E'))
"conferência: " + $checkFile
