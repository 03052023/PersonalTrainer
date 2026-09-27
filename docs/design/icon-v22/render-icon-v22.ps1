# render-icon-v22.ps1 — candidatos do ícone e da flor do Magister para a versão 2.2 (pedido S10 do dono: pétalas com
# mais movimento, irregularidade, organicidade e vivacidade).
#
# Continua valendo o DESIGN.md §2: 5 pétalas em gota que não se tocam (os 5 objetivos), miolo areia (a pessoa), fundo
# azul-marinho #2B3F58 → #1C2B40, leitura calma, nada de cultura de academia. O que muda é o desenho de cada pétala:
# em vez de uma gota reta e simétrica, cada pétala nasce de uma "espinha" curva (Bézier cúbica) com um perfil de
# largura próprio, o que permite giro, assimetria, ponta torcida e borda feita à mão.
#
# Toda irregularidade é DETERMINÍSTICA: são os números das tabelas $Candidates abaixo (nada de Get-Random), então rodar
# o script de novo gera exatamente os mesmos PNG.
#
# Saídas (em -OutDir; padrão: a pasta deste script):
#   v22-1-giro.png ... v22-6-brisa.png  1024x1024, opacos, aparência padrão (sem máscara: o iOS arredonda os cantos)
#   compare-v22.png                     os 6 lado a lado, prévias em 60 px sobre papel de parede claro e escuro e a
#                                       flor como fica dentro do app (FlowerView, 56 pt, pétala de Longevidade ativa)
#
# Uso: powershell -ExecutionPolicy Bypass -File docs/design/icon-v22/render-icon-v22.ps1 [-OutDir <pasta>]
param([string]$OutDir = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
if ($OutDir -eq '') { $OutDir = $here }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$S = 1024
# Cores do ícone atual (DESIGN §2); o bloco de cores de cada candidato pode sobrescrever as pétalas.
$Icon = @{ bgTop = '#2B3F58'; bgBot = '#1C2B40'; petal = '#F1EDE4'; tipTo = '#FFFFFF'; tip = 0.35; baseMix = 0.05; center = '#E9DCC6'; glowA = 55 }
# Paleta do app (DESIGN §3) para a prévia da FlowerView: pétala ativa = Longevidade (pétala 1, topo).
$App = @{
  light = @{ bg = '#F2EBE0'; line = '#6B5A4C'; active = '#56654A'; center = '#E9DCC6'; goals = @('#56654A', '#904C36', '#7A583C', '#74506A', '#4F6170') }
  dark  = @{ bg = '#1C1714'; line = '#BCAB98'; active = '#A9B98F'; center = '#D3C4AB'; goals = @('#A9B98F', '#E0927A', '#C9A27F', '#C9A0BC', '#9FB2C2') }
}

# ---------------- utilitários ----------------
function HexColor([string]$hex, [int]$a = 255) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16)) }
function Mix($c1, $c2, [double]$t) { [System.Drawing.Color]::FromArgb(255, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t)) }
function WithAlpha($c, [int]$a) { [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF([single]$x, [single]$y) }
function Merge($a, $b) { $h = @{}; foreach ($k in $a.Keys) { $h[$k] = $a[$k] }; if ($null -ne $b) { foreach ($k in $b.Keys) { $h[$k] = $b[$k] } }; $h }
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

# ---------------- modelo da pétala ----------------
# Coordenadas locais (u, v): u = para fora, a partir da base da pétala (a $r0 do centro); v = sentido horário.
# Parâmetros (todos em px do ícone de 1024):
#   r0, L, W      distância da base ao centro, comprimento, meia-largura máxima
#   tm, alpha, w0 posição da largura máxima (0–1), curvatura dos flancos, largura na base (fração de W)
#   lean          desloca a largura máxima de um lado para fora e do outro para dentro: cabeça assimétrica
#   b1, b2, b3    desvio lateral dos pontos de controle da espinha (fração de L): curva a pétala
#   tilt          inclinação da pétala em relação ao raio (graus, + = horário)
#   asym, asymK   um flanco mais cheio que o outro (+ = lado horário), crescendo para a ponta
#   wobP, wobM    ondulação de cada flanco (feito à mão)
#   fold*         torção: faixa do avesso da pétala num tom mais fundo, entre a borda do lado foldSide e uma linha
#                 que vai de foldIn0 a foldIn1 (fração da meia-largura: 1 = na borda, 0 = na espinha, < 0 = passa dela)
#   streaks       riscos de goiva vazados na pétala (ver Get-Petal)
#   ang, dAng     ângulo da pétala (graus, horário a partir do topo) e ajuste fino individual
# Atenção ao PowerShell: lista com UM item só (wobP, streaks) precisa de @(,@(...)); @(@(...)) achata a lista.
$BasePetal = @{ r0 = 70; L = 268; W = 99; tm = 0.64; alpha = 0.62; w0 = 0.0; lean = 0.0; b1 = 0.0; b2 = 0.0; b3 = 0.0; tilt = 0.0
  asym = 0.0; asymK = 1.5; wobP = @(); wobM = @(); fold = 0; foldSide = 1; foldStart = 0.0; foldIn0 = 1.0; foldIn1 = -0.4; streaks = @(); ang = 0.0; dAng = 0.0 }

function Get-Petal($sp, [double]$k) {
  # Atenção: variáveis do PowerShell não diferenciam maiúsculas; por isso os vetores têm prefixo "ar".
  $cnt = 200; $len0 = $sp.L; $halfW = $sp.W; $r0 = $sp.r0
  $q1 = $sp.b1 * $len0; $q2 = $sp.b2 * $len0; $q3 = $sp.b3 * $len0
  $tau = $sp.tilt * [Math]::PI / 180; $ct = [Math]::Cos($tau); $st = [Math]::Sin($tau)
  $angR = $sp.ang * [Math]::PI / 180; $ca = [Math]::Cos($angR); $sa = [Math]::Sin($angR)
  $arU = New-Object 'double[]' ($cnt + 1); $arV = New-Object 'double[]' ($cnt + 1); $arNU = New-Object 'double[]' ($cnt + 1); $arNV = New-Object 'double[]' ($cnt + 1)
  $arWP = New-Object 'double[]' ($cnt + 1); $arWM = New-Object 'double[]' ($cnt + 1); $arT = New-Object 'double[]' ($cnt + 1)
  for ($j = 0; $j -le $cnt; $j++) {
    $tt = (1 - [Math]::Cos([Math]::PI * $j / $cnt)) / 2   # mais amostras nas duas pontas, onde a largura muda rápido
    $su = Bez 0 ($len0/3) (2*$len0/3) $len0 $tt; $sv = Bez 0 $q1 $q2 $q3 $tt
    $du = BezD 0 ($len0/3) (2*$len0/3) $len0 $tt; $dv = BezD 0 $q1 $q2 $q3 $tt; $dl = [Math]::Sqrt($du*$du + $dv*$dv)
    $asymT = [Math]::Pow($tt, $sp.asymK)
    $arT[$j] = $tt; $arU[$j] = $su; $arV[$j] = $sv; $arNU[$j] = -$dv / $dl; $arNV[$j] = $du / $dl
    $arWP[$j] = $halfW * (Prof $tt ($sp.tm + $sp.lean) $sp.alpha $sp.w0) * (1 + $sp.asym * $asymT) * (1 + (Wob $sp.wobP $tt))
    $arWM[$j] = $halfW * (Prof $tt ($sp.tm - $sp.lean) $sp.alpha $sp.w0) * (1 - $sp.asym * $asymT) * (1 + (Wob $sp.wobM $tt))
  }
  # (u, v) → tela, com o centro da flor em (0, 0) e escala $k
  $toScreen = {
    param([double]$pu, [double]$pv)
    $u2 = $pu * $ct - $pv * $st; $v2 = $pu * $st + $pv * $ct
    $x = $v2; $y = -($r0 + $u2)
    New-Object System.Drawing.PointF([single]($k * ($x * $ca - $y * $sa)), [single]($k * ($x * $sa + $y * $ca)))
  }
  $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($j = 0; $j -le $cnt; $j++) { $pts.Add((& $toScreen ($arU[$j] + $arNU[$j] * $arWP[$j]) ($arV[$j] + $arNV[$j] * $arWP[$j]))) }
  for ($j = $cnt - 1; $j -ge 0; $j--) { $pts.Add((& $toScreen ($arU[$j] - $arNU[$j] * $arWM[$j]) ($arV[$j] - $arNV[$j] * $arWM[$j]))) }
  # Com w0 = 0 e alpha < 1 a base já sai arredondada (tangente perpendicular à espinha). Com w0 > 0, fecha a base com
  # uma meia-circunferência atrás do ponto inicial da espinha.
  if ($sp.w0 -gt 0) {
    $cu = ($arWP[0] - $arWM[0]) / 2 * $arNU[0]; $cv = ($arWP[0] - $arWM[0]) / 2 * $arNV[0]; $rr = ($arWP[0] + $arWM[0]) / 2
    $tu = $arNV[0]; $tv = -$arNU[0]
    for ($m = 1; $m -lt 24; $m++) {
      $phi = [Math]::PI * $m / 24
      $pts.Add((& $toScreen ($cu + $rr * (-[Math]::Cos($phi) * $arNU[0] - [Math]::Sin($phi) * $tu)) ($cv + $rr * (-[Math]::Cos($phi) * $arNV[0] - [Math]::Sin($phi) * $tv))))
    }
  }
  $fold = $null
  if ($sp.fold -eq 1) {
    $sd = $sp.foldSide; $fold = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $inner = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($j = 0; $j -le $cnt; $j++) {
      if ($arT[$j] -lt $sp.foldStart) { continue }
      $wSide = if ($sd -gt 0) { $arWP[$j] } else { $arWM[$j] }
      $fs = ($arT[$j] - $sp.foldStart) / (1 - $sp.foldStart); $sm = $fs * $fs * (3 - 2 * $fs)
      $fold.Add((& $toScreen ($arU[$j] + $sd * $arNU[$j] * $wSide * 1.02) ($arV[$j] + $sd * $arNV[$j] * $wSide * 1.02)))
      $wi = $wSide * ($sp.foldIn0 + ($sp.foldIn1 - $sp.foldIn0) * $sm)
      $inner.Add((& $toScreen ($arU[$j] + $sd * $arNU[$j] * $wi) ($arV[$j] + $sd * $arNV[$j] * $wi)))
    }
    for ($j = $inner.Count - 1; $j -ge 0; $j--) { $fold.Add($inner[$j]) }
  }
  # Riscos de goiva: fendas finas ao longo da espinha, que viram furos no preenchimento (modo par-ímpar).
  # Cada item de streaks é @(deslocamento lateral em fração da meia-largura, t inicial, t final, meia-espessura px).
  $holes = @()
  foreach ($stk in $sp.streaks) {
    $sideA = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'; $sideB = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($j = 0; $j -le $cnt; $j++) {
      if ($arT[$j] -lt $stk[1] -or $arT[$j] -gt $stk[2]) { continue }
      $f = ($arT[$j] - $stk[1]) / ($stk[2] - $stk[1]); $hh = $stk[3] * [Math]::Pow([Math]::Sin([Math]::PI * $f), 0.7)
      $wS = if ($stk[0] -ge 0) { $arWP[$j] } else { $arWM[$j] }
      $off = $stk[0] * $wS
      $sideA.Add((& $toScreen ($arU[$j] + $arNU[$j] * ($off + $hh)) ($arV[$j] + $arNV[$j] * ($off + $hh))))
      $sideB.Add((& $toScreen ($arU[$j] + $arNU[$j] * ($off - $hh)) ($arV[$j] + $arNV[$j] * ($off - $hh))))
    }
    for ($j = $sideB.Count - 1; $j -ge 0; $j--) { $sideA.Add($sideB[$j]) }
    $holes += ,($sideA.ToArray())
  }
  $mid = [int]($cnt * 0.42)
  @{
    Holes   = $holes
    Outline = $pts.ToArray()
    Fold    = if ($null -ne $fold) { $fold.ToArray() } else { $null }
    Base    = (& $toScreen 0 0)
    Tip     = (& $toScreen $arU[$cnt] $arV[$cnt])
    Mid     = (& $toScreen $arU[$mid] $arV[$mid])
    MidN    = (& $toScreen ($arU[$mid] + $arNU[$mid] * $halfW) ($arV[$mid] + $arNV[$mid] * $halfW))
  }
}

# Miolo: círculo, ou disco levemente irregular (harmônicos fixos) nas versões feitas à mão.
function Get-Center([double]$radius, $harm, [double]$k) {
  $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
  for ($j = 0; $j -lt 144; $j++) {
    $th = 2 * [Math]::PI * $j / 144; $rad = $radius
    foreach ($h in $harm) { $rad += $radius * $h[0] * [Math]::Sin($h[1] * $th + $h[2]) }
    $pts.Add((P ($k * $rad * [Math]::Sin($th)) (-$k * $rad * [Math]::Cos($th))))
  }
  $pts.ToArray()
}

function Get-Flower($cand, [double]$k) {
  $petals = @()
  for ($i = 0; $i -lt 5; $i++) {
    $sp = Merge (Merge $BasePetal $cand.common) $cand.per[$i]
    $sp.ang = $cand.rot + 72 * $i + $sp.dAng
    $petals += ,(Get-Petal $sp $k)
  }
  @{ Petals = $petals; Center = (Get-Center $cand.centerR $cand.centerHarm $k) }
}

function Path-Of($pts) { $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddPolygon($pts); $p }

# ---------------- candidatos ----------------
# Cada candidato: common = parâmetros de todas as pétalas; per = ajustes de cada pétala (1 = topo, sentido horário);
# colors = cor base de cada pétala; light = sombreado de volume (@(alfa da luz, alfa da sombra)) por pétala.
$Candidates = [ordered]@{}

# 1 · Giro — prefloração contorta (vinca, jasmim-manga, espirradeira): as cinco pétalas curvam no mesmo sentido,
# iguais entre si. É a direção de mais movimento: a flor parece estar abrindo.
$Candidates['giro'] = @{
  file = 'v22-1-giro.png'; title = '1 · Giro'; caption = 'gotas curvas no mesmo sentido, iguais entre si'
  rot = -8; scale = 0.965
  common = @{ W = 97; tm = 0.61; alpha = 0.70; lean = 0.02; b1 = 0.02; b2 = 0.15; b3 = 0.36; tilt = -17; asym = 0.10; asymK = 1.2 }
  per = @(@{}, @{}, @{}, @{}, @{})
  colors = @('#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4'); light = @(0, 26)
  centerR = 52; centerHarm = @()
}

# 2 · À mão — a gota atual, recortada à mão: cada pétala com comprimento, largura, ângulo e inclinação um pouco
# diferentes, borda com ondulação lenta e miolo que não é um círculo perfeito. A mudança mais conservadora.
$Candidates['mao'] = @{
  file = 'v22-2-mao.png'; title = '2 · À mão'; caption = 'a gota atual, recortada à mão'
  rot = 0
  common = @{ W = 99 }
  per = @(
    @{ L = 272; W = 97;  dAng = 0.0;   tilt = -4.0; b2 = 0.05;   b3 = 0.07;  lean = 0.04;  wobP = @(,@(0.026, 1.6, 0.4)); wobM = @(,@(0.020, 2.1, 2.2)) },
    @{ L = 250; W = 105; dAng = 2.0;   tilt = 5.0;  b2 = -0.04;  b3 = -0.06; lean = -0.05; wobP = @(,@(0.022, 1.9, 1.1)); wobM = @(,@(0.028, 1.4, 4.0)) },
    @{ L = 278; W = 94;  dAng = 0.5;  tilt = -3.5; b2 = 0.06;   b3 = 0.08;  lean = 0.03;  wobP = @(,@(0.020, 2.3, 5.0)); wobM = @(,@(0.024, 1.7, 0.9)) },
    @{ L = 256; W = 101; dAng = -1.5;  tilt = 3.0;  b2 = -0.035; b3 = -0.05; lean = -0.04; wobP = @(,@(0.028, 1.5, 3.3)); wobM = @(,@(0.018, 2.4, 1.8)) },
    @{ L = 266; W = 97;  dAng = -2.0;  tilt = -3.5; b2 = 0.035;  b3 = 0.05;  lean = 0.06;  wobP = @(,@(0.022, 2.0, 2.7)); wobM = @(,@(0.020, 1.8, 5.6)) }
  )
  colors = @('#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4'); light = @(0, 0)
  centerR = 52; centerHarm = @(@(0.040, 2, 0.6), @(0.028, 3, 2.1))
}

# 3 · Torcida — cada pétala gira sobre si mesma: perto do miolo ela está de frente, e a ponta vira e mostra o avesso
# num tom de areia; a divisa atravessa a pétala na diagonal. Mesmo a 60 px, os cinco avessos desenham o giro.
$Candidates['torcida'] = @{
  file = 'v22-3-torcida.png'; title = '3 · Torcida'; caption = 'a ponta vira e mostra o avesso, em areia'
  rot = -4
  common = @{ W = 100; tm = 0.62; alpha = 0.66; lean = 0.05; b2 = 0.06; b3 = 0.14; tilt = -7; asym = 0.10; asymK = 1.4
              fold = 1; foldSide = 1; foldStart = 0.12; foldIn0 = 1.0; foldIn1 = -0.30 }
  per = @(@{}, @{}, @{}, @{}, @{})
  colors = @('#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4'); light = @(0, 0); foldColor = '#D6CAB6'
  centerR = 52; centerHarm = @()
}

# 4 · Tons — a forma da Brisa com a ponta de cada pétala corada, bem de leve, na cor do objetivo que ela representa
# no app (sálvia, terracota, argila, ameixa, ardósia): a base continua creme e a cor só aparece na borda de fora,
# como nas flores de verdade. A vivacidade vem da cor, sem virar pétala colorida.
$Candidates['tons'] = @{
  file = 'v22-4-tons.png'; title = '4 · Tons'; caption = 'ponta corada na cor de cada objetivo'
  rot = -3
  common = @{ W = 99; tm = 0.63; alpha = 0.66; asymK = 1.3 }
  per = @(
    @{ L = 268; W = 98;  dAng = 0.0;   tilt = -8;  b2 = 0.08; b3 = 0.19; lean = 0.05; asym = 0.10; wobP = @(,@(0.018, 1.6, 0.4)); wobM = @(,@(0.015, 2.1, 2.2)) },
    @{ L = 253; W = 103; dAng = 2.5;   tilt = -5;  b2 = 0.06; b3 = 0.14; lean = 0.02; asym = 0.08; wobP = @(,@(0.016, 1.9, 1.1)); wobM = @(,@(0.018, 1.4, 4.0)) },
    @{ L = 272; W = 96;  dAng = 1.0;  tilt = -10; b2 = 0.09; b3 = 0.21; lean = 0.06; asym = 0.12; wobP = @(,@(0.015, 2.3, 5.0)); wobM = @(,@(0.016, 1.7, 0.9)) },
    @{ L = 258; W = 101; dAng = -1.0;  tilt = -6;  b2 = 0.07; b3 = 0.15; lean = 0.03; asym = 0.09; wobP = @(,@(0.018, 1.5, 3.3)); wobM = @(,@(0.014, 2.4, 1.8)) },
    @{ L = 263; W = 98;  dAng = -2.5; tilt = -9;  b2 = 0.08; b3 = 0.18; lean = 0.05; asym = 0.11; wobP = @(,@(0.016, 2.0, 2.7)); wobM = @(,@(0.017, 1.8, 5.6)) }
  )
  colors = @('#F3EFE7', '#F3EFE7', '#F3EFE7', '#F3EFE7', '#F3EFE7'); light = @(0, 0)
  # DESIGN §3, cores de objetivo do modo escuro (as claras do app): Longevidade, Hipertrofia, Força, Combate, Resistência
  tips = @('#A9B98F', '#E0927A', '#C9A27F', '#C9A0BC', '#9FB2C2'); tipAmt = 0.45
  centerR = 52; centerHarm = @(@(0.025, 2, 0.6), @(0.018, 3, 2.1))
}

# 5 · Traço — pétala talhada à mão, como numa xilogravura: borda de faca levemente irregular, cauda fina junto ao
# miolo e dois riscos de goiva que saem da base (lembram as nervuras da pétala). O traço de mão fica no
# desenho, com cinco formas largas (nunca riscos finos soltos, para não virar asterisco).
$Candidates['traco'] = @{
  file = 'v22-5-traco.png'; title = '5 · Traço'; caption = 'borda de faca e riscos de goiva (xilogravura)'
  rot = 2
  common = @{ r0 = 66; W = 104; tm = 0.64; alpha = 0.95; w0 = 0.0; asymK = 1.1 }
  per = @(
    @{ L = 272; W = 103; dAng = 0.0;   tilt = -5; b2 = 0.06; b3 = 0.10; lean = 0.06;  asym = 0.07
       wobP = @(@(0.030, 1.3, 0.3), @(0.012, 3.6, 1.9)); wobM = @(@(0.026, 1.7, 2.6), @(0.010, 4.3, 4.4))
       streaks = @(@(0.30, 0.10, 0.46, 2.7), @(-0.36, 0.12, 0.36, 2.2)) },
    @{ L = 254; W = 108; dAng = 2.0;   tilt = -2; b2 = 0.08; b3 = 0.12; lean = -0.04; asym = 0.05
       wobP = @(@(0.032, 1.5, 1.4), @(0.010, 4.0, 0.2)); wobM = @(@(0.024, 1.2, 4.7), @(0.012, 3.2, 2.9))
       streaks = @(@(-0.28, 0.08, 0.42, 2.6), @(0.40, 0.12, 0.32, 2.1)) },
    @{ L = 278; W = 99;  dAng = 1.5;  tilt = -7; b2 = 0.05; b3 = 0.08; lean = 0.05;  asym = 0.09
       wobP = @(@(0.026, 1.8, 3.9), @(0.012, 3.4, 5.5)); wobM = @(@(0.030, 1.4, 0.8), @(0.010, 4.6, 1.6))
       streaks = @(@(0.26, 0.10, 0.48, 2.7), @(-0.30, 0.14, 0.34, 2.1)) },
    @{ L = 260; W = 106; dAng = -1.0;  tilt = -3; b2 = 0.07; b3 = 0.12; lean = -0.05; asym = 0.06
       wobP = @(@(0.030, 1.6, 5.1), @(0.010, 4.2, 3.3)); wobM = @(@(0.026, 1.9, 3.2), @(0.012, 3.8, 0.5))
       streaks = @(@(0.36, 0.12, 0.44, 2.4), @(-0.26, 0.10, 0.30, 2.1)) },
    @{ L = 266; W = 101; dAng = -2.5; tilt = -8; b2 = 0.06; b3 = 0.09; lean = 0.07;  asym = 0.08
       wobP = @(@(0.028, 1.4, 2.2), @(0.012, 3.9, 4.8)); wobM = @(@(0.030, 1.6, 5.9), @(0.010, 4.4, 2.1))
       streaks = @(@(-0.32, 0.10, 0.44, 2.6), @(0.30, 0.13, 0.33, 2.1)) }
  )
  colors = @('#F3EFE6', '#F3EFE6', '#F3EFE6', '#F3EFE6', '#F3EFE6'); light = @(0, 0)
  centerR = 50; centerHarm = @(@(0.06, 2, 1.1), @(0.035, 3, 4.0), @(0.02, 5, 2.2))
}

# 6 · Brisa — o giro da 1 mais leve, com a irregularidade da 2: cada pétala curva um pouco diferente, como uma flor
# de verdade mexida pelo vento. Junta movimento, mão e calma.
$Candidates['brisa'] = @{
  file = 'v22-6-brisa.png'; title = '6 · Brisa'; caption = 'giro leve + irregularidade de mão'
  rot = -5
  common = @{ W = 98; tm = 0.62; alpha = 0.68; asymK = 1.3 }
  per = @(
    @{ L = 270; W = 97;  dAng = 0.0;   tilt = -11; b2 = 0.10; b3 = 0.26; lean = 0.06; asym = 0.12; wobP = @(,@(0.020, 1.6, 0.4)); wobM = @(,@(0.016, 2.1, 2.2)) },
    @{ L = 252; W = 103; dAng = 2.5;   tilt = -7;  b2 = 0.07; b3 = 0.18; lean = 0.03; asym = 0.09; wobP = @(,@(0.018, 1.9, 1.1)); wobM = @(,@(0.020, 1.4, 4.0)) },
    @{ L = 275; W = 95;  dAng = 1.0;  tilt = -14; b2 = 0.12; b3 = 0.30; lean = 0.07; asym = 0.14; wobP = @(,@(0.016, 2.3, 5.0)); wobM = @(,@(0.018, 1.7, 0.9)) },
    @{ L = 257; W = 101; dAng = -1.0;  tilt = -8;  b2 = 0.08; b3 = 0.20; lean = 0.04; asym = 0.10; wobP = @(,@(0.020, 1.5, 3.3)); wobM = @(,@(0.015, 2.4, 1.8)) },
    @{ L = 264; W = 97;  dAng = -2.5; tilt = -12; b2 = 0.10; b3 = 0.25; lean = 0.06; asym = 0.12; wobP = @(,@(0.018, 2.0, 2.7)); wobM = @(,@(0.019, 1.8, 5.6)) }
  )
  colors = @('#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4', '#F1EDE4'); light = @(0, 18)
  centerR = 52; centerHarm = @(@(0.025, 2, 0.6), @(0.018, 3, 2.1))
}

# ---------------- desenho ----------------
function Get-Bounds($flower) {
  $minX = 1e9; $maxX = -1e9; $minY = 1e9; $maxY = -1e9; $maxR = 0
  foreach ($pt in $flower.Petals) { foreach ($q in $pt.Outline) {
    if ($q.X -lt $minX) { $minX = $q.X }; if ($q.X -gt $maxX) { $maxX = $q.X }; if ($q.Y -lt $minY) { $minY = $q.Y }; if ($q.Y -gt $maxY) { $maxY = $q.Y }
    $r = [Math]::Sqrt($q.X * $q.X + $q.Y * $q.Y); if ($r -gt $maxR) { $maxR = $r } } }
  @{ minX = $minX; maxX = $maxX; minY = $minY; maxY = $maxY; maxR = $maxR }
}

# Menor distância entre pétalas vizinhas e entre pétala e miolo (px do ícone de 1024): mede se "as pétalas não se
# tocam" continua verdade e se o vão sobrevive a 60 px (1 px a 60 px = 17 px no 1024).
function Get-Gaps($flower) {
  $minPP = 1e9; $minPC = 1e9
  $sub = @(); foreach ($pt in $flower.Petals) { $o = $pt.Outline; $l = @(); for ($j = 0; $j -lt $o.Count; $j += 3) { $l += ,$o[$j] }; $sub += ,$l }
  $pairs = @()
  for ($i = 0; $i -lt 5; $i++) {
    $a = $sub[$i]; $b = $sub[($i + 1) % 5]; $minPair = 1e9
    foreach ($p in $a) { foreach ($q in $b) { $dx = $p.X - $q.X; $dy = $p.Y - $q.Y; $d = $dx*$dx + $dy*$dy; if ($d -lt $minPair) { $minPair = $d } } }
    $pairs += [Math]::Round([Math]::Sqrt($minPair)); if ($minPair -lt $minPP) { $minPP = $minPair }
    foreach ($p in $a) { $d = [Math]::Sqrt($p.X*$p.X + $p.Y*$p.Y); if ($d -lt $minPC) { $minPC = $d } }
  }
  $cR = 0; foreach ($q in $flower.Center) { $r = [Math]::Sqrt($q.X*$q.X + $q.Y*$q.Y); if ($r -gt $cR) { $cR = $r } }
  @{ petal = [Math]::Sqrt($minPP); center = $minPC - $cR; pairs = ($pairs -join '/') }
}

function Render-Icon($cand) {
  $scale = if ($null -ne $cand.scale) { $cand.scale } else { 1.0 }
  $fl = Get-Flower $cand $scale
  $bd = Get-Bounds $fl
  $cx = $S / 2.0 - ($bd.minX + $bd.maxX) / 2.0; $cy = $S / 2.0 - ($bd.minY + $bd.maxY) / 2.0
  $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.CompositingQuality = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 -2), (P 0 ($S + 2)), (HexColor $Icon.bgTop), (HexColor $Icon.bgBot))
  $g.FillRectangle($bg, 0, 0, $S, $S); $bg.Dispose()
  $glowR = 430; $gp = New-Object System.Drawing.Drawing2D.GraphicsPath; $gp.AddEllipse([single]($cx - $glowR), [single]($cy - $glowR), [single](2*$glowR), [single](2*$glowR))
  $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp); $glow.CenterPoint = (P $cx $cy)
  $gc = Mix (HexColor $Icon.bgTop) (HexColor '#FFFFFF') 0.30
  $glow.CenterColor = WithAlpha $gc $Icon.glowA; $glow.SurroundColors = [System.Drawing.Color[]]@((HexColor $Icon.bgTop 0))
  $g.FillPath($glow, $gp); $glow.Dispose(); $gp.Dispose()
  $g.TranslateTransform([single]$cx, [single]$cy)
  $navy = HexColor $Icon.bgBot; $white = HexColor '#FFFFFF'
  for ($i = 0; $i -lt 5; $i++) {
    $pt = $fl.Petals[$i]; $path = Path-Of $pt.Outline
    foreach ($hole in $pt.Holes) { $path.AddPolygon($hole) }   # FillMode Alternate: as fendas ficam vazadas
    $base = HexColor $cand.colors[$i]
    $tipC = Mix $base (HexColor $Icon.tipTo) $Icon.tip
    if ($null -ne $cand.tips) { $tipC = Mix $base (HexColor $cand.tips[$i]) $cand.tipAmt }
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($pt.Base, $pt.Tip, (Mix $base $navy $Icon.baseMix), $tipC)
    if ($null -ne $cand.tips) {
      # a cor aparece só na metade de fora, como nas pétalas de verdade que colorem da borda para dentro
      $bl = New-Object System.Drawing.Drawing2D.Blend(4); $bl.Positions = [single[]]@(0, 0.40, 0.75, 1); $bl.Factors = [single[]]@(0, 0.05, 0.55, 1); $lg.Blend = $bl
    }
    $lg.WrapMode = 'TileFlipXY'; $g.FillPath($lg, $path); $lg.Dispose()
    if ($null -ne $pt.Fold) {
      $g.SetClip($path, [System.Drawing.Drawing2D.CombineMode]::Replace)
      $fp = Path-Of $pt.Fold; $fc = HexColor $cand.foldColor
      $fb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($pt.Base, $pt.Tip, (Mix $fc $base 0.55), $fc); $fb.WrapMode = 'TileFlipXY'
      $g.FillPath($fb, $fp); $fb.Dispose(); $fp.Dispose(); $g.ResetClip()
    }
    if ($cand.light[0] -gt 0 -or $cand.light[1] -gt 0) {
      # volume: luz num flanco e sombra no outro. Com lightDir, a luz é a mesma para a flor toda (cada pétala fica
      # com um tom próprio conforme a direção em que aponta); sem, o flanco anti-horário fica na sombra (giro).
      if ($null -ne $cand.lightDir) {
        $ldx = $cand.lightDir[0] * 110; $ldy = $cand.lightDir[1] * 110
        $pa = P ($pt.Mid.X + $ldx) ($pt.Mid.Y + $ldy); $pb = P ($pt.Mid.X - $ldx) ($pt.Mid.Y - $ldy)
      } else { $pa = $pt.MidN; $pb = P (2 * $pt.Mid.X - $pt.MidN.X) (2 * $pt.Mid.Y - $pt.MidN.Y) }
      $sh = New-Object System.Drawing.Drawing2D.LinearGradientBrush($pa, $pb, (WithAlpha $white $cand.light[0]), (WithAlpha (HexColor '#6E6150') $cand.light[1]))
      $sh.WrapMode = 'TileFlipXY'; $g.FillPath($sh, $path); $sh.Dispose()
    }
    $path.Dispose()
  }
  $cp = Path-Of $fl.Center; $cc = HexColor $Icon.center
  $cb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 (-$cand.centerR - 4)), (P 0 ($cand.centerR + 4)), $cc, (Mix $cc (HexColor $Icon.bgTop) 0.18))
  $g.FillPath($cb, $cp); $cb.Dispose(); $cp.Dispose(); $g.Dispose()
  $gaps = Get-Gaps $fl
  "{0,-8} símbolo {1:N0} x {2:N0} px, raio externo {3:N0} px (recorte do Watch: 512), vão mínimo entre pétalas {4:N1} px ({6}), pétala-miolo {5:N1} px" -f $cand.title.Split(' ')[-1], ($bd.maxX - $bd.minX), ($bd.maxY - $bd.minY), $bd.maxR, $gaps.petal, $gaps.center, $gaps.pairs | Write-Host
  $bmp
}

# Redução em etapas de 1/2 (a bicúbica do GDI+ serrilha em reduções grandes de uma vez só).
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

# Como a flor fica dentro do app (FlowerView): mesma geometria, pétala ativa preenchida com a cor do objetivo e as
# outras em contorno de 1,5 pt em textSecondary; $size = diâmetro ponta a ponta em px (56 pt @2x = 112 px).
function Draw-AppFlower($g, $cand, [double]$cx, [double]$cy, [double]$size, $pal) {
  $fl = Get-Flower $cand 1.0; $bd = Get-Bounds $fl; $k = ($size / 2) / $bd.maxR
  $fl = Get-Flower $cand $k
  $state = $g.Save(); $g.TranslateTransform([single]$cx, [single]$cy)
  $pen = New-Object System.Drawing.Pen((HexColor $pal.line), 3.0); $pen.LineJoin = 'Round'
  for ($i = 0; $i -lt 5; $i++) {
    $pt = $fl.Petals[$i]; $path = Path-Of $pt.Outline
    if ($i -eq 0) {
      $br = New-Object System.Drawing.SolidBrush((HexColor $pal.active)); $g.FillPath($br, $path); $br.Dispose()
      # Torcida: o avesso da pétala ativa num tom mais fundo da cor do objetivo
      if ($null -ne $pt.Fold) {
        $g.SetClip($path, [System.Drawing.Drawing2D.CombineMode]::Intersect)
        $fp = Path-Of $pt.Fold; $fb = New-Object System.Drawing.SolidBrush((Mix (HexColor $pal.active) (HexColor '#000000') 0.24))
        $g.FillPath($fb, $fp); $fb.Dispose(); $fp.Dispose(); $g.ResetClip()
      }
    } else {
      # Tons: cada pétala inativa tem o contorno na cor do próprio objetivo, em vez de textSecondary
      if ($null -ne $cand.tips) { $gp2 = New-Object System.Drawing.Pen((HexColor $pal.goals[$i]), 3.0); $gp2.LineJoin = 'Round'; $g.DrawPath($gp2, $path); $gp2.Dispose() }
      else { $g.DrawPath($pen, $path) }
    }
    $path.Dispose()
  }
  $cp = Path-Of $fl.Center; $br = New-Object System.Drawing.SolidBrush((HexColor $pal.center)); $g.FillPath($br, $cp); $br.Dispose(); $cp.Dispose()
  $pen.Dispose(); $g.Restore($state)
}

$icons = [ordered]@{}
foreach ($key in $Candidates.Keys) {
  $c = $Candidates[$key]; $bmp = Render-Icon $c
  $bmp.Save((Join-Path $OutDir $c.file), [System.Drawing.Imaging.ImageFormat]::Png); $icons[$key] = $bmp
}

# ---------------- folha de comparação ----------------
$cellW = 610; $cellH = 380; $mg = 24; $top = 70
$stripY = $top + 2 * $cellH + 10; $stripH = 118
$SW = 3 * $cellW + 2 * $mg; $SH = $stripY + 2 * $stripH + 70
$sheet = New-Object System.Drawing.Bitmap $SW, $SH
$gs = [System.Drawing.Graphics]::FromImage($sheet)
$gs.SmoothingMode = 'AntiAlias'; $gs.InterpolationMode = 'HighQualityBicubic'; $gs.PixelOffsetMode = 'HighQuality'; $gs.TextRenderingHint = 'AntiAliasGridFit'
$gs.Clear((HexColor '#F2F2F7'))
$fTitle = New-Object System.Drawing.Font 'Segoe UI', 22, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fName = New-Object System.Drawing.Font 'Segoe UI', 19, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fCap = New-Object System.Drawing.Font 'Segoe UI', 14, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$fSmall = New-Object System.Drawing.Font 'Segoe UI', 12, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$ink = New-Object System.Drawing.SolidBrush((HexColor '#1C1C1E')); $ink2 = New-Object System.Drawing.SolidBrush((HexColor '#6B6B70'))
$inkW = New-Object System.Drawing.SolidBrush((HexColor '#EDEDF0'))
$gs.DrawString('Magister · ícone v2.2 (S10): seis direções com mais movimento', $fTitle, $ink, $mg, 20)

$n = 0
foreach ($key in $Candidates.Keys) {
  $c = $Candidates[$key]
  $x0 = $mg + ($n % 3) * $cellW; $y0 = $top + [Math]::Floor($n / 3) * $cellH
  $gs.DrawString($c.title, $fName, $ink, $x0, $y0)
  $gs.DrawString($c.caption, $fCap, $ink2, $x0, ($y0 + 26))
  Draw-Masked $gs $icons[$key] $x0 ($y0 + 54) 290
  $rx = $x0 + 310
  # 60 px sobre papel de parede claro e escuro
  $gs.DrawString('60 px', $fSmall, $ink2, $rx, ($y0 + 54))
  $b1 = New-Object System.Drawing.SolidBrush((HexColor '#FFFFFF')); $gs.FillRectangle($b1, $rx, ($y0 + 72), 130, 96); $b1.Dispose()
  $b2 = New-Object System.Drawing.SolidBrush((HexColor '#1C1C1E')); $gs.FillRectangle($b2, ($rx + 134), ($y0 + 72), 130, 96); $b2.Dispose()
  Draw-Masked $gs $icons[$key] ($rx + 35) ($y0 + 90) 60
  Draw-Masked $gs $icons[$key] ($rx + 169) ($y0 + 90) 60
  # dentro do app
  $gs.DrawString('No app (FlowerView 56 pt, Longevidade ativa)', $fSmall, $ink2, $rx, ($y0 + 180))
  $b3 = New-Object System.Drawing.SolidBrush((HexColor $App.light.bg)); $gs.FillRectangle($b3, $rx, ($y0 + 198), 130, 146); $b3.Dispose()
  $b4 = New-Object System.Drawing.SolidBrush((HexColor $App.dark.bg)); $gs.FillRectangle($b4, ($rx + 134), ($y0 + 198), 130, 146); $b4.Dispose()
  Draw-AppFlower $gs $c ($rx + 65) ($y0 + 271) 112 $App.light
  Draw-AppFlower $gs $c ($rx + 199) ($y0 + 271) 112 $App.dark
  $n++
}

# tira da tela inicial: atual + 6 candidatos a 60 px, papel de parede claro e escuro
$current = $null
$curPath = Join-Path $repo 'PersonalTrainer\Resources\Assets.xcassets\AppIcon.appiconset\AppIcon.png'
if (Test-Path $curPath) { $current = [System.Drawing.Bitmap]::FromFile($curPath) }
$row = @(); if ($null -ne $current) { $row += ,@('atual', $current) }
foreach ($key in $Candidates.Keys) { $row += ,@($Candidates[$key].title, $icons[$key]) }
$strips = @(@{ bg = '#FFFFFF'; y = $stripY; txt = $ink }, @{ bg = '#1C1C1E'; y = ($stripY + $stripH + 8); txt = $inkW })
foreach ($st in $strips) {
  $bb = New-Object System.Drawing.SolidBrush((HexColor $st.bg)); $gs.FillRectangle($bb, $mg, $st.y, ($SW - 2 * $mg), $stripH); $bb.Dispose()
  $step = ($SW - 2 * $mg) / $row.Count
  for ($j = 0; $j -lt $row.Count; $j++) {
    $ix = $mg + $j * $step + ($step - 60) / 2
    Draw-Masked $gs $row[$j][1] $ix ($st.y + 16) 60
    $sz = $gs.MeasureString($row[$j][0], $fSmall)
    $gs.DrawString($row[$j][0], $fSmall, $st.txt, [single]($mg + $j * $step + ($step - $sz.Width) / 2), [single]($st.y + 84))
  }
}
$gs.DrawString('Tela inicial a 60 px (fundo claro e escuro). Irregularidade determinística: rode o script de novo e sai igual.', $fCap, $ink2, $mg, ($SH - 40))
$cmpFile = Join-Path $OutDir 'compare-v22.png'
$sheet.Save($cmpFile, [System.Drawing.Imaging.ImageFormat]::Png)
$gs.Dispose(); $sheet.Dispose()
if ($null -ne $current) { $current.Dispose() }
foreach ($k in $icons.Keys) { $icons[$k].Dispose() }
Write-Host ("comparação: " + $cmpFile)
