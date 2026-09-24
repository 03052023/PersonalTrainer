# render-exercise-guides.ps1 — protótipo da "Frente 3" (ilustração própria) do botão "Como fazer".
#
# Desenha o manequim neutro do Magister a partir de DADOS DE POSE (exercise-guides.sample.json), com o mesmo
# algoritmo que o app usaria em SwiftUI (Canvas + TimelineView):
#   1. interpolação: para um instante t entre dois quadros-chave, cada ângulo de segmento vai pelo arco mais curto,
#      com easeInOut (senoide);
#   2. cinemática direta: a partir do quadril, soma segmentos de comprimento fixo (proporções de estatura de
#      Winter) nas direções absolutas interpoladas;
#   3. âncora: translada o corpo inteiro para que a articulação-âncora (tornozelo no agachamento, quadril no banco)
#      fique sempre no mesmo ponto — é isso que impede os pés de "escorregar" no meio do movimento;
#   4. IK de dois ossos (lei dos cossenos) para os braços quando as mãos seguram algo com posição definida
#      (barra nas costas, pegada por quadro), com um vetor de dica para o lado do cotovelo;
#   5. desenho em camadas: equipamento de fundo -> membros do lado de lá (tom claro, levemente deslocados) ->
#      equipamento do meio -> tronco e cabeça -> perna e braço do lado de cá -> equipamento da frente.
#
# Saídas (na pasta do script, ou em -Out):
#   <slug>-1-inicio.png, <slug>-2-fim.png  quadros-chave de cada exercício, inclusive os extras (640x640)
#   interpolation-strip.png                5 instantes por exercício (t = 0, 25, 50, 75, 100%) para conferir âncora e IK
#   compare.png                            folha de comparação: os 3 exercícios lado a lado com textos em pt-BR
#   compare-dark.png                       a mesma folha na aparência escura (tokens escuros do DESIGN.md §3)
#   bonus-front-view.png                   extra: guias marcados com "bonus": true (aqui, vista frontal da elevação lateral)
#
# Uso: powershell -ExecutionPolicy Bypass -File render-exercise-guides.ps1 [-Data <json>] [-Catalog <exercises.v2.json>] [-Out <pasta>]
param([string]$Data = '', [string]$Catalog = '', [string]$Out = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Data -eq '') { $Data = Join-Path $here 'exercise-guides.sample.json' }
if ($Catalog -eq '') { $Catalog = 'C:\Users\leona\Developer\PersonalTrainer\PersonalTrainer\Resources\Seed\exercises.v2.json' }
if ($Out -eq '') { $Out = $here }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

# ---------------------------------------------------------------- vetor 2D (mundo: x para a frente, y para cima)
class V2 {
  [double]$X; [double]$Y
  V2([double]$x, [double]$y) { $this.X = $x; $this.Y = $y }
  [V2] Plus([V2]$o) { return [V2]::new($this.X + $o.X, $this.Y + $o.Y) }
  [V2] Minus([V2]$o) { return [V2]::new($this.X - $o.X, $this.Y - $o.Y) }
  [V2] Times([double]$k) { return [V2]::new($this.X * $k, $this.Y * $k) }
  [double] Dot([V2]$o) { return $this.X * $o.X + $this.Y * $o.Y }
  [double] Len() { return [Math]::Sqrt($this.X * $this.X + $this.Y * $this.Y) }
  [V2] Unit() { $l = $this.Len(); if ($l -lt 1e-9) { return [V2]::new(1, 0) }; return [V2]::new($this.X / $l, $this.Y / $l) }
  [V2] Perp() { return [V2]::new(-$this.Y, $this.X) }
  [V2] Rotated([double]$deg) { $r = $deg * [Math]::PI / 180.0; $c = [Math]::Cos($r); $s = [Math]::Sin($r); return [V2]::new($this.X * $c - $this.Y * $s, $this.X * $s + $this.Y * $c) }
  static [V2] Dir([double]$deg) { $r = $deg * [Math]::PI / 180.0; return [V2]::new([Math]::Cos($r), [Math]::Sin($r)) }
  static [V2] Lerp([V2]$a, [V2]$b, [double]$u) { return [V2]::new($a.X + ($b.X - $a.X) * $u, $a.Y + ($b.Y - $a.Y) * $u) }
}
function Vec($arr) { [V2]::new([double]$arr[0], [double]$arr[1]) }

# ---------------------------------------------------------------- cores (DESIGN.md §3)
function HexColor([string]$hex, [int]$a = 255) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16)) }
function Mix($c1, $c2, [double]$t) { [System.Drawing.Color]::FromArgb(255, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t)) }
function WithAlpha($c, [int]$a) { [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
$Tokens = @{
  light = @{ page = '#F2EBE0'; surface = '#FAF6F0'; text = '#33281F'; text2 = '#6B5A4C'; accent = '#355A7C'; accentSoft = '#DDE5EC' }
  dark  = @{ page = '#1C1714'; surface = '#29221C'; text = '#F0E7DA'; text2 = '#BCAB98'; accent = '#9DBAD6'; accentSoft = '#26323E' }
}
function New-Ink([string]$look) {
  $t = $Tokens[$look]
  $surface = HexColor $t.surface; $accent = HexColor $t.accent; $text2 = HexColor $t.text2
  @{
    page = HexColor $t.page; surface = $surface; text = HexColor $t.text; text2 = $text2; accentSoft = HexColor $t.accentSoft
    body = $accent                                  # manequim, lado de cá
    far = Mix $accent $surface 0.50                 # lado de lá: mesmo matiz, mais claro
    ghost = Mix $accent $surface 0.86               # posição anterior (só no quadro final)
    equipLine = Mix $text2 $surface 0.12            # barra, cabo, polia
    equipFill = Mix $text2 $surface 0.52            # estofado, anilhas
    equipSoft = Mix $text2 $surface 0.74            # estrutura, torre
    floor = Mix $text2 $surface 0.70
    cue = Mix $text2 $surface 0.18
  }
}

# ---------------------------------------------------------------- manequim (unidade = estatura; Winter 2009)
$Rig = @{ trunk = 0.288; neck = 0.122; thigh = 0.245; shin = 0.246; foot = 0.125; upperArm = 0.186; forearm = 0.190 }
$Rad = @{ hip = 0.058; chest = 0.063; neck = 0.022; head = 0.061; thighTop = 0.050; knee = 0.034; kneeLow = 0.031; ankle = 0.022
          heel = 0.017; toe = 0.012; shoulder = 0.031; elbow = 0.025; elbowLow = 0.023; wrist = 0.018; hand = 0.024; plate = 0.074 }
$FarShift = [V2]::new(-0.016, 0.013)   # câmera levemente acima e à frente: o lado de lá aparece um pouco atrás e acima

# ---------------------------------------------------------------- interpolação
function LerpAngle([double]$a, [double]$b, [double]$u) { $d = (($b - $a + 540.0) % 360.0) - 180.0; $a + $d * $u }
function Ease([double]$u) { 0.5 - 0.5 * [Math]::Cos([Math]::PI * [Math]::Max(0.0, [Math]::Min(1.0, $u))) }
function NumOr($v, [double]$d) { if ($null -eq $v) { $d } else { [double]$v } }
function DepthPair($v, $default) {
  if ($null -eq $v) { return ,$default }
  if ($v -is [System.Array]) { return ,@([double]$v[0], [double]$v[1]) }
  return ,@([double]$v, [double]$v)
}

# Tempo do loop (segundos) -> t contínuo entre quadros. Segmentos: pausa no 1º quadro, ida, pausa no último, volta.
function Get-LoopT($Gd, [double]$seconds) {
  $tm = $Gd.timing; $hold = NumOr $tm.hold 0.4; $go = NumOr $tm.toEnd 1.4; $back = NumOr $tm.toStart 1.4
  $last = $Gd.frames.Count - 1; $cycle = 2 * $hold + $go + $back; $s = $seconds % $cycle
  if ($s -lt $hold) { return 0.0 }
  $s -= $hold; if ($s -lt $go) { return $last * $s / $go }
  $s -= $go; if ($s -lt $hold) { return [double]$last }
  $s -= $hold; return $last * (1.0 - $s / $back)
}

# Dois ossos: ombro S, alvo T, comprimentos a e b, dica (graus) para o lado do cotovelo.
function Solve-TwoBone([V2]$S, [V2]$T, [double]$a, [double]$b, [double]$hintDeg) {
  $d = $T.Minus($S); $dist = $d.Len()
  $dist = [Math]::Max([Math]::Abs($a - $b) + 1e-4, [Math]::Min($a + $b - 1e-4, $dist))
  $u = $d.Unit(); $end = $S.Plus($u.Times($dist))
  $x = ($a * $a - $b * $b + $dist * $dist) / (2 * $dist); $h = [Math]::Sqrt([Math]::Max(0.0, $a * $a - $x * $x))
  $n = $u.Perp(); if ($n.Dot([V2]::Dir($hintDeg)) -lt 0) { $n = $n.Times(-1) }
  @{ elbow = $S.Plus($u.Times($x)).Plus($n.Times($h)); end = $end }
}

# Vista frontal: mesmos nomes de ângulo, medidos no plano frontal. O lado "de cá" é o lado direito da tela
# (0 = para fora); o outro lado é espelhado (180 - a), então exercícios simétricos descrevem um lado só.
function MirrorAng([double]$a, [double]$k) { if ($k -gt 0) { $a } else { 180.0 - $a } }
function Solve-Front($Gd, $ang) {
  $P = @{}; $P.hip = [V2]::new(0, 0)
  $up = [V2]::Dir($ang.trunk); $side = [V2]::Dir($ang.trunk - 90)
  $P.neckBase = $P.hip.Plus($up.Times($Rig.trunk))
  $P.head = $P.neckBase.Plus([V2]::Dir($ang.neck).Times($Rig.neck))
  foreach ($sd in @(@('', 1.0), @('Far', -1.0))) {
    $s = $sd[0]; $k = $sd[1]
    $P['shoulder' + $s] = $P.neckBase.Plus($side.Times(0.118 * $k)).Minus($up.Times(0.012))
    $P['hipJ' + $s] = $P.hip.Plus($side.Times(0.085 * $k))
    $P['elbow' + $s] = $P['shoulder' + $s].Plus([V2]::Dir((MirrorAng $ang['upperArm' + $s] $k)).Times($Rig.upperArm))
    $P['hand' + $s] = $P['elbow' + $s].Plus([V2]::Dir((MirrorAng $ang['forearm' + $s] $k)).Times($Rig.forearm))
    $P['knee' + $s] = $P['hipJ' + $s].Plus([V2]::Dir((MirrorAng $ang['thigh' + $s] $k)).Times($Rig.thigh))
    $P['ankle' + $s] = $P['knee' + $s].Plus([V2]::Dir((MirrorAng $ang['shin' + $s] $k)).Times($Rig.shin))
    $P['toe' + $s] = $P['ankle' + $s].Plus([V2]::new(0.03 * $k, -0.026))
  }
  $off = (Vec $Gd.anchor.at).Minus($P[$Gd.anchor.joint])
  foreach ($key in @($P.Keys)) { $P[$key] = $P[$key].Plus($off) }
  $props = @{}
  foreach ($pr in $Gd.props) { if ($pr.attach -eq 'hand') { $props[$pr.id] = $P.hand; $props[$pr.id + 'Far'] = $P.handFar } }
  @{ P = $P; props = $props; ang = $ang; front = $true }
}

# Resolve a pose num instante t (0 .. n-1) e devolve pontos do corpo e dos acessórios em coordenadas do mundo.
function Solve-Guide($Gd, [double]$t) {
  $n = $Gd.frames.Count
  $i = [Math]::Max(0, [Math]::Min([int][Math]::Floor($t), $n - 2)); $u = Ease ($t - $i)
  $A = $Gd.frames[$i]; $B = $Gd.frames[$i + 1]
  $ang = @{}
  foreach ($k in 'trunk','neck','thigh','shin','foot','upperArm','forearm','thighFar','shinFar','footFar','upperArmFar','forearmFar') {
    $va = $A.pose.$k; $vb = $B.pose.$k
    if ($null -ne $va -and $null -ne $vb) { $ang[$k] = LerpAngle ([double]$va) ([double]$vb) $u }
  }
  foreach ($k in 'thigh','shin','foot','upperArm','forearm') { if (-not $ang.ContainsKey($k + 'Far') -and $ang.ContainsKey($k)) { $ang[$k + 'Far'] = $ang[$k] } }

  if ($Gd.view -eq 'front') { return Solve-Front $Gd $ang }

  $P = @{}
  $P.hip = [V2]::new(0, 0)
  $P.shoulder = $P.hip.Plus([V2]::Dir($ang.trunk).Times($Rig.trunk))
  $P.head = $P.shoulder.Plus([V2]::Dir($ang.neck).Times($Rig.neck))
  foreach ($s in '', 'Far') {
    $P['knee' + $s] = $P.hip.Plus([V2]::Dir($ang['thigh' + $s]).Times($Rig.thigh))
    $P['ankle' + $s] = $P['knee' + $s].Plus([V2]::Dir($ang['shin' + $s]).Times($Rig.shin))
    $P['toe' + $s] = $P['ankle' + $s].Plus([V2]::Dir($ang['foot' + $s]).Times($Rig.foot))
    $P['heel' + $s] = $P['ankle' + $s].Plus(([V2]::new(-0.035, -0.026)).Rotated($ang['foot' + $s]))
  }
  # âncora
  $off = (Vec $Gd.anchor.at).Minus($P[$Gd.anchor.joint])
  foreach ($key in @($P.Keys)) { $P[$key] = $P[$key].Plus($off) }

  $up = [V2]::Dir($ang.trunk); $fwd = [V2]::Dir($ang.trunk - 90)
  $props = @{}
  foreach ($pr in $Gd.props) { if ($pr.attach -eq 'back') { $props[$pr.id] = $P.shoulder.Plus($fwd.Times([double]$pr.offset[0])).Plus($up.Times([double]$pr.offset[1])) } }

  # braços: IK até a pegada do quadro (interpolada) ou até um acessório; senão, ângulos diretos
  $arms = $Gd.arms
  # escorço: fator de projeção de cada segmento do braço no plano do desenho ([braço, antebraço] ou um número só)
  $dA = DepthPair $A.armDepth (DepthPair $arms.depth @(1.0, 1.0)); $dB = DepthPair $B.armDepth (DepthPair $arms.depth @(1.0, 1.0))
  $ua = $Rig.upperArm * ($dA[0] + ($dB[0] - $dA[0]) * $u); $fa = $Rig.forearm * ($dA[1] + ($dB[1] - $dA[1]) * $u)
  if ($arms -and $arms.reach) {
    if ($arms.reach -eq 'grip') { $target = [V2]::Lerp((Vec $A.grip), (Vec $B.grip), $u) } else { $target = $props[$arms.reach] }
    $hint = LerpAngle (NumOr $A.elbow (NumOr $arms.elbow -90)) (NumOr $B.elbow (NumOr $arms.elbow -90)) $u
    $ik = Solve-TwoBone $P.shoulder $target $ua $fa $hint
    $P.elbow = $ik.elbow; $P.hand = $ik.end; $P.elbowFar = $ik.elbow; $P.handFar = $ik.end
  } else {
    foreach ($s in '', 'Far') {
      $P['elbow' + $s] = $P.shoulder.Plus([V2]::Dir($ang['upperArm' + $s]).Times($ua))
      $P['hand' + $s] = $P['elbow' + $s].Plus([V2]::Dir($ang['forearm' + $s]).Times($fa))
    }
  }
  foreach ($pr in $Gd.props) { if ($pr.attach -eq 'hand') { $props[$pr.id] = $P.hand } }
  @{ P = $P; props = $props; ang = $ang }
}

# ---------------------------------------------------------------- câmera
$script:sc = 100.0; $script:ox = 0.0; $script:oy = 0.0
function ToS([V2]$w) { [V2]::new($script:ox + $w.X * $script:sc, $script:oy - $w.Y * $script:sc) }
function PF([V2]$v) { New-Object System.Drawing.PointF([single]$v.X, [single]$v.Y) }

function Get-Bounds($Gd) {
  $b = @{ minX = 1e9; maxX = -1e9; minY = 0.0; maxY = -1e9 }
  $grow = { param($x1, $y1, $x2, $y2) $b.minX = [Math]::Min($b.minX, $x1); $b.maxX = [Math]::Max($b.maxX, $x2); $b.minY = [Math]::Min($b.minY, $y1); $b.maxY = [Math]::Max($b.maxY, $y2) }
  $last = $Gd.frames.Count - 1
  for ($t = 0.0; $t -le $last + 1e-6; $t += 0.1) {
    $sol = Solve-Guide $Gd $t
    foreach ($p in $sol.P.Values) { & $grow ($p.X - 0.066) ($p.Y - 0.066) ($p.X + 0.066) ($p.Y + 0.066) }
    foreach ($k in $sol.props.Keys) { $p = $sol.props[$k]; & $grow ($p.X - $Rad.plate) ($p.Y - $Rad.plate) ($p.X + $Rad.plate) ($p.Y + $Rad.plate) }
  }
  foreach ($s in $Gd.scene) {
    switch ($s.kind) {
      'bench'     { & $grow ([double]$s.x) 0 ([double]$s.x + [double]$s.length) ([double]$s.top) }
      'seat'      { & $grow ([double]$s.x) 0 ([double]$s.x + [double]$s.length) ([double]$s.top) }
      'rail'      { & $grow ([double]$s.x1) 0 ([double]$s.x2) 0.04 }
      'tower'     { & $grow ([double]$s.x) 0 ([double]$s.x + [double]$s.width) ([double]$s.height) }
      default     { }
    }
  }
  $b
}
function Set-Camera([System.Drawing.RectangleF]$r, $bounds, [double]$scale, [double]$bottomPad) {
  $script:sc = $scale
  $cx = ($bounds.minX + $bounds.maxX) / 2.0
  $script:ox = $r.X + $r.Width / 2.0 - $cx * $scale
  $script:oy = $r.Bottom - $bottomPad + $bounds.minY * $scale
}

# ---------------------------------------------------------------- primitivas
function New-HullPath([V2]$c1, [double]$r1, [V2]$c2, [double]$r2) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $c2.Minus($c1); $L = $d.Len()
  if ($L -le [Math]::Abs($r1 - $r2) + 0.5) {
    if ($r1 -ge $r2) { $c = $c1; $r = $r1 } else { $c = $c2; $r = $r2 }
    $p.AddEllipse([single]($c.X - $r), [single]($c.Y - $r), [single](2 * $r), [single](2 * $r)); return $p
  }
  $base = [Math]::Atan2($d.Y, $d.X); $phi = [Math]::Acos(($r1 - $r2) / $L); $deg = 180.0 / [Math]::PI
  $p.AddArc([single]($c1.X - $r1), [single]($c1.Y - $r1), [single](2 * $r1), [single](2 * $r1), [single](($base + $phi) * $deg), [single]((2 * [Math]::PI - 2 * $phi) * $deg))
  $p.AddArc([single]($c2.X - $r2), [single]($c2.Y - $r2), [single](2 * $r2), [single](2 * $r2), [single](($base - $phi) * $deg), [single](2 * $phi * $deg))
  $p.CloseFigure(); $p
}
function New-RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $r = [Math]::Max(0.5, [Math]::Min($r, [Math]::Min($w, $h) / 2.0))
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = 2 * $r
  $p.AddArc([single]$x, [single]$y, [single]$d, [single]$d, 180, 90); $p.AddArc([single]($x + $w - $d), [single]$y, [single]$d, [single]$d, 270, 90)
  $p.AddArc([single]($x + $w - $d), [single]($y + $h - $d), [single]$d, [single]$d, 0, 90); $p.AddArc([single]$x, [single]($y + $h - $d), [single]$d, [single]$d, 90, 90)
  $p.CloseFigure(); $p
}
# retângulo arredondado em coordenadas do mundo (canto inferior esquerdo x,y; largura w; altura h)
function Fill-WorldRect($g, $color, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $tl = ToS ([V2]::new($x, $y + $h)); $path = New-RoundRect $tl.X $tl.Y ($w * $script:sc) ($h * $script:sc) ($r * $script:sc)
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPath($br, $path); $br.Dispose(); $path.Dispose()
}
# barra girada: centro, direção (graus), comprimento, espessura
function Fill-WorldBar($g, $color, [V2]$center, [double]$angle, [double]$length, [double]$thick) {
  $d = [V2]::Dir($angle).Times($length / 2.0 - $thick / 2.0)
  $path = New-HullPath (ToS ($center.Minus($d))) ($thick / 2.0 * $script:sc) (ToS ($center.Plus($d))) ($thick / 2.0 * $script:sc)
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPath($br, $path); $br.Dispose(); $path.Dispose()
}
function Fill-WorldCircle($g, $color, [V2]$c, [double]$r) {
  $s = ToS $c; $rr = $r * $script:sc; $br = New-Object System.Drawing.SolidBrush($color)
  $g.FillEllipse($br, [single]($s.X - $rr), [single]($s.Y - $rr), [single](2 * $rr), [single](2 * $rr)); $br.Dispose()
}
function Stroke-WorldCircle($g, $color, [V2]$c, [double]$r, [double]$w) {
  $s = ToS $c; $rr = $r * $script:sc; $pen = New-Object System.Drawing.Pen($color, [single]($w * $script:sc))
  $g.DrawEllipse($pen, [single]($s.X - $rr), [single]($s.Y - $rr), [single](2 * $rr), [single](2 * $rr)); $pen.Dispose()
}
function Stroke-WorldLine($g, $color, [V2]$a, [V2]$b, [double]$w) {
  $pen = New-Object System.Drawing.Pen($color, [single]($w * $script:sc)); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
  $g.DrawLine($pen, (PF (ToS $a)), (PF (ToS $b))); $pen.Dispose()
}

# segmento do corpo: casco tangente a dois círculos; o contorno na cor da superfície separa sobreposições
function Draw-Limb($g, $color, $gapColor, [V2]$a, [double]$ra, [V2]$b, [double]$rb, [V2]$shift) {
  $path = New-HullPath (ToS ($a.Plus($shift))) ($ra * $script:sc) (ToS ($b.Plus($shift))) ($rb * $script:sc)
  if ($null -ne $gapColor) {
    $pen = New-Object System.Drawing.Pen($gapColor, [single](0.009 * $script:sc)); $pen.LineJoin = 'Round'
    $g.DrawPath($pen, $path); $pen.Dispose()
  }
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPath($br, $path); $br.Dispose(); $path.Dispose()
}

# ---------------------------------------------------------------- corpo
function Draw-Leg($g, $P, [string]$s, $color, $gap, [V2]$shift) {
  Draw-Limb $g $color $gap $P['heel' + $s] $Rad.heel $P['toe' + $s] $Rad.toe $shift
  Draw-Limb $g $color $null $P['ankle' + $s] $Rad.ankle $P['heel' + $s] $Rad.heel $shift
  Draw-Limb $g $color $gap $P['knee' + $s] $Rad.kneeLow $P['ankle' + $s] $Rad.ankle $shift
  Draw-Limb $g $color $gap $P.hip $Rad.thighTop $P['knee' + $s] $Rad.knee $shift
}
function Draw-Arm($g, $P, [string]$s, $color, $gap, [V2]$shift) {
  Draw-Limb $g $color $gap $P.shoulder $Rad.shoulder $P['elbow' + $s] $Rad.elbow $shift
  Draw-Limb $g $color $gap $P['elbow' + $s] $Rad.elbowLow $P['hand' + $s] $Rad.wrist $shift
  Draw-Limb $g $color $null $P['hand' + $s] $Rad.hand $P['hand' + $s] $Rad.hand $shift
}
function Draw-TrunkHead($g, $sol, $color, $gap) {
  $P = $sol.P; $up = [V2]::Dir($sol.ang.trunk); $zero = [V2]::new(0, 0)
  Draw-Limb $g $color $gap $P.hip $Rad.hip $P.shoulder.Minus($up.Times(0.012)) $Rad.chest $zero
  Draw-Limb $g $color $null $P.shoulder $Rad.neck $P.head $Rad.neck $zero
  Draw-Limb $g $color $gap $P.head $Rad.head $P.head $Rad.head $zero
  # nariz discreto: diz para onde a pessoa olha sem desenhar rosto
  $face = [V2]::Dir($sol.ang.neck - 90)
  Draw-Limb $g $color $null $P.head.Plus($face.Times(0.045)) 0.016 $P.head.Plus($face.Times(0.058)).Plus([V2]::Dir($sol.ang.neck).Times(-0.004)) 0.011 $zero
}

# ---------------------------------------------------------------- equipamento
function Draw-SceneItem($g, $s, $ink) {
  switch ($s.kind) {
    'bench' {
      $x = [double]$s.x; $top = [double]$s.top; $len = [double]$s.length; $th = 0.042
      foreach ($px in @(($x + 0.10), ($x + $len - 0.10))) {
        Fill-WorldRect $g $ink.equipSoft ($px - 0.014) 0.0 0.028 ($top - $th) 0.004
        Fill-WorldRect $g $ink.equipSoft ($px - 0.075) 0.0 0.15 0.018 0.009
      }
      Fill-WorldRect $g $ink.equipFill $x ($top - $th) $len $th 0.016
    }
    'seat' {
      $x = [double]$s.x; $top = [double]$s.top; $len = [double]$s.length; $th = 0.042; $mid = $x + $len / 2.0
      Fill-WorldRect $g $ink.equipSoft ($mid - 0.016) 0.03 0.032 ($top - $th - 0.03) 0.004
      Fill-WorldRect $g $ink.equipFill $x ($top - $th) $len $th 0.016
    }
    'rail' { Fill-WorldRect $g $ink.equipSoft ([double]$s.x1) 0.0 ([double]$s.x2 - [double]$s.x1) 0.036 0.012 }
    'tower' {
      $x = [double]$s.x; $w = [double]$s.width; $h = [double]$s.height
      Fill-WorldRect $g $ink.equipSoft $x 0.0 $w $h 0.02
      $inner = Mix $ink.equipSoft $ink.surface 0.55
      Fill-WorldRect $g $inner ($x + 0.022) 0.05 ($w - 0.044) ($h - 0.10) 0.012
      for ($k = 0; $k -lt 7; $k++) { Fill-WorldRect $g $ink.equipFill ($x + 0.034) (0.065 + $k * 0.046) ($w - 0.068) 0.036 0.008 }
      Fill-WorldCircle $g $ink.equipLine ([V2]::new($x + $w / 2.0, $h - 0.045)) 0.02
    }
    'footPlate' {
      $c = Vec $s.at; $ang = [double]$s.angle
      Fill-WorldBar $g $ink.equipFill $c $ang ([double]$s.length) 0.036
    }
    'pulley' {
      $c = Vec $s.at
      Fill-WorldCircle $g $ink.equipLine $c 0.026
      Fill-WorldCircle $g $ink.equipSoft $c 0.009
    }
  }
}
function Get-Layer($kind) { switch ($kind) { 'tower' { 'back' } 'rail' { 'back' } 'footPlate' { 'back' } 'bench' { 'mid' } 'seat' { 'mid' } 'pulley' { 'mid' } default { 'mid' } } }

function Draw-Cable($g, $Gd, $sol, $ink) {
  foreach ($pr in $Gd.props) {
    if ($pr.kind -ne 'cable') { continue }
    $from = $null; foreach ($s in $Gd.scene) { if ($s.id -eq $pr.from) { $from = Vec $s.at } }
    $to = $sol.props[$pr.to]; if ($null -eq $from -or $null -eq $to) { continue }
    $apex = $to.Plus($from.Minus($to).Unit().Times(0.06))
    Stroke-WorldLine $g $ink.equipLine $from $apex 0.0065
  }
}
function Draw-HeldProps($g, $Gd, $sol, $ink, [string]$when) {
  foreach ($pr in $Gd.props) {
    $c = $sol.props[$pr.id]; if ($null -eq $c) { continue }
    if ($pr.kind -eq 'vHandle' -and $when -eq 'beforeNearArm') {
      $pull = $null; foreach ($q in $Gd.props) { if ($q.kind -eq 'cable') { foreach ($s in $Gd.scene) { if ($s.id -eq $q.from) { $pull = Vec $s.at } } } }
      $dir = if ($pull) { $pull.Minus($c).Unit() } else { [V2]::new(1, 0) }
      $apex = $c.Plus($dir.Times(0.06)); $n = $dir.Perp()
      $top = $c.Plus($n.Times(0.042)); $bot = $c.Minus($n.Times(0.042))
      Stroke-WorldLine $g $ink.equipLine $top $apex 0.011
      Stroke-WorldLine $g $ink.equipLine $bot $apex 0.011
      Stroke-WorldLine $g $ink.equipLine $top $bot 0.02
    }
    if ($pr.kind -eq 'dumbbell' -and $when -eq 'front') {
      foreach ($hc in @($c, $sol.props[$pr.id + 'Far'])) {
        if ($null -eq $hc) { continue }
        Fill-WorldCircle $g (WithAlpha $ink.surface 115) $hc 0.038
        Stroke-WorldCircle $g $ink.equipFill $hc 0.032 0.011
        Fill-WorldCircle $g $ink.equipLine $hc 0.011
      }
    }    if ($pr.kind -eq 'barbell' -and $when -eq 'front') {
      # só a anilha do lado de cá, vista de frente: aro + véu translúcido para o corpo continuar legível atrás dela
      Fill-WorldCircle $g (WithAlpha $ink.surface 115) $c $Rad.plate
      Stroke-WorldCircle $g $ink.equipFill $c ($Rad.plate - 0.006) 0.012
      Fill-WorldCircle $g $ink.equipLine $c 0.016
    }
  }
}

# ---------------------------------------------------------------- corpo em vista frontal
function Draw-FrontTorso($g, $sol, $color, $gap) {
  $P = $sol.P; $u = [V2]::Dir($sol.ang.trunk); $r = [V2]::Dir($sol.ang.trunk - 90)
  $pts = @(
    $P.neckBase.Plus($r.Times(0.118)).Minus($u.Times(0.01)), $P.hip.Plus($u.Times(0.13)).Plus($r.Times(0.088)), $P.hip.Plus($r.Times(0.100)).Minus($u.Times(0.02)),
    $P.hip.Minus($r.Times(0.100)).Minus($u.Times(0.02)), $P.hip.Plus($u.Times(0.13)).Minus($r.Times(0.088)), $P.neckBase.Minus($r.Times(0.118)).Minus($u.Times(0.01)))
  $spts = [System.Drawing.PointF[]]($pts | ForEach-Object { PF (ToS $_) })
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath; $path.AddPolygon($spts)
  $round = 0.05 * $script:sc
  if ($null -ne $gap) { $pg = New-Object System.Drawing.Pen($gap, [single]($round + 0.018 * $script:sc)); $pg.LineJoin = 'Round'; $g.DrawPath($pg, $path); $pg.Dispose() }
  $pen = New-Object System.Drawing.Pen($color, [single]$round); $pen.LineJoin = 'Round'; $g.DrawPath($pen, $path); $pen.Dispose()
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPath($br, $path); $br.Dispose(); $path.Dispose()
}
function Draw-FrontBody($g, $sol, $color, $gap) {
  $P = $sol.P; $zero = [V2]::new(0, 0)
  foreach ($s in 'Far', '') {
    Draw-Limb $g $color $null $P['ankle' + $s] $Rad.ankle $P['toe' + $s] 0.017 $zero
    Draw-Limb $g $color $gap $P['knee' + $s] $Rad.kneeLow $P['ankle' + $s] $Rad.ankle $zero
    Draw-Limb $g $color $gap $P['hipJ' + $s] $Rad.thighTop $P['knee' + $s] $Rad.knee $zero
  }
  Draw-FrontTorso $g $sol $color $gap
  Draw-Limb $g $color $null $P.neckBase $Rad.neck $P.head $Rad.neck $zero
  Draw-Limb $g $color $gap $P.head $Rad.head $P.head $Rad.head $zero
  foreach ($s in 'Far', '') {
    Draw-Limb $g $color $gap $P['shoulder' + $s] $Rad.shoulder $P['elbow' + $s] $Rad.elbow $zero
    Draw-Limb $g $color $gap $P['elbow' + $s] $Rad.elbowLow $P['hand' + $s] $Rad.wrist $zero
    Draw-Limb $g $color $null $P['hand' + $s] $Rad.hand $P['hand' + $s] $Rad.hand $zero
  }
}

function Draw-Ghost($g, $Gd, [double]$t, $ink) {
  $sol = Solve-Guide $Gd $t; $P = $sol.P; $c = $ink.ghost; $zero = [V2]::new(0, 0)
  if ($sol.front) { Draw-FrontBody $g $sol $c $null; return }
  Draw-Leg $g $P '' $c $null $zero; Draw-TrunkHead $g $sol $c $null; Draw-Arm $g $P '' $c $null $zero
  foreach ($pr in $Gd.props) { if ($pr.kind -eq 'barbell') { Stroke-WorldCircle $g $c $sol.props[$pr.id] ($Rad.plate - 0.007) 0.012 } }
}

function Draw-Cue($g, $Gd, $ink, [double]$fromT, [double]$toT) {
  if ($null -eq $Gd.cue) { return }
  $off = Vec $Gd.cue.offset; $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
  $steps = 24
  for ($k = 0; $k -le $steps; $k++) {
    $t = $fromT + ($toT - $fromT) * $k / $steps; $sol = Solve-Guide $Gd $t
    $p = if ($Gd.cue.track -eq 'hip') { $sol.P.hip } elseif ($Gd.cue.track -eq 'hand') { $sol.P.hand } else { $sol.props[$Gd.cue.track] }
    $pts.Add((PF (ToS ($p.Plus($off)))))
  }
  $pen = New-Object System.Drawing.Pen($ink.cue, [single](0.0075 * $script:sc)); $pen.DashStyle = 'Custom'; $pen.DashPattern = [single[]]@(2.2, 1.8); $pen.DashCap = 'Round'
  $arr = $pts.ToArray(); $a = $arr[$arr.Length - 3]; $b = $arr[$arr.Length - 1]
  # corta o traço antes da ponta para a seta não engrossar
  $g.DrawLines($pen, [System.Drawing.PointF[]]($arr[0..($arr.Length - 3)])); $pen.Dispose()
  $dx = $b.X - $a.X; $dy = $b.Y - $a.Y; $l = [Math]::Sqrt($dx * $dx + $dy * $dy); $ux = $dx / $l; $uy = $dy / $l
  $hs = 0.034 * $script:sc
  $tri = [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF([single]($b.X + $ux * $hs * 0.35), [single]($b.Y + $uy * $hs * 0.35))),
    (New-Object System.Drawing.PointF([single]($b.X - $ux * $hs * 0.75 - $uy * $hs * 0.55), [single]($b.Y - $uy * $hs * 0.75 + $ux * $hs * 0.55))),
    (New-Object System.Drawing.PointF([single]($b.X - $ux * $hs * 0.75 + $uy * $hs * 0.55), [single]($b.Y - $uy * $hs * 0.75 - $ux * $hs * 0.55))))
  $br = New-Object System.Drawing.SolidBrush($ink.cue); $g.FillPolygon($br, $tri); $br.Dispose()
}

# Desenha um quadro completo dentro de $rect. $opts: ghostT (posição anterior), cue ($true/$false), floor
function Draw-Frame($g, [System.Drawing.RectangleF]$rect, $Gd, [double]$t, $ink, [double]$scale, $bounds, $opts) {
  Set-Camera $rect $bounds $scale ([double]$opts.bottomPad)
  # chão
  $fy = $script:oy
  $pen = New-Object System.Drawing.Pen($ink.floor, [single](0.006 * $script:sc)); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
  $g.DrawLine($pen, [single]($rect.X + 0.06 * $rect.Width), [single]$fy, [single]($rect.Right - 0.06 * $rect.Width), [single]$fy); $pen.Dispose()

  foreach ($s in $Gd.scene) { if ((Get-Layer $s.kind) -eq 'back') { Draw-SceneItem $g $s $ink } }
  if ($null -ne $opts.ghostT) { Draw-Ghost $g $Gd ([double]$opts.ghostT) $ink }
  $sol = Solve-Guide $Gd $t; $P = $sol.P
  if ($sol.front) {
    Draw-FrontBody $g $sol $ink.body $ink.surface; Draw-HeldProps $g $Gd $sol $ink 'front'
    if ($opts.cue) { Draw-Cue $g $Gd $ink ([double]$opts.cueFrom) ([double]$opts.cueTo) }
    return
  }
  Draw-Arm $g $P 'Far' $ink.far $null $FarShift
  Draw-Leg $g $P 'Far' $ink.far $null $FarShift
  foreach ($s in $Gd.scene) { if ((Get-Layer $s.kind) -eq 'mid') { Draw-SceneItem $g $s $ink } }
  Draw-Cable $g $Gd $sol $ink
  Draw-TrunkHead $g $sol $ink.body $ink.surface
  Draw-Leg $g $P '' $ink.body $ink.surface ([V2]::new(0, 0))
  Draw-HeldProps $g $Gd $sol $ink 'beforeNearArm'
  Draw-Arm $g $P '' $ink.body $ink.surface ([V2]::new(0, 0))
  Draw-HeldProps $g $Gd $sol $ink 'front'
  if ($opts.cue) { Draw-Cue $g $Gd $ink ([double]$opts.cueFrom) ([double]$opts.cueTo) }
}

# ---------------------------------------------------------------- texto
function New-Font([string]$family, [double]$px, [string]$style = 'Regular') { New-Object System.Drawing.Font($family, [single]$px, [System.Drawing.FontStyle]$style, [System.Drawing.GraphicsUnit]::Pixel) }
function Draw-Text($g, [string]$text, $font, $color, [double]$x, [double]$y, [double]$w) {
  $fmt = New-Object System.Drawing.StringFormat; $fmt.Trimming = 'Word'
  $size = $g.MeasureString($text, $font, [int][Math]::Ceiling($w), $fmt)
  $br = New-Object System.Drawing.SolidBrush($color)
  $g.DrawString($text, $font, $br, (New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$w, [single]($size.Height + 4))), $fmt)
  $br.Dispose(); $fmt.Dispose(); [double]$size.Height
}
function Draw-PanelLabel($g, [string]$text, $ink, [System.Drawing.RectangleF]$r, [double]$px) {
  $f = New-Font 'Segoe UI Semibold' $px; [void](Draw-Text $g $text $f $ink.text2 ($r.X + $px * 0.9) ($r.Y + $px * 0.6) ($r.Width)); $f.Dispose()
}
function New-Canvas([int]$w, [int]$h) {
  $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.CompositingQuality = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  @{ bmp = $bmp; g = $g }
}
function Fill-Round($g, $color, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $p = New-RoundRect $x $y $w $h $r; $b = New-Object System.Drawing.SolidBrush($color); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
}

# ---------------------------------------------------------------- dados
$doc = Get-Content -Raw -Encoding UTF8 $Data | ConvertFrom-Json
$names = @{}
if (Test-Path $Catalog) { (Get-Content -Raw -Encoding UTF8 $Catalog | ConvertFrom-Json).exercises | ForEach-Object { $names[$_.slug] = $_.name } }
$allGuides = @($doc.guides); $guides = @($allGuides | Where-Object { -not $_.bonus }); $bonusGuides = @($allGuides | Where-Object { $_.bonus })
$boundsBy = @{}; foreach ($Gd in $allGuides) { $boundsBy[$Gd.slug] = Get-Bounds $Gd }
# mesma escala para todos: o corpo tem o mesmo tamanho em qualquer exercício (padronização)
function Get-CommonScale([double]$w, [double]$h, [double]$pad, [double]$topPad, $list = $null) {
  $s = 1e9
  if ($null -eq $list) { $list = $guides }; foreach ($Gd in $list) { $b = $boundsBy[$Gd.slug]; $s = [Math]::Min($s, [Math]::Min(($w - 2 * $pad) / ($b.maxX - $b.minX), ($h - $pad - $topPad) / ($b.maxY - $b.minY))) }
  $s
}
function NameOf($Gd) { if ($names.ContainsKey($Gd.slug)) { $names[$Gd.slug] } else { $Gd.slug } }
function Save-Png($c, [string]$path) { $c.g.Dispose(); $c.bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $c.bmp.Dispose(); Write-Host "ok  $path" }

$ink = New-Ink 'light'

# ---------------------------------------------------------------- 1) quadros-chave individuais
$S = 640; $scale1 = Get-CommonScale $S $S 40 70 $allGuides
foreach ($Gd in $allGuides) {
  $last = $Gd.frames.Count - 1
  for ($f = 0; $f -le $last; $f++) {
    $c = New-Canvas $S $S; $c.g.Clear($ink.surface)
    $r = New-Object System.Drawing.RectangleF(0, 0, $S, $S)
    $opts = @{ bottomPad = 44; cue = ($f -eq 0); cueFrom = 0.0; cueTo = [double]$last; ghostT = $null }
    if ($f -gt 0) { $opts.ghostT = [double]($f - 1) }
    Draw-Frame $c.g $r $Gd ([double]$f) $ink $scale1 $boundsBy[$Gd.slug] $opts
    Draw-PanelLabel $c.g ("{0} · {1}" -f ($f + 1), $Gd.frames[$f].label) $ink $r 22
    $suffix = if ($f -eq 0) { 'inicio' } else { 'fim' }
    Save-Png $c (Join-Path $Out ("{0}-{1}-{2}.png" -f $Gd.slug, ($f + 1), $suffix))
  }
}

# ---------------------------------------------------------------- 2) tira de interpolação
$cell = 260; $gap = 12; $left = 250; $top = 96
$W = $left + 5 * $cell + 4 * $gap + 36; $H = $top + $guides.Count * ($cell + $gap) + 40
$c = New-Canvas $W $H; $g = $c.g; $g.Clear($ink.page)
$ft = New-Font 'Georgia' 30; [void](Draw-Text $g 'Interpolação entre os quadros-chave' $ft $ink.text 36 26 1400); $ft.Dispose()
$fs = New-Font 'Segoe UI' 16; [void](Draw-Text $g 'Ângulos pelo arco mais curto com easeInOut; a âncora (tornozelo ou quadril) fica parada e os braços seguem a barra ou o puxador por IK de dois ossos.' $fs $ink.text2 36 64 1500); $fs.Dispose()
$scale2 = Get-CommonScale $cell $cell 14 30
$row = 0
foreach ($Gd in $guides) {
  $y = $top + $row * ($cell + $gap) + 10
  $fn = New-Font 'Georgia' 21; [void](Draw-Text $g (NameOf $Gd) $fn $ink.text 36 ($y + 20) ($left - 50)); $fn.Dispose()
  $fc = New-Font 'Segoe UI' 14; [void](Draw-Text $g $Gd.caption $fc $ink.text2 36 ($y + 80) ($left - 50)); $fc.Dispose()
  for ($k = 0; $k -lt 5; $k++) {
    $x = $left + $k * ($cell + $gap); $u = $k / 4.0
    Fill-Round $g $ink.surface $x $y $cell $cell 16
    $r = New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$cell, [single]$cell)
    Draw-Frame $g $r $Gd ($u * ($Gd.frames.Count - 1)) $ink $scale2 $boundsBy[$Gd.slug] @{ bottomPad = 20; cue = $false }
    Draw-PanelLabel $g ("{0}%" -f [int]($u * 100)) $ink $r 14
  }
  $row++
}
Save-Png $c (Join-Path $Out 'interpolation-strip.png')

# ---------------------------------------------------------------- 3) folha de comparação (claro e escuro)
# Desenha a folha inteira; devolve a altura usada. Chamada duas vezes: medir (tela descartável) e desenhar.
function Draw-CompareSheet($g, [string]$look, [double]$H, [double]$W, $list, [string]$title, [string]$subtitle) {
  $ink = New-Ink $look
  $colW = 740; $gutter = 36; $pad = 24; $between = 30; $panel = [int](($colW - 2 * $pad - $between) / 2)
  $g.Clear($ink.page)
  $ft = New-Font 'Georgia' 38; [void](Draw-Text $g $title $ft $ink.text $gutter 30 900); $ft.Dispose()
  $fs = New-Font 'Segoe UI' 18
  [void](Draw-Text $g $subtitle $fs $ink.text2 $gutter 86 ($W - 2 * $gutter))
  $fs.Dispose()
  $scale3 = Get-CommonScale $panel $panel 12 36 $list
  $y0 = 146; $cardH = $H - $y0 - 64; $maxBottom = 0.0; $col = 0
  foreach ($Gd in $list) {
    $x0 = $gutter + $col * ($colW + $gutter)
    Fill-Round $g $ink.surface $x0 $y0 $colW $cardH 24
    $fn = New-Font 'Georgia' 29; $hName = Draw-Text $g (NameOf $Gd) $fn $ink.text ($x0 + $pad) ($y0 + 22) ($colW - 2 * $pad); $fn.Dispose()
    $fc = New-Font 'Segoe UI' 16; [void](Draw-Text $g $Gd.caption $fc $ink.text2 ($x0 + $pad) ($y0 + 28 + $hName) ($colW - 2 * $pad)); $fc.Dispose()
    $py = $y0 + 100; $last = $Gd.frames.Count - 1
    for ($f = 0; $f -le 1; $f++) {
      $px = $x0 + $pad + $f * ($panel + $between)
      Fill-Round $g $ink.page $px $py $panel $panel 18
      $r = New-Object System.Drawing.RectangleF([single]$px, [single]$py, [single]$panel, [single]$panel)
      $opts = @{ bottomPad = 20; cue = ($f -eq 0); cueFrom = 0.0; cueTo = [double]$last; ghostT = $null }
      if ($f -eq 1) { $opts.ghostT = 0.0 }
      # o painel usa o fundo da página para destacar do cartão; a cor da "lacuna" entre segmentos acompanha
      $inkP = $ink.Clone(); $inkP.surface = $ink.page; $inkP.ghost = Mix $ink.body $ink.page 0.86
      $inkP.far = Mix $ink.body $ink.page 0.50; $inkP.floor = Mix $ink.text2 $ink.page 0.66
      Draw-Frame $g $r $Gd ([double]($f * $last)) $inkP $scale3 $boundsBy[$Gd.slug] $opts
      Draw-PanelLabel $g ("{0} · {1}" -f ($f + 1), $Gd.frames[$f * $last].label) $ink $r 16
    }
    $ax = $x0 + $pad + $panel + $between / 2.0; $ay = $py + $panel / 2.0
    $pen = New-Object System.Drawing.Pen($ink.text2, 2.4); $pen.EndCap = 'Round'; $pen.StartCap = 'Round'
    $g.DrawLine($pen, [single]($ax - 8), [single]$ay, [single]($ax + 7), [single]$ay)
    $g.DrawLine($pen, [single]($ax + 1), [single]($ay - 6), [single]($ax + 7), [single]$ay)
    $g.DrawLine($pen, [single]($ax + 1), [single]($ay + 6), [single]($ax + 7), [single]$ay); $pen.Dispose()

    $ty = $py + $panel + 28; $tw = $colW - 2 * $pad - 42
    $fh = New-Font 'Segoe UI Semibold' 17; $fb = New-Font 'Segoe UI' 17; $fnum = New-Font 'Segoe UI Semibold' 15; $fsm = New-Font 'Segoe UI' 15
    $ty += (Draw-Text $g 'Passos' $fh $ink.text ($x0 + $pad) $ty ($colW - 2 * $pad)) + 8
    $n = 1
    foreach ($step in $Gd.steps) {
      Fill-Round $g $ink.accentSoft ($x0 + $pad) ($ty + 1) 28 28 14
      $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
      $br = New-Object System.Drawing.SolidBrush((HexColor $Tokens[$look].accent)); $g.DrawString([string]$n, $fnum, $br, (New-Object System.Drawing.RectangleF([single]($x0 + $pad), [single]($ty + 2), 28, 28)), $fmt); $br.Dispose(); $fmt.Dispose()
      $ty += [Math]::Max(30, (Draw-Text $g $step $fb $ink.text ($x0 + $pad + 42) ($ty + 2) $tw)) + 10
      $n++
    }
    $ty += 12
    $ty += (Draw-Text $g 'Erros comuns' $fh $ink.text ($x0 + $pad) $ty ($colW - 2 * $pad)) + 8
    foreach ($m in $Gd.mistakes) {
      $pen = New-Object System.Drawing.Pen($ink.text2, 2); $g.DrawEllipse($pen, [single]($x0 + $pad + 9), [single]($ty + 8), 10, 10); $pen.Dispose()
      $ty += (Draw-Text $g $m $fb $ink.text2 ($x0 + $pad + 42) $ty $tw) + 10
    }
    $ty += 14
    $line = New-Object System.Drawing.Pen((Mix $ink.text2 $ink.surface 0.8), 1); $g.DrawLine($line, [single]($x0 + $pad), [single]$ty, [single]($x0 + $colW - $pad), [single]$ty); $line.Dispose()
    $ty += 12
    $ty += (Draw-Text $g ('VoiceOver: "' + $Gd.a11y + '"') $fsm $ink.text2 ($x0 + $pad) $ty ($colW - 2 * $pad)) + 4
    $fh.Dispose(); $fb.Dispose(); $fnum.Dispose(); $fsm.Dispose()
    $maxBottom = [Math]::Max($maxBottom, $ty)
    $col++
  }
  $ff = New-Font 'Segoe UI' 15
  [void](Draw-Text $g 'Cores: DESIGN.md §3 · proporções do corpo: Winter (2009) · dados: exercise-guides.sample.json (ângulos absolutos por segmento, 2 quadros-chave, âncora, IK dos braços e escorço)' $ff $ink.text2 $gutter ($H - 42) ($W - 2 * $gutter))
  $ff.Dispose()
  $maxBottom
}
function Render-Compare([string]$look, [string]$file, $list, [string]$title, [string]$subtitle) {
  $W = $list.Count * 740 + ($list.Count + 1) * 36
  $probe = New-Canvas $W 1800; $used = Draw-CompareSheet $probe.g $look 1800 $W $list $title $subtitle; $probe.g.Dispose(); $probe.bmp.Dispose()
  $H = [int]([Math]::Ceiling($used) + 28 + 64)
  $c = New-Canvas $W $H; [void](Draw-CompareSheet $c.g $look $H $W $list $title $subtitle)
  Save-Png $c (Join-Path $Out $file)
}
$sub = 'Protótipo: manequim neutro desenhado pelo app a partir de dados de pose. No app ele anima em loop entre os dois quadros; com Reduzir Movimento, os quadros aparecem lado a lado, como aqui.'
Render-Compare 'light' 'compare.png' $guides 'Como fazer' $sub
Render-Compare 'dark' 'compare-dark.png' $guides 'Como fazer' $sub
if ($bonusGuides.Count -gt 0) { Render-Compare 'light' 'bonus-front-view.png' $bonusGuides 'Vista frontal' 'Mesmo formato de dados com "view": "front"; o outro lado do corpo é espelhado.' }
