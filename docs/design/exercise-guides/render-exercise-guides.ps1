# render-exercise-guides.ps1 — protótipo v2 da "Frente 3" (ilustração própria) do botão "Como fazer".
#
# Desenha o manequim neutro do Magister a partir de DADOS DE POSE (exercise-guides.sample.json), com o mesmo
# algoritmo que o app usaria em SwiftUI (Canvas + TimelineView):
#   1. interpolação: para um instante t entre dois quadros-chave, cada ângulo de segmento vai pelo arco mais curto,
#      com easeInOut (senoide);
#   2. cinemática direta: a partir do quadril, soma segmentos de comprimento fixo (proporções de Drillis e Contini,
#      1966, reproduzidas em Winter) nas direções absolutas interpoladas;
#   3. âncora: translada o corpo inteiro para que a articulação-âncora (tornozelo no agachamento, quadril no banco)
#      fique sempre no mesmo ponto — é isso que impede os pés de "escorregar" no meio do movimento;
#   4. IK de dois ossos (lei dos cossenos) para os braços quando as mãos seguram algo com posição definida
#      (barra nas costas, pegada por quadro), com um vetor de dica para o lado do cotovelo. A pegada fica no meio da
#      palma, a 40% do comprimento da mão depois do punho. Com "arms.forearm" o antebraço fica num ângulo travado
#      (supino: vertical sob a barra) e o cotovelo acompanha a pegada, sem IK;
#   5. desenho em camadas: equipamento de fundo -> fantasma -> membros do lado de lá -> equipamento do meio ->
#      tronco e cabeça -> perna e braço do lado de cá -> equipamento da frente -> seta.
#
# Clareza (v2, pedido do dono: "dê mais clareza para o usuário"; clareza vence minimalismo, sem realismo):
#   - o que se move fica em accent; o resto do corpo em accent misturado ao fundo. "Move" é calculado dos dados
#     (Get-Moving): o segmento gira pelo menos 12° ou anda pelo menos 0,04 H entre o primeiro e o último quadro,
#     E a articulação dele muda pelo menos 12° (ou ele só acompanha, rígido, um segmento do mesmo membro que se
#     move: antebraço, perna, pé, cabeça). Assim os braços que só seguram a barra no agachamento ficam suaves.
#     "moving" no JSON sobrepõe o cálculo;
#   - o lado de lá é sempre mais claro que o de cá, e o que se move no lado de lá mantém contraste >= 3:1;
#   - seta curva e sólida em textPrimary no quadro 1, paralela à trajetória do ponto principal ("cue");
#     no quadro 2, a posição inicial em fantasma: preenchimento quase no tom do fundo e contorno tracejado, só das
#     partes que mudaram de lugar (Get-GhostShapes). Assim o fantasma lê como "estava aqui", e não como membros a
#     mais, nos dois modos; quando o tronco se move (agachamento), o corpo inteiro muda de lugar e aparece inteiro;
#   - barra apoiada nas costas ("attach": "back") fica atrás do tronco, com metade escondida pelo corpo, para não
#     parecer segura na frente do peito;
#   - legenda curta por quadro ("caption", até ~28 caracteres) e a linha "Trabalha: ..." (primaryMuscles do seed);
#   - implemento que se move em textSecondary (>= 3:1); estrutura fixa (banco, torre, assento) clara, como fundo.
#   O script confere os contrastes e para com erro se algum gráfico essencial ficar abaixo de 3:1.
#
# Saídas (na pasta do script, ou em -Out):
#   compare-v2.png, compare-v2-dark.png   folha com os 4 exercícios, nas aparências clara e escura (DESIGN.md §3)
# Com -Extras <pasta>: <slug>-1-inicio.png e <slug>-2-fim.png (640x640) e interpolation-strip-v2.png
#   (5 instantes por exercício, para conferir âncora e IK).
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File render-exercise-guides.ps1
#        [-Data <json>] [-Catalog <exercises.v2.json>] [-Out <pasta>] [-Extras <pasta>]
param([string]$Data = '', [string]$Catalog = '', [string]$Out = '', [string]$Extras = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Data -eq '') { $Data = Join-Path $here 'exercise-guides.sample.json' }
if ($Catalog -eq '') { $Catalog = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\..\PersonalTrainer\Resources\Seed\exercises.v2.json')) }
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

# ---------------------------------------------------------------- cores (DESIGN.md §3 e §12 proposto)
function HexColor([string]$hex, [int]$a = 255) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16)) }
function Mix($c1, $c2, [double]$t) { [System.Drawing.Color]::FromArgb(255, [int][Math]::Round($c1.R + ($c2.R - $c1.R) * $t), [int][Math]::Round($c1.G + ($c2.G - $c1.G) * $t), [int][Math]::Round($c1.B + ($c2.B - $c1.B) * $t)) }
function WithAlpha($c, [int]$a) { [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function Lum($c) {
  $sum = 0.0; $w = @(0.2126, 0.7152, 0.0722); $ch = @($c.R, $c.G, $c.B)
  for ($i = 0; $i -lt 3; $i++) { $x = $ch[$i] / 255.0; if ($x -le 0.04045) { $v = $x / 12.92 } else { $v = [Math]::Pow(($x + 0.055) / 1.055, 2.4) }; $sum += $w[$i] * $v }
  $sum
}
function Contrast($a, $b) { $la = Lum $a; $lb = Lum $b; ([Math]::Max($la, $lb) + 0.05) / ([Math]::Min($la, $lb) + 0.05) }
function Hex($c) { '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B }

$Tokens = @{
  light = @{ page = '#F2EBE0'; surface = '#FAF6F0'; text = '#33281F'; text2 = '#6B5A4C'; accent = '#355A7C'; accentSoft = '#DDE5EC' }
  dark  = @{ page = '#1C1714'; surface = '#29221C'; text = '#F0E7DA'; text2 = '#BCAB98'; accent = '#9DBAD6'; accentSoft = '#26323E' }
}
# Fração de cada tom que vai para o fundo do quadro (background). No escuro o accent já contrasta mais com o
# fundo, então as misturas são maiores para a figura manter a mesma hierarquia.
$Mixes = @{
  light = @{ farMove = 0.25; nearStill = 0.56; farStill = 0.72; ghostFill = 0.90; ghostLine = 0.50; structure = 0.62; structureSoft = 0.76; floor = 0.60 }
  dark  = @{ farMove = 0.40; nearStill = 0.62; farStill = 0.76; ghostFill = 0.90; ghostLine = 0.52; structure = 0.64; structureSoft = 0.78; floor = 0.62 }
}
function New-Ink([string]$look) {
  $t = $Tokens[$look]; $m = $Mixes[$look]
  $bg = HexColor $t.page; $accent = HexColor $t.accent; $text2 = HexColor $t.text2
  @{
    look = $look; bg = $bg; page = $bg; surface = HexColor $t.surface; text = HexColor $t.text; text2 = $text2
    accent = $accent; accentSoft = HexColor $t.accentSoft
    nearMove = $accent                                # o que se move, lado de cá
    farMove = Mix $accent $bg $m.farMove              # o que se move, lado de lá (>= 3:1)
    nearStill = Mix $accent $bg $m.nearStill          # resto do corpo, lado de cá
    farStill = Mix $accent $bg $m.farStill            # resto do corpo, lado de lá
    ghostFill = Mix $accent $bg $m.ghostFill          # posição inicial (só no quadro final): miolo quase fundo
    ghostLine = Mix $accent $bg $m.ghostLine          # ... e contorno tracejado, mais fraco que o corpo
    equip = $text2                                    # barra, anilhas, halter, puxador, cabo (>= 3:1)
    structure = Mix $text2 $bg $m.structure           # estofado, assento, plataforma, polia
    structureSoft = Mix $text2 $bg $m.structureSoft   # pés do banco, trilho, torre
    floor = Mix $text2 $bg $m.floor
    arrow = HexColor $t.text                          # seta de movimento
  }
}
function Test-Contrast {
  foreach ($look in 'light', 'dark') {
    $ink = New-Ink $look; $bg = $ink.bg; $line = @()
    foreach ($k in 'nearMove', 'farMove', 'equip', 'arrow', 'nearStill', 'farStill', 'structure', 'ghostLine', 'ghostFill') {
      $cr = Contrast $ink[$k] $bg; $line += ('{0} {1} {2:0.00}' -f $k, (Hex $ink[$k]), $cr)
      if (@('nearMove', 'farMove', 'equip', 'arrow') -contains $k -and $cr -lt 3.0) { throw "contraste abaixo de 3:1 ($look, $k): $cr" }
    }
    $sep = Contrast $ink.nearMove $ink.nearStill
    Write-Host ("contraste {0} contra o fundo {1}: {2}; forte x suave {3:0.00}" -f $look, (Hex $bg), ($line -join ' · '), $sep)
  }
}

# ---------------------------------------------------------------- manequim (unidade = estatura H)
# Drillis e Contini (1966), em Winter, fig. 4.1: braço 0,186 H; antebraço 0,146 H; mão 0,108 H; coxa 0,245 H;
# perna 0,246 H. Tronco (quadril-ombro) 0,288 H e pescoço-cabeça 0,122 H.
$Rig = @{ trunk = 0.288; neck = 0.122; thigh = 0.245; shin = 0.246; foot = 0.125; upperArm = 0.186; forearm = 0.146; hand = 0.108 }
$GripAt = 0.40                          # pegada no meio da palma: 40% da mão depois do punho
$FistAt = 0.55                          # a mão fechada vai do punho até 55% do comprimento da mão
$Rad = @{ hip = 0.062; chest = 0.067; neck = 0.024; head = 0.064; thighTop = 0.055; knee = 0.038; kneeLow = 0.034; ankle = 0.024
          heel = 0.019; toe = 0.013; shoulder = 0.034; elbow = 0.029; elbowLow = 0.027; wrist = 0.021; hand = 0.025; plate = 0.074 }
$FarShift = [V2]::new(-0.016, 0.013)    # câmera levemente acima e à frente: o lado de lá aparece um pouco atrás e acima
$GapW = 0.011                           # contorno na cor do fundo que separa segmentos sobrepostos

# ---------------------------------------------------------------- interpolação
function LerpAngle([double]$a, [double]$b, [double]$u) { $d = (($b - $a + 540.0) % 360.0) - 180.0; $a + $d * $u }
function Ease([double]$u) { 0.5 - 0.5 * [Math]::Cos([Math]::PI * [Math]::Max(0.0, [Math]::Min(1.0, $u))) }
function NumOr($v, [double]$d) { if ($null -eq $v) { $d } else { [double]$v } }
function DepthPair($v, $default) {
  if ($null -eq $v) { return ,$default }
  if ($v -is [System.Array]) { return ,@([double]$v[0], [double]$v[1]) }
  return ,@([double]$v, [double]$v)
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

# Antebraço + mão a partir do cotovelo E numa direção dir: punho, pegada (meio da palma) e ponta da mão fechada.
function Set-ForearmPoints($P, [string]$s, [V2]$E, [V2]$dir, [double]$depth) {
  $P['elbow' + $s] = $E
  $P['wrist' + $s] = $E.Plus($dir.Times($Rig.forearm * $depth))
  $P['hand' + $s] = $E.Plus($dir.Times(($Rig.forearm + $GripAt * $Rig.hand) * $depth))
  $P['fist' + $s] = $E.Plus($dir.Times(($Rig.forearm + $FistAt * $Rig.hand) * $depth))
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
    $E = $P['shoulder' + $s].Plus([V2]::Dir((MirrorAng $ang['upperArm' + $s] $k)).Times($Rig.upperArm))
    Set-ForearmPoints $P $s $E ([V2]::Dir((MirrorAng $ang['forearm' + $s] $k))) 1.0
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
  # escorço: fator de projeção de cada segmento do braço no plano do desenho ([braço, antebraço+mão] ou um número)
  $dA = DepthPair $A.armDepth (DepthPair $arms.depth @(1.0, 1.0)); $dB = DepthPair $B.armDepth (DepthPair $arms.depth @(1.0, 1.0))
  $dU = $dA[0] + ($dB[0] - $dA[0]) * $u; $dF = $dA[1] + ($dB[1] - $dA[1]) * $u
  $ua = $Rig.upperArm * $dU; $reach = ($Rig.forearm + $GripAt * $Rig.hand) * $dF
  if ($arms -and $arms.reach) {
    if ($arms.reach -eq 'grip') { $target = [V2]::Lerp((Vec $A.grip), (Vec $B.grip), $u) } else { $target = $props[$arms.reach] }
    if ($null -ne $arms.forearm) {
      # antebraço com ângulo travado (supino: vertical sob a barra durante todo o movimento). O cotovelo fica sob a
      # pegada e o braço vai do ombro até ele; o comprimento aparente do braço muda sozinho (escorço implícito).
      $dir = [V2]::Dir([double]$arms.forearm); $E = $target.Minus($dir.Times($reach))
      $need = $E.Minus($P.shoulder).Len()
      if ($need -gt $Rig.upperArm + 1e-3) { Write-Warning ("{0}: em t={1:0.00} o braço precisaria medir {2:0.000} H (máx. {3})" -f $Gd.slug, $t, $need, $Rig.upperArm) }
      foreach ($s in '', 'Far') { Set-ForearmPoints $P $s $E $dir $dF }
    } else {
      $hint = LerpAngle (NumOr $A.elbow (NumOr $arms.elbow -90)) (NumOr $B.elbow (NumOr $arms.elbow -90)) $u
      $ik = Solve-TwoBone $P.shoulder $target $ua $reach $hint
      $dir = $ik.end.Minus($ik.elbow).Unit()
      foreach ($s in '', 'Far') { Set-ForearmPoints $P $s $ik.elbow $dir $dF }
    }
  } else {
    foreach ($s in '', 'Far') {
      $E = $P.shoulder.Plus([V2]::Dir($ang['upperArm' + $s]).Times($ua))
      Set-ForearmPoints $P $s $E ([V2]::Dir($ang['forearm' + $s])) $dF
    }
  }
  foreach ($pr in $Gd.props) { if ($pr.attach -eq 'hand') { $props[$pr.id] = $P.hand } }
  @{ P = $P; props = $props; ang = $ang }
}

# ---------------------------------------------------------------- o que se move (calculado dos dados)
function SegAng([V2]$p, [V2]$q) { $d = $q.Minus($p); [Math]::Atan2($d.Y, $d.X) * 180.0 / [Math]::PI }
function AngDiff([double]$a, [double]$b) { $d = ($b - $a) % 360.0; if ($d -gt 180) { $d -= 360 } elseif ($d -lt -180) { $d += 360 }; [Math]::Abs($d) }
# Extremos de cada segmento (para ângulo e deslocamento do ponto médio).
function Get-Segs($sol) {
  $P = $sol.P; $a = @{}
  $top = if ($sol.front) { $P.neckBase } else { $P.shoulder }
  $a.trunk = @($P.hip, $top); $a.head = @($top, $P.head)
  foreach ($s in '', 'Far') {
    if ($sol.front) { $root = $P['hipJ' + $s]; $sh = $P['shoulder' + $s] } else { $root = $P.hip; $sh = $P.shoulder }
    $a['thigh' + $s] = @($root, $P['knee' + $s])
    $a['shin' + $s] = @($P['knee' + $s], $P['ankle' + $s])
    $a['foot' + $s] = @($P['ankle' + $s], $P['toe' + $s])
    $a['upperArm' + $s] = @($sh, $P['elbow' + $s])
    $a['forearm' + $s] = @($P['elbow' + $s], $P['wrist' + $s])
  }
  $a
}
$Parent = @{ trunk = $null; head = 'trunk'; thigh = 'trunk'; shin = 'thigh'; foot = 'shin'; upperArm = 'trunk'; forearm = 'upperArm' }
$Rigid = @{ head = $true; shin = $true; foot = $true; forearm = $true }   # podem só acompanhar o segmento-pai
$MoveMin = 12.0; $ShiftMin = 0.04
# Um segmento "se move" quando gira >= 12° ou o meio dele anda >= 0,04 H (o antebraço do supino desce sem girar),
# E a articulação com o pai muda >= 12° (ou ele só acompanha, rígido, um pai que se move no mesmo membro).
# Assim o pé parado no chão e os braços que só seguram a barra no agachamento ficam suaves. (Na remada o tronco
# fica no mesmo ângulo nos dois quadros: se inclinasse, a figura sugeriria o erro "jogar o tronco para trás".)
function Get-Moving($Gd) {
  $last = $Gd.frames.Count - 1
  $s0 = Get-Segs (Solve-Guide $Gd 0.0); $s1 = Get-Segs (Solve-Guide $Gd ([double]$last))
  $a0 = @{}; $a1 = @{}; foreach ($k in $s0.Keys) { $a0[$k] = SegAng $s0[$k][0] $s0[$k][1]; $a1[$k] = SegAng $s1[$k][0] $s1[$k][1] }
  $mv = @{}; $report = @()
  foreach ($s in '', 'Far') {
    foreach ($seg in 'trunk', 'head', 'thigh', 'shin', 'foot', 'upperArm', 'forearm') {
      $central = ($seg -eq 'trunk' -or $seg -eq 'head')
      if ($central -and $s -eq 'Far') { continue }
      $key = if ($central) { $seg } else { $seg + $s }
      $abs = AngDiff $a0[$key] $a1[$key]
      $mid0 = [V2]::Lerp($s0[$key][0], $s0[$key][1], 0.5); $mid1 = [V2]::Lerp($s1[$key][0], $s1[$key][1], 0.5)
      $shift = $mid1.Minus($mid0).Len()
      $par = $Parent[$seg]; $pkey = $null; $joint = $abs
      if ($null -ne $par) {
        $pkey = if ($par -eq 'trunk') { 'trunk' } else { $par + $s }
        $joint = AngDiff ($a0[$key] - $a0[$pkey]) ($a1[$key] - $a1[$pkey])
      }
      $follows = $Rigid.ContainsKey($seg) -and $null -ne $pkey -and $mv.ContainsKey($pkey)
      $m = (($abs -ge $MoveMin) -or ($shift -ge $ShiftMin)) -and (($joint -ge $MoveMin) -or $follows)
      if ($m) { $mv[$key] = $true }
      if ($s -eq '') { $report += ('{0} {1:0}°/{2:0.00}H/{3:0}°{4}' -f $key, $abs, $shift, $joint, $(if ($m) { ' MOVE' } else { '' })) }
    }
  }
  if ($null -ne $Gd.moving) {
    $auto = ($mv.Keys | Sort-Object) -join ','
    $mv = @{}; foreach ($k in $Gd.moving) { $mv[$k] = $true; if ($k -notmatch 'Far$') { $mv[$k + 'Far'] = $true } }
    Write-Host ("  {0}: 'moving' do JSON sobrepõe o cálculo ({1})" -f $Gd.slug, $auto)
  }
  Write-Host ("  {0} (giro/deslocamento/articulação): {1}" -f $Gd.slug, ($report -join ' · '))
  $mv
}
# Tons por segmento. Na vista frontal não há lado de lá: os dois lados usam os tons de cá.
function Get-Tones($ink, $moving, [bool]$front = $false) {
  $t = @{}
  foreach ($seg in 'trunk', 'head', 'upperArm', 'forearm', 'thigh', 'shin', 'foot') {
    $t[$seg] = if ($moving.ContainsKey($seg)) { $ink.nearMove } else { $ink.nearStill }
    $fk = if ($seg -eq 'trunk' -or $seg -eq 'head') { $seg } else { $seg + 'Far' }
    if ($front) { $t[$seg + 'Far'] = if ($moving.ContainsKey($fk)) { $ink.nearMove } else { $ink.nearStill } }
    else { $t[$seg + 'Far'] = if ($moving.ContainsKey($fk)) { $ink.farMove } else { $ink.farStill } }
  }
  $t
}

# ---------------------------------------------------------------- seta de movimento
# Pontos da trajetória do ponto principal (quadril, mão, barra ou puxador) ao longo da ida, reamostrados por
# comprimento de arco, recortados em "span" e deslocados "gap" para o lado indicado (à direita ou à esquerda de
# quem anda pela trajetória), para a seta correr paralela ao movimento sem cobrir o corpo.
function Get-TrackPoint($Gd, $sol) {
  switch ($Gd.cue.track) { 'hip' { return $sol.P.hip } 'hand' { return $sol.P.hand } default { return $sol.props[$Gd.cue.track] } }
}
function Get-CuePath($Gd) {
  $cue = $Gd.cue; if ($null -eq $cue) { return $null }
  $last = $Gd.frames.Count - 1; $n = 80
  $raw = New-Object System.Collections.Generic.List[object]
  for ($k = 0; $k -le $n; $k++) { $raw.Add((Get-TrackPoint $Gd (Solve-Guide $Gd ($last * $k / $n)))) }
  $cum = @(0.0); for ($k = 1; $k -le $n; $k++) { $cum += $cum[$k - 1] + $raw[$k].Minus($raw[$k - 1]).Len() }
  $L = $cum[$n]; $a = 0.0; $b = 1.0; if ($cue.span) { $a = [double]$cue.span[0]; $b = [double]$cue.span[1] }
  $m = 40; $pts = New-Object System.Collections.Generic.List[object]; $j = 1
  for ($k = 0; $k -le $m; $k++) {
    $target = $L * ($a + ($b - $a) * $k / $m)
    while ($j -lt $n -and $cum[$j] -lt $target) { $j++ }
    $seg = [Math]::Max(1e-9, $cum[$j] - $cum[$j - 1]); $f = [Math]::Max(0.0, [Math]::Min(1.0, ($target - $cum[$j - 1]) / $seg))
    $pts.Add([V2]::Lerp($raw[$j - 1], $raw[$j], $f))
  }
  $outPts = New-Object System.Collections.Generic.List[object]
  for ($k = 0; $k -le $m; $k++) {
    $p = $pts[$k]
    if ($cue.side) {
      $tan = $pts[[Math]::Min($m, $k + 2)].Minus($pts[[Math]::Max(0, $k - 2)]).Unit()
      $nrm = [V2]::new($tan.Y, -$tan.X); if ($cue.side -eq 'left') { $nrm = $nrm.Times(-1) }
      $p = $p.Plus($nrm.Times([double]$cue.gap))
    }
    if ($cue.offset) { $p = $p.Plus((Vec $cue.offset)) }
    $outPts.Add($p)
  }
  ,$outPts
}
function Draw-Arrow($g, $worldPts, $color) {
  $s = @(); foreach ($w in $worldPts) { $s += ,(ToS $w) }
  Draw-ArrowScreen $g $s $color (0.056 * $script:sc) (0.034 * $script:sc) (0.013 * $script:sc)
}
# seta em pixels: traço até o entalhe da ponta, ponta em forma de flecha alinhada ao fim da curva
function Draw-ArrowScreen($g, $s, $color, [double]$hl, [double]$hw, [double]$lw) {
  $end = $s[$s.Count - 1]; $k = $s.Count - 1
  while ($k -gt 1 -and $end.Minus($s[$k - 1]).Len() -lt $hl) { $k-- }
  $u = $end.Minus($s[$k - 1]).Unit(); $n = $u.Perp()
  $notch = $end.Minus($u.Times($hl * 0.72)); $base = $end.Minus($u.Times($hl))
  $line = New-Object System.Collections.Generic.List[System.Drawing.PointF]
  for ($i = 0; $i -lt $k; $i++) { $line.Add((PF $s[$i])) }
  $line.Add((PF $notch))
  $pen = New-Object System.Drawing.Pen($color, [single]$lw); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
  $g.DrawLines($pen, $line.ToArray()); $pen.Dispose()
  $tri = [System.Drawing.PointF[]]@((PF $end), (PF $base.Plus($n.Times($hw))), (PF $notch), (PF $base.Minus($n.Times($hw))))
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPolygon($br, $tri); $br.Dispose()
}

# ---------------------------------------------------------------- câmera
$script:sc = 100.0; $script:ox = 0.0; $script:oy = 0.0
function ToS([V2]$w) { [V2]::new($script:ox + $w.X * $script:sc, $script:oy - $w.Y * $script:sc) }
function PF([V2]$v) { New-Object System.Drawing.PointF([single]$v.X, [single]$v.Y) }

function Get-Bounds($Gd) {
  $b = @{ minX = 1e9; maxX = -1e9; minY = 0.0; maxY = -1e9 }
  $grow = { param($x1, $y1, $x2, $y2) $b.minX = [Math]::Min($b.minX, $x1); $b.maxX = [Math]::Max($b.maxX, $x2); $b.minY = [Math]::Min($b.minY, $y1); $b.maxY = [Math]::Max($b.maxY, $y2) }
  $last = $Gd.frames.Count - 1
  $propR = @{}; foreach ($pr in $Gd.props) { $r = switch ($pr.kind) { 'barbell' { $Rad.plate } 'dumbbell' { 0.042 } 'vHandle' { 0.05 } default { 0.03 } }; $propR[$pr.id] = $r; $propR[$pr.id + 'Far'] = $r }
  for ($t = 0.0; $t -le $last + 1e-6; $t += 0.1) {
    $sol = Solve-Guide $Gd $t
    foreach ($k in $sol.P.Keys) { $p = $sol.P[$k]; $r = if ($k -eq 'head') { 0.072 } else { 0.062 }; & $grow ($p.X - $r) ($p.Y - $r) ($p.X + $r) ($p.Y + $r) }
    foreach ($k in $sol.props.Keys) { $p = $sol.props[$k]; $r = $propR[$k]; & $grow ($p.X - $r) ($p.Y - $r) ($p.X + $r) ($p.Y + $r) }
  }
  $cp = Get-CuePath $Gd
  if ($null -ne $cp) { foreach ($p in $cp) { & $grow ($p.X - 0.04) ($p.Y - 0.04) ($p.X + 0.04) ($p.Y + 0.04) } }
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

# segmento do corpo: casco tangente a dois círculos; o contorno na cor do fundo separa sobreposições
function Draw-Limb($g, $color, $gapColor, [V2]$a, [double]$ra, [V2]$b, [double]$rb, [V2]$shift) {
  $path = New-HullPath (ToS ($a.Plus($shift))) ($ra * $script:sc) (ToS ($b.Plus($shift))) ($rb * $script:sc)
  if ($null -ne $gapColor) {
    $pen = New-Object System.Drawing.Pen($gapColor, [single]($GapW * $script:sc)); $pen.LineJoin = 'Round'
    $g.DrawPath($pen, $path); $pen.Dispose()
  }
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPath($br, $path); $br.Dispose(); $path.Dispose()
}

# ---------------------------------------------------------------- corpo (vista lateral)
function Draw-Leg($g, $P, [string]$s, $tn, $gap, [V2]$shift) {
  Draw-Limb $g $tn['foot' + $s] $gap $P['heel' + $s] $Rad.heel $P['toe' + $s] $Rad.toe $shift
  Draw-Limb $g $tn['foot' + $s] $null $P['ankle' + $s] $Rad.ankle $P['heel' + $s] $Rad.heel $shift
  Draw-Limb $g $tn['shin' + $s] $gap $P['knee' + $s] $Rad.kneeLow $P['ankle' + $s] $Rad.ankle $shift
  Draw-Limb $g $tn['thigh' + $s] $gap $P.hip $Rad.thighTop $P['knee' + $s] $Rad.knee $shift
}
function Draw-Arm($g, $P, [string]$s, $tn, $gap, [V2]$shift, $shoulder = $null) {
  if ($null -eq $shoulder) { $shoulder = $P.shoulder }
  Draw-Limb $g $tn['upperArm' + $s] $gap $shoulder $Rad.shoulder $P['elbow' + $s] $Rad.elbow $shift
  Draw-Limb $g $tn['forearm' + $s] $gap $P['elbow' + $s] $Rad.elbowLow $P['wrist' + $s] $Rad.wrist $shift
  Draw-Limb $g $tn['forearm' + $s] $null $P['wrist' + $s] $Rad.wrist $P['fist' + $s] $Rad.hand $shift
}
function Draw-TrunkHead($g, $sol, $tn, $gap) {
  $P = $sol.P; $up = [V2]::Dir($sol.ang.trunk); $zero = [V2]::new(0, 0)
  Draw-Limb $g $tn.trunk $gap $P.hip $Rad.hip $P.shoulder.Minus($up.Times(0.012)) $Rad.chest $zero
  Draw-Limb $g $tn.head $null $P.shoulder $Rad.neck $P.head $Rad.neck $zero
  Draw-Limb $g $tn.head $gap $P.head $Rad.head $P.head $Rad.head $zero
  # nariz discreto: diz para onde a pessoa olha sem desenhar rosto
  $face = [V2]::Dir($sol.ang.neck - 90)
  Draw-Limb $g $tn.head $null $P.head.Plus($face.Times(0.047)) 0.017 $P.head.Plus($face.Times(0.061)).Plus([V2]::Dir($sol.ang.neck).Times(-0.004)) 0.011 $zero
}

# ---------------------------------------------------------------- corpo (vista frontal)
function Get-FrontTorsoPts($sol) {
  $P = $sol.P; $u = [V2]::Dir($sol.ang.trunk); $r = [V2]::Dir($sol.ang.trunk - 90)
  ,@(
    $P.neckBase.Plus($r.Times(0.118)).Minus($u.Times(0.01)), $P.hip.Plus($u.Times(0.13)).Plus($r.Times(0.088)), $P.hip.Plus($r.Times(0.100)).Minus($u.Times(0.02)),
    $P.hip.Minus($r.Times(0.100)).Minus($u.Times(0.02)), $P.hip.Plus($u.Times(0.13)).Minus($r.Times(0.088)), $P.neckBase.Minus($r.Times(0.118)).Minus($u.Times(0.01)))
}
function Draw-FrontTorso($g, $sol, $color, $gap) {
  $pts = Get-FrontTorsoPts $sol
  $spts = [System.Drawing.PointF[]]($pts | ForEach-Object { PF (ToS $_) })
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath; $path.AddPolygon($spts)
  $round = 0.05 * $script:sc
  if ($null -ne $gap) { $pg = New-Object System.Drawing.Pen($gap, [single]($round + 2 * $GapW * $script:sc)); $pg.LineJoin = 'Round'; $g.DrawPath($pg, $path); $pg.Dispose() }
  $pen = New-Object System.Drawing.Pen($color, [single]$round); $pen.LineJoin = 'Round'; $g.DrawPath($pen, $path); $pen.Dispose()
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPath($br, $path); $br.Dispose(); $path.Dispose()
}
function Draw-FrontBody($g, $sol, $tn, $gap) {
  $P = $sol.P; $zero = [V2]::new(0, 0)
  foreach ($s in 'Far', '') {
    Draw-Limb $g $tn['foot' + $s] $null $P['ankle' + $s] $Rad.ankle $P['toe' + $s] 0.018 $zero
    Draw-Limb $g $tn['shin' + $s] $gap $P['knee' + $s] $Rad.kneeLow $P['ankle' + $s] $Rad.ankle $zero
    Draw-Limb $g $tn['thigh' + $s] $gap $P['hipJ' + $s] $Rad.thighTop $P['knee' + $s] $Rad.knee $zero
  }
  Draw-FrontTorso $g $sol $tn.trunk $gap
  Draw-Limb $g $tn.head $null $P.neckBase $Rad.neck $P.head $Rad.neck $zero
  Draw-Limb $g $tn.head $gap $P.head $Rad.head $P.head $Rad.head $zero
  foreach ($s in 'Far', '') { Draw-Arm $g $P $s $tn $gap $zero $P['shoulder' + $s] }
}

# ---------------------------------------------------------------- equipamento
function Draw-SceneItem($g, $s, $ink) {
  switch ($s.kind) {
    'bench' {
      $x = [double]$s.x; $top = [double]$s.top; $len = [double]$s.length; $th = 0.042
      foreach ($px in @(($x + 0.10), ($x + $len - 0.10))) {
        Fill-WorldRect $g $ink.structureSoft ($px - 0.014) 0.0 0.028 ($top - $th) 0.004
        Fill-WorldRect $g $ink.structureSoft ($px - 0.075) 0.0 0.15 0.018 0.009
      }
      Fill-WorldRect $g $ink.structure $x ($top - $th) $len $th 0.016
    }
    'seat' {
      $x = [double]$s.x; $top = [double]$s.top; $len = [double]$s.length; $th = 0.042; $mid = $x + $len / 2.0
      Fill-WorldRect $g $ink.structureSoft ($mid - 0.016) 0.03 0.032 ($top - $th - 0.03) 0.004
      Fill-WorldRect $g $ink.structure $x ($top - $th) $len $th 0.016
    }
    'rail' { Fill-WorldRect $g $ink.structureSoft ([double]$s.x1) 0.0 ([double]$s.x2 - [double]$s.x1) 0.036 0.012 }
    'tower' {
      $x = [double]$s.x; $w = [double]$s.width; $h = [double]$s.height
      Fill-WorldRect $g $ink.structureSoft $x 0.0 $w $h 0.02
      $inner = Mix $ink.structureSoft $ink.bg 0.55
      Fill-WorldRect $g $inner ($x + 0.022) 0.05 ($w - 0.044) ($h - 0.10) 0.012
      for ($k = 0; $k -lt 7; $k++) { Fill-WorldRect $g $ink.structure ($x + 0.034) (0.065 + $k * 0.046) ($w - 0.068) 0.036 0.008 }
      Fill-WorldCircle $g $ink.structure ([V2]::new($x + $w / 2.0, $h - 0.045)) 0.02
    }
    'footPlate' {
      $c = Vec $s.at; $ang = [double]$s.angle
      Fill-WorldBar $g $ink.structure $c $ang ([double]$s.length) 0.036
    }
    'pulley' {
      $c = Vec $s.at
      Fill-WorldCircle $g $ink.structure $c 0.028
      Fill-WorldCircle $g $ink.equip $c 0.010
    }
  }
}
function Get-Layer($kind) { switch ($kind) { 'tower' { 'back' } 'rail' { 'back' } 'footPlate' { 'back' } 'bench' { 'mid' } 'seat' { 'mid' } 'pulley' { 'mid' } default { 'mid' } } }

function Draw-Cable($g, $Gd, $sol, $color) {
  foreach ($pr in $Gd.props) {
    if ($pr.kind -ne 'cable') { continue }
    $from = $null; foreach ($s in $Gd.scene) { if ($s.id -eq $pr.from) { $from = Vec $s.at } }
    $to = $sol.props[$pr.to]; if ($null -eq $from -or $null -eq $to) { continue }
    $apex = $to.Plus($from.Minus($to).Unit().Times(0.06))
    Stroke-WorldLine $g $color $from $apex 0.0075
  }
}
function Draw-VHandle($g, $Gd, [V2]$c, $color) {
  $pull = $null; foreach ($q in $Gd.props) { if ($q.kind -eq 'cable') { foreach ($s in $Gd.scene) { if ($s.id -eq $q.from) { $pull = Vec $s.at } } } }
  $dir = if ($pull) { $pull.Minus($c).Unit() } else { [V2]::new(1, 0) }
  $apex = $c.Plus($dir.Times(0.06)); $n = $dir.Perp()
  $top = $c.Plus($n.Times(0.044)); $bot = $c.Minus($n.Times(0.044))
  Stroke-WorldLine $g $color $top $apex 0.013
  Stroke-WorldLine $g $color $bot $apex 0.013
  Stroke-WorldLine $g $color $top $bot 0.022
}
function Draw-Plate($g, [V2]$c, $ink, $color, [bool]$veil) {
  # só a anilha do lado de cá, vista de frente: aro + véu translúcido para o corpo continuar legível atrás dela
  if ($veil) { Fill-WorldCircle $g (WithAlpha $ink.bg 80) $c $Rad.plate }
  Stroke-WorldCircle $g $color $c ($Rad.plate - 0.007) 0.014
  Fill-WorldCircle $g $color $c 0.017
}
function Draw-Dumbbell($g, [V2]$c, $ink, $color, [bool]$veil) {
  # halter visto de ponta (a pegada aponta para a câmera): disco + miolo
  if ($veil) { Fill-WorldCircle $g (WithAlpha $ink.bg 80) $c 0.041 }
  Stroke-WorldCircle $g $color $c 0.034 0.013
  Fill-WorldCircle $g $color $c 0.012
}
function Draw-HeldProps($g, $Gd, $sol, $ink, [string]$when) {
  foreach ($pr in $Gd.props) {
    $c = $sol.props[$pr.id]; if ($null -eq $c) { continue }
    if ($pr.kind -eq 'vHandle' -and $when -eq 'beforeNearArm') { Draw-VHandle $g $Gd $c $ink.equip }
    if ($pr.kind -eq 'dumbbell' -and $when -eq 'front') {
      foreach ($hc in @($c, $sol.props[$pr.id + 'Far'])) { if ($null -ne $hc) { Draw-Dumbbell $g $hc $ink $ink.equip $true } }
    }
    # barra nas costas: atrás do tronco, com metade escondida pelo corpo (lê como "apoiada nas costas", não "no peito")
    if ($pr.kind -eq 'barbell' -and $pr.attach -eq 'back' -and $when -eq 'behindTrunk') { Draw-Plate $g $c $ink $ink.equip $false }
    if ($pr.kind -eq 'barbell' -and $pr.attach -ne 'back' -and $when -eq 'front') { Draw-Plate $g $c $ink $ink.equip $true }
  }
}

# ---------------------------------------------------------------- fantasma (posição inicial, no quadro final)
# Formas do corpo na mesma ordem para qualquer pose (cascos entre dois círculos e, de frente, o polígono do tronco),
# para comparar forma a forma a pose do fantasma com a pose atual. Vista lateral: só o lado de cá.
function Get-BodyShapes($sol) {
  $P = $sol.P; $L = New-Object System.Collections.Generic.List[object]
  $hull = { param($a, $ra, $b, $rb) $L.Add(@{ kind = 'hull'; a = $a; ra = $ra; b = $b; rb = $rb }) }
  if ($sol.front) {
    foreach ($s in 'Far', '') {
      & $hull $P['ankle' + $s] $Rad.ankle $P['toe' + $s] 0.018
      & $hull $P['knee' + $s] $Rad.kneeLow $P['ankle' + $s] $Rad.ankle
      & $hull $P['hipJ' + $s] $Rad.thighTop $P['knee' + $s] $Rad.knee
    }
    $L.Add(@{ kind = 'torso'; pts = (Get-FrontTorsoPts $sol) })
    & $hull $P.neckBase $Rad.neck $P.head $Rad.neck
    & $hull $P.head $Rad.head $P.head $Rad.head
    foreach ($s in 'Far', '') {
      & $hull $P['shoulder' + $s] $Rad.shoulder $P['elbow' + $s] $Rad.elbow
      & $hull $P['elbow' + $s] $Rad.elbowLow $P['wrist' + $s] $Rad.wrist
      & $hull $P['wrist' + $s] $Rad.wrist $P['fist' + $s] $Rad.hand
    }
  } else {
    $up = [V2]::Dir($sol.ang.trunk); $face = [V2]::Dir($sol.ang.neck - 90)
    & $hull $P.heel $Rad.heel $P.toe $Rad.toe
    & $hull $P.ankle $Rad.ankle $P.heel $Rad.heel
    & $hull $P.knee $Rad.kneeLow $P.ankle $Rad.ankle
    & $hull $P.hip $Rad.thighTop $P.knee $Rad.knee
    & $hull $P.hip $Rad.hip $P.shoulder.Minus($up.Times(0.012)) $Rad.chest
    & $hull $P.shoulder $Rad.neck $P.head $Rad.neck
    & $hull $P.head $Rad.head $P.head $Rad.head
    & $hull $P.head.Plus($face.Times(0.047)) 0.017 $P.head.Plus($face.Times(0.061)).Plus([V2]::Dir($sol.ang.neck).Times(-0.004)) 0.011
    & $hull $P.shoulder $Rad.shoulder $P.elbow $Rad.elbow
    & $hull $P.elbow $Rad.elbowLow $P.wrist $Rad.wrist
    & $hull $P.wrist $Rad.wrist $P.fist $Rad.hand
  }
  ,$L
}
$GhostTol = 0.02                        # só entra no fantasma o que mudou de lugar mais que 0,02 H
function Test-ShapeMoved($s0, $s1) {
  if ($s0.kind -eq 'torso') { for ($i = 0; $i -lt $s0.pts.Count; $i++) { if ($s0.pts[$i].Minus($s1.pts[$i]).Len() -gt $GhostTol) { return $true } }; return $false }
  ($s0.a.Minus($s1.a).Len() -gt $GhostTol) -or ($s0.b.Minus($s1.b).Len() -gt $GhostTol)
}
function New-ShapePath($sh) {
  if ($sh.kind -eq 'torso') {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddPolygon([System.Drawing.PointF[]]($sh.pts | ForEach-Object { PF (ToS $_) })); return $p
  }
  New-HullPath (ToS $sh.a) ($sh.ra * $script:sc) (ToS $sh.b) ($sh.rb * $script:sc)
}
# Contorno tracejado da UNIÃO das formas: 1ª passada traça cada forma com o dobro da espessura; a 2ª preenche todas
# por cima, cobrindo a metade de dentro do traço e as linhas internas onde as formas se sobrepõem.
function Draw-GhostShapes($g, $shapes, $ink) {
  $lw = 0.0075 * $script:sc; $round = 0.05 * $script:sc; $dash = 0.026 * $script:sc; $gapLen = 0.017 * $script:sc
  foreach ($sh in $shapes) {
    $path = New-ShapePath $sh; $w = 2 * $lw; if ($sh.kind -eq 'torso') { $w += $round }
    $pen = New-Object System.Drawing.Pen($ink.ghostLine, [single]$w); $pen.LineJoin = 'Round'
    $pen.DashPattern = [single[]]@(($dash / $w), ($gapLen / $w))
    $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
  }
  foreach ($sh in $shapes) {
    $path = New-ShapePath $sh; $br = New-Object System.Drawing.SolidBrush($ink.ghostFill); $g.FillPath($br, $path); $br.Dispose()
    if ($sh.kind -eq 'torso') { $pen = New-Object System.Drawing.Pen($ink.ghostFill, [single]$round); $pen.LineJoin = 'Round'; $g.DrawPath($pen, $path); $pen.Dispose() }
    $path.Dispose()
  }
}
# Posição do instante $t desenhada por baixo da pose do instante $tNow: só as formas e os acessórios que mudaram de
# lugar. Se o tronco não se move (supino, remada, elevação), o fantasma fica só nos braços e no implemento, presos
# ao mesmo ombro; se o tronco se move (agachamento), o corpo todo muda de lugar e aparece inteiro.
function Draw-Ghost($g, $Gd, [double]$t, [double]$tNow, $ink) {
  $sol = Solve-Guide $Gd $t; $now = Solve-Guide $Gd $tNow
  $a = Get-BodyShapes $sol; $b = Get-BodyShapes $now
  $sel = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $a.Count; $i++) { if (Test-ShapeMoved $a[$i] $b[$i]) { $sel.Add($a[$i]) } }
  $moved = @{}
  foreach ($k in $sol.props.Keys) { $p1 = $now.props[$k]; $moved[$k] = ($null -eq $p1) -or ($sol.props[$k].Minus($p1).Len() -gt $GhostTol) }
  foreach ($pr in $Gd.props) { if ($pr.kind -eq 'barbell' -and $pr.attach -eq 'back' -and $moved[$pr.id]) { Draw-Plate $g $sol.props[$pr.id] $ink $ink.ghostLine $false } }
  Draw-GhostShapes $g $sel $ink
  foreach ($pr in $Gd.props) {
    switch ($pr.kind) {
      'barbell'  { if ($pr.attach -ne 'back' -and $moved[$pr.id]) { Draw-Plate $g $sol.props[$pr.id] $ink $ink.ghostLine $false } }
      'vHandle'  { if ($moved[$pr.id]) { Draw-VHandle $g $Gd $sol.props[$pr.id] $ink.ghostLine } }
      'dumbbell' { foreach ($k in @($pr.id, ($pr.id + 'Far'))) { if ($moved[$k]) { Draw-Dumbbell $g $sol.props[$k] $ink $ink.ghostLine $false } } }
    }
  }
}

# Desenha um quadro completo dentro de $rect. $opts: bottomPad, ghostT (posição anterior), cue ($true/$false)
function Draw-Frame($g, [System.Drawing.RectangleF]$rect, $Gd, [double]$t, $ink, [double]$scale, $bounds, $opts) {
  Set-Camera $rect $bounds $scale ([double]$opts.bottomPad)
  # chão
  $fy = $script:oy
  $pen = New-Object System.Drawing.Pen($ink.floor, [single](0.007 * $script:sc)); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
  $g.DrawLine($pen, [single]($rect.X + 0.05 * $rect.Width), [single]$fy, [single]($rect.Right - 0.05 * $rect.Width), [single]$fy); $pen.Dispose()

  foreach ($s in $Gd.scene) { if ((Get-Layer $s.kind) -eq 'back') { Draw-SceneItem $g $s $ink } }
  if ($null -ne $opts.ghostT) { Draw-Ghost $g $Gd ([double]$opts.ghostT) $t $ink }
  $sol = Solve-Guide $Gd $t; $P = $sol.P; $tn = Get-Tones $ink $movingBy[$Gd.slug] ([bool]$sol.front); $zero = [V2]::new(0, 0)
  if ($sol.front) {
    Draw-FrontBody $g $sol $tn $ink.bg; Draw-HeldProps $g $Gd $sol $ink 'front'
  } else {
    Draw-Arm $g $P 'Far' $tn $null $FarShift
    Draw-Leg $g $P 'Far' $tn $null $FarShift
    foreach ($s in $Gd.scene) { if ((Get-Layer $s.kind) -eq 'mid') { Draw-SceneItem $g $s $ink } }
    Draw-Cable $g $Gd $sol $ink.equip
    Draw-HeldProps $g $Gd $sol $ink 'behindTrunk'
    Draw-TrunkHead $g $sol $tn $ink.bg
    Draw-Leg $g $P '' $tn $ink.bg $zero
    Draw-HeldProps $g $Gd $sol $ink 'beforeNearArm'
    Draw-Arm $g $P '' $tn $ink.bg $zero
    Draw-HeldProps $g $Gd $sol $ink 'front'
  }
  if ($opts.cue -and $null -ne $cueBy[$Gd.slug]) { Draw-Arrow $g $cueBy[$Gd.slug] $ink.arrow }
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
function TextWidth($g, [string]$text, $font) {
  $fmt = [System.Drawing.StringFormat]::GenericTypographic
  [double]$g.MeasureString($text, $font, 4000, $fmt).Width
}
# Trecho numa linha só, para emendar trechos de pesos diferentes. Mede e desenha sem ajuste à grade de pixels
# (AntiAlias), senão a largura medida cresce com o comprimento do texto e o espaço depois dele varia.
function Draw-Run($g, [string]$text, $font, $color, [double]$x, [double]$y) {
  $hint = $g.TextRenderingHint; $g.TextRenderingHint = 'AntiAlias'
  $fmt = [System.Drawing.StringFormat]::GenericTypographic
  $br = New-Object System.Drawing.SolidBrush($color); $g.DrawString($text, $font, $br, [single]$x, [single]$y, $fmt); $br.Dispose()
  $w = [double]$g.MeasureString($text, $font, 4000, $fmt).Width; $g.TextRenderingHint = $hint; $w
}
# Erro comum no formato "o erro: o que fazer". O erro vai em semibold, a correção em regular, na mesma linha se couber.
function Draw-Mistake($g, [string]$text, $fontBold, $font, $ink, [double]$x, [double]$y, [double]$w) {
  $i = $text.IndexOf(': ')
  if ($i -lt 0) { return (Draw-Text $g $text $font $ink.text $x $y $w) }
  $head = $text.Substring(0, $i + 1); $tail = $text.Substring($i + 2); $space = 0.3 * $font.Size
  if ((TextWidth $g $head $fontBold) + $space + (TextWidth $g $tail $font) -le $w) {
    $w1 = Draw-Run $g $head $fontBold $ink.text $x ($y + 2); [void](Draw-Run $g $tail $font $ink.text ($x + $w1 + $space) ($y + 2))
    return [double]$fontBold.GetHeight($g) + 3
  }
  $h1 = Draw-Text $g $head $fontBold $ink.text $x $y $w
  $h1 + (Draw-Text $g $tail $font $ink.text $x ($y + $h1) $w)
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
function Draw-Badge($g, $ink, [string]$label, [double]$x, [double]$y, [double]$d) {
  Fill-Round $g $ink.accentSoft $x $y $d $d ($d / 2.0)
  $f = New-Font 'Segoe UI Semibold' ($d * 0.54)
  $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $br = New-Object System.Drawing.SolidBrush($ink.accent); $g.DrawString($label, $f, $br, (New-Object System.Drawing.RectangleF([single]$x, [single]($y + 1), [single]$d, [single]$d)), $fmt)
  $br.Dispose(); $fmt.Dispose(); $f.Dispose()
}

# ---------------------------------------------------------------- dados
$doc = Get-Content -Raw -Encoding UTF8 $Data | ConvertFrom-Json
$names = @{}; $muscles = @{}
if (Test-Path $Catalog) { (Get-Content -Raw -Encoding UTF8 $Catalog | ConvertFrom-Json).exercises | ForEach-Object { $names[$_.slug] = $_.name; $muscles[$_.slug] = @($_.primaryMuscles) } }
else { Write-Warning "catálogo não encontrado: $Catalog" }
# mesmos nomes de ReviewText.muscleName (TrainerCore), em minúsculas porque entram no meio da frase
$MuscleNames = @{ chest = 'peito'; back = 'costas'; shoulders = 'ombros'; biceps = 'bíceps'; triceps = 'tríceps'; quads = 'quadríceps'
                  hamstrings = 'posteriores da coxa'; glutes = 'glúteos'; calves = 'panturrilhas'; core = 'abdômen e lombar' }
# Termo técnico que o app mantém (é o nome do grupo no catálogo e na Home) ganha a explicação em palavras comuns no
# "Trabalha:", como pede o DESIGN §7 ("termos técnicos úteis ficam, com explicação no primeiro uso"). Os outros nomes
# do catálogo já são palavras do dia a dia.
$MuscleGloss = @{ quads = 'frente das coxas' }
function NameOf($Gd) { if ($names.ContainsKey($Gd.slug)) { $names[$Gd.slug] } else { $Gd.slug } }
function WorksOf($Gd) {
  $list = @()
  foreach ($m in $muscles[$Gd.slug]) {
    $nm = if ($MuscleNames.ContainsKey($m)) { $MuscleNames[$m] } else { $m }
    if ($MuscleGloss.ContainsKey($m)) { $nm = '{0} ({1})' -f $nm, $MuscleGloss[$m] }
    $list += $nm
  }
  if ($list.Count -eq 0) { return '' }
  if ($list.Count -eq 1) { return $list[0] }
  (($list[0..($list.Count - 2)]) -join ', ') + ' e ' + $list[$list.Count - 1]
}
function Save-Png($c, [string]$path) { $c.g.Dispose(); $c.bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $c.bmp.Dispose(); Write-Host "ok  $path" }

$guides = @($doc.guides)
# conferências de conteúdo (SPEC §7.12 E2 proposto): 3 passos, 2 erros, até 120 caracteres; legenda de quadro curta
foreach ($Gd in $guides) {
  if (@($Gd.steps).Count -ne 3 -or @($Gd.mistakes).Count -ne 2) { Write-Warning "$($Gd.slug): precisa de 3 passos e 2 erros" }
  foreach ($txt in @($Gd.steps) + @($Gd.mistakes)) { if ($txt.Length -gt 120) { Write-Warning "$($Gd.slug): texto com $($txt.Length) caracteres (máx. 120): $txt" } }
  foreach ($fr in $Gd.frames) { if ($null -eq $fr.caption -or $fr.caption.Length -gt 28) { Write-Warning "$($Gd.slug): legenda ausente ou longa: '$($fr.caption)'" } }
}
Test-Contrast
Write-Host 'o que se move (MOVE = acento forte):'
$movingBy = @{}; $cueBy = @{}; $boundsBy = @{}
foreach ($Gd in $guides) { $movingBy[$Gd.slug] = Get-Moving $Gd; $cueBy[$Gd.slug] = Get-CuePath $Gd; $boundsBy[$Gd.slug] = Get-Bounds $Gd }

# mesma escala para todos: o corpo tem o mesmo tamanho em qualquer exercício (padronização, E3)
function Get-CommonScale([double]$w, [double]$h, [double]$pad, [double]$topPad, [double]$bottomPad) {
  $s = 1e9
  foreach ($Gd in $guides) { $b = $boundsBy[$Gd.slug]; $s = [Math]::Min($s, [Math]::Min(($w - 2 * $pad) / ($b.maxX - $b.minX), ($h - $bottomPad - $topPad) / ($b.maxY - $b.minY))) }
  $s
}

# ---------------------------------------------------------------- folha de comparação
$ColW = 920; $Gutter = 36; $CardPad = 28; $Between = 32
$Panel = [int][Math]::Floor(($ColW - 2 * $CardPad - $Between) / 2)
$PanelOpts = @{ side = 8; top = 10; bottom = 14 }

# Cartão de um exercício; devolve a coordenada y do fim do conteúdo.
function Draw-Card($g, $ink, $Gd, [double]$x0, [double]$y0, [double]$scale) {
  $tw = $ColW - 2 * $CardPad; $x = $x0 + $CardPad
  $y = $y0 + 22
  $fn = New-Font 'Georgia' 31; $y += (Draw-Text $g (NameOf $Gd) $fn $ink.text $x $y $tw); $fn.Dispose()
  $y += 2
  $works = WorksOf $Gd
  if ($works -ne '') {
    $fl = New-Font 'Segoe UI Semibold' 18; $fv = New-Font 'Segoe UI' 18
    $wl = TextWidth $g 'Trabalha:' $fl
    [void](Draw-Text $g 'Trabalha:' $fl $ink.text2 $x $y 200)
    $h = Draw-Text $g $works $fv $ink.text ($x + $wl + 6) $y ($tw - $wl - 6)
    $y += $h; $fl.Dispose(); $fv.Dispose()
  }
  $y += 16
  $py = $y; $last = $Gd.frames.Count - 1
  for ($f = 0; $f -le 1; $f++) {
    $px = $x + $f * ($Panel + $Between)
    Fill-Round $g $ink.page $px $py $Panel $Panel 18
    $r = New-Object System.Drawing.RectangleF([single]$px, [single]$py, [single]$Panel, [single]$Panel)
    $opts = @{ bottomPad = $PanelOpts.bottom; cue = ($f -eq 0); ghostT = $null }
    if ($f -eq 1) { $opts.ghostT = 0.0 }
    Draw-Frame $g $r $Gd ([double]($f * $last)) $ink $scale $boundsBy[$Gd.slug] $opts
    # legenda do quadro: número + posição-chave
    $fr = $Gd.frames[$f * $last]; $cap = if ($fr.caption) { $fr.caption } else { $fr.label }
    Draw-Badge $g $ink ([string]($f + 1)) $px ($py + $Panel + 14) 28
    $fc = New-Font 'Segoe UI Semibold' 18; [void](Draw-Text $g $cap $fc $ink.text ($px + 38) ($py + $Panel + 15) ($Panel - 38)); $fc.Dispose()
  }
  # seta entre os quadros
  $ax = $x + $Panel + $Between / 2.0; $ay = $py + $Panel / 2.0
  $pen = New-Object System.Drawing.Pen($ink.text2, 2.6); $pen.EndCap = 'Round'; $pen.StartCap = 'Round'; $pen.LineJoin = 'Round'
  $g.DrawLine($pen, [single]($ax - 9), [single]$ay, [single]($ax + 8), [single]$ay)
  $g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF([single]($ax + 1), [single]($ay - 7))), (New-Object System.Drawing.PointF([single]($ax + 8), [single]$ay)), (New-Object System.Drawing.PointF([single]($ax + 1), [single]($ay + 7)))))
  $pen.Dispose()

  $y = $py + $Panel + 14 + 28 + 26
  $sw = $tw - 42
  $fh = New-Font 'Segoe UI Semibold' 18; $fb = New-Font 'Segoe UI' 17.5; $fbb = New-Font 'Segoe UI Semibold' 17.5; $fsm = New-Font 'Segoe UI' 15
  $y += (Draw-Text $g 'Passos' $fh $ink.text $x $y $tw) + 8
  $n = 1
  foreach ($step in $Gd.steps) {
    Draw-Badge $g $ink ([string]$n) $x ($y + 1) 28
    $y += [Math]::Max(30, (Draw-Text $g $step $fb $ink.text ($x + 42) ($y + 2) $sw)) + 10
    $n++
  }
  $y += 12
  $y += (Draw-Text $g 'Erros comuns' $fh $ink.text $x $y $tw) + 8
  foreach ($m in $Gd.mistakes) {
    $pen = New-Object System.Drawing.Pen($ink.text2, 2); $g.DrawEllipse($pen, [single]($x + 9), [single]($y + 8), 10, 10); $pen.Dispose()
    $y += (Draw-Mistake $g $m $fbb $fb $ink ($x + 42) $y $sw) + 10
  }
  $y += 14
  $line = New-Object System.Drawing.Pen((Mix $ink.text2 $ink.surface 0.8), 1); $g.DrawLine($line, [single]$x, [single]$y, [single]($x0 + $ColW - $CardPad), [single]$y); $line.Dispose()
  $y += 12
  $y += (Draw-Text $g ('VoiceOver: "' + $Gd.a11y + '"') $fsm $ink.text2 $x $y $tw) + 4
  $fh.Dispose(); $fb.Dispose(); $fbb.Dispose(); $fsm.Dispose()
  $y
}

# Cabeçalho com título, explicação e legenda de cores; devolve a coordenada y do fim.
function Draw-Header($g, $ink, [double]$W) {
  $ft = New-Font 'Georgia' 40; [void](Draw-Text $g 'Como fazer' $ft $ink.text $Gutter 28 900); $ft.Dispose()
  $fs = New-Font 'Segoe UI' 18
  $sub = 'Versão 2 do protótipo, revisada para ficar mais clara. No app a figura anima em loop entre os dois quadros; com Reduzir Movimento, os quadros ficam parados lado a lado, como aqui.'
  $y = 88 + (Draw-Text $g $sub $fs $ink.text2 $Gutter 88 ($W - 2 * $Gutter)) + 14
  $fs.Dispose()
  # legenda: amostras desenhadas sobre o fundo do quadro, com as mesmas cores da figura. É só desta folha de
  # revisão: no app a folha "Como fazer" não tem legenda (a figura tem que se explicar sozinha).
  $items = @(
    @('limb', $ink.nearMove, 'o que se move'), @('limb', $ink.nearStill, 'resto do corpo'), @('pair', $null, 'lado de lá, mais suave'),
    @('ghost', $null, 'posição inicial (quadro 2)'), @('arrow', $ink.arrow, 'caminho da ida (quadro 1)'), @('ring', $ink.equip, 'equipamento que se move'))
  $fl = New-Font 'Segoe UI' 16.5; $flb = New-Font 'Segoe UI Semibold' 16.5
  $lead = 'Legenda da revisão (não vai para o app):'
  $leadW = TextWidth $g $lead $flb
  $totalW = $leadW + 24; foreach ($it in $items) { $totalW += 44 + 10 + (TextWidth $g $it[2] $fl) + 30 }
  # a pílula usa o mesmo fundo dos quadros, para as amostras terem exatamente o contraste da figura
  $pillW = [Math]::Min($W - 2 * $Gutter, $totalW + 24)
  Fill-Round $g (Mix $ink.text2 $ink.page 0.72) ($Gutter - 1.5) ($y - 1.5) ($pillW + 3) 47 23.5
  Fill-Round $g $ink.page $Gutter $y $pillW 44 22
  $x = $Gutter + 20; $cy = $y + 22
  [void](Draw-Text $g $lead $flb $ink.text2 $x ($cy - 11.5) ($leadW + 20)); $x += $leadW + 24
  $script:sc = 100.0
  foreach ($it in $items) {
    switch ($it[0]) {
      'limb' { $p = New-HullPath ([V2]::new($x + 7, $cy)) 7 ([V2]::new($x + 37, $cy)) 7; $b = New-Object System.Drawing.SolidBrush($it[1]); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose() }
      'ghost' {
        # mesmo desenho do fantasma: traço tracejado com o dobro da espessura, miolo por cima
        $p = New-HullPath ([V2]::new($x + 7, $cy)) 7 ([V2]::new($x + 37, $cy)) 7
        $pen = New-Object System.Drawing.Pen($ink.ghostLine, 5.0); $pen.DashPattern = [single[]]@(1.8, 1.2); $g.DrawPath($pen, $p); $pen.Dispose()
        $b = New-Object System.Drawing.SolidBrush($ink.ghostFill); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
      }
      'pair' {
        $p = New-HullPath ([V2]::new($x + 7, $cy - 4)) 6 ([V2]::new($x + 37, $cy - 4)) 6; $b = New-Object System.Drawing.SolidBrush($ink.farMove); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
        $p = New-HullPath ([V2]::new($x + 7, $cy + 5)) 6 ([V2]::new($x + 37, $cy + 5)) 6; $b = New-Object System.Drawing.SolidBrush($ink.farStill); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
      }
      'arrow' {
        # arco suave da esquerda para a direita, descendo no fim, com a mesma ponta da figura
        $pts = @(); for ($i = 0; $i -le 16; $i++) { $a = [Math]::PI * (1.0 - 0.75 * $i / 16); $pts += ,([V2]::new($x + 22 + 20 * [Math]::Cos($a), $cy + 9 - 13 * [Math]::Sin($a))) }
        Draw-ArrowScreen $g $pts $it[1] 13 8 3.6
      }
      'ring' {
        $pen = New-Object System.Drawing.Pen($it[1], 4); $g.DrawEllipse($pen, [single]($x + 11), [single]($cy - 11), 22, 22); $pen.Dispose()
        $b = New-Object System.Drawing.SolidBrush($it[1]); $g.FillEllipse($b, [single]($x + 18.5), [single]($cy - 3.5), 7, 7); $b.Dispose()
      }
    }
    $tw = TextWidth $g $it[2] $fl
    [void](Draw-Text $g $it[2] $fl $ink.text ($x + 54) ($cy - 11.5) ($tw + 20))
    $x += 44 + 10 + $tw + 30
  }
  $fl.Dispose(); $flb.Dispose()
  $y + 44 + 26
}

function Render-Compare([string]$look, [string]$file) {
  $ink = New-Ink $look
  $cols = 2; $rows = [int][Math]::Ceiling($guides.Count / $cols)
  $W = $cols * $ColW + ($cols + 1) * $Gutter
  $scale = Get-CommonScale $Panel $Panel $PanelOpts.side $PanelOpts.top $PanelOpts.bottom
  # 1ª passada: mede cabeçalho e cartões numa tela descartável
  $probe = New-Canvas $W 2400; $headH = Draw-Header $probe.g $ink $W
  $heights = @(); foreach ($Gd in $guides) { $heights += (Draw-Card $probe.g $ink $Gd 0 0 $scale) }
  $probe.g.Dispose(); $probe.bmp.Dispose()
  $rowH = @(); for ($r = 0; $r -lt $rows; $r++) { $m = 0.0; for ($c = 0; $c -lt $cols; $c++) { $i = $r * $cols + $c; if ($i -lt $guides.Count) { $m = [Math]::Max($m, $heights[$i]) } }; $rowH += $m + 26 }
  $H = [int][Math]::Ceiling($headH + ($rowH | Measure-Object -Sum).Sum + ($rows - 1) * $Gutter + 72)
  # 2ª passada: desenha
  $cv = New-Canvas $W $H; $g = $cv.g; $g.Clear($ink.page)
  [void](Draw-Header $g $ink $W)
  $y = $headH
  for ($r = 0; $r -lt $rows; $r++) {
    for ($c = 0; $c -lt $cols; $c++) {
      $i = $r * $cols + $c; if ($i -ge $guides.Count) { continue }
      $x0 = $Gutter + $c * ($ColW + $Gutter)
      Fill-Round $g $ink.surface $x0 $y $ColW $rowH[$r] 24
      [void](Draw-Card $g $ink $guides[$i] $x0 $y $scale)
    }
    $y += $rowH[$r] + $Gutter
  }
  $ff = New-Font 'Segoe UI' 15
  [void](Draw-Text $g 'Cores: DESIGN.md §3 e §12 (proposto) · proporções: Drillis e Contini (1966), em Winter · grupos trabalhados: primaryMuscles de exercises.v2.json · dados: exercise-guides.sample.json (ângulos por segmento, 2 quadros, âncora, IK dos braços, escorço, seta)' $ff $ink.text2 $Gutter ($H - 50) ($W - 2 * $Gutter))
  $ff.Dispose()
  Save-Png $cv (Join-Path $Out $file)
  Write-Host ("escala comum: {0:0} px por estatura; quadro de {1} px" -f $scale, $Panel)
}
Render-Compare 'light' 'compare-v2.png'
Render-Compare 'dark' 'compare-v2-dark.png'

# ---------------------------------------------------------------- extras: quadros individuais e tira de interpolação
if ($Extras -ne '') {
  New-Item -ItemType Directory -Force -Path $Extras | Out-Null
  $ink = New-Ink 'light'
  $S = 640; $scale1 = Get-CommonScale $S $S 30 30 40
  foreach ($Gd in $guides) {
    $last = $Gd.frames.Count - 1
    for ($f = 0; $f -le $last; $f++) {
      $c = New-Canvas $S $S; $c.g.Clear($ink.page)
      $r = New-Object System.Drawing.RectangleF(0, 0, $S, $S)
      $opts = @{ bottomPad = 40; cue = ($f -eq 0); ghostT = $null }; if ($f -gt 0) { $opts.ghostT = [double]($f - 1) }
      Draw-Frame $c.g $r $Gd ([double]$f) $ink $scale1 $boundsBy[$Gd.slug] $opts
      $fc = New-Font 'Segoe UI Semibold' 22; [void](Draw-Text $c.g ("{0} · {1}" -f ($f + 1), $Gd.frames[$f].caption) $fc $ink.text 20 14 600); $fc.Dispose()
      $suffix = if ($f -eq 0) { 'inicio' } else { 'fim' }
      Save-Png $c (Join-Path $Extras ("{0}-{1}-{2}.png" -f $Gd.slug, ($f + 1), $suffix))
    }
  }
  $cell = 260; $gap = 12; $left = 250; $top = 60
  $W = $left + 5 * $cell + 4 * $gap + 36; $H = $top + $guides.Count * ($cell + $gap) + 30
  $c = New-Canvas $W $H; $g = $c.g; $g.Clear($ink.page)
  $ft = New-Font 'Georgia' 28; [void](Draw-Text $g 'Interpolação entre os quadros-chave (v2)' $ft $ink.text 36 16 1400); $ft.Dispose()
  $scale2 = Get-CommonScale $cell $cell 10 26 14
  $row = 0
  foreach ($Gd in $guides) {
    $y = $top + $row * ($cell + $gap)
    $fn = New-Font 'Georgia' 21; [void](Draw-Text $g (NameOf $Gd) $fn $ink.text 36 ($y + 20) ($left - 50)); $fn.Dispose()
    for ($k = 0; $k -lt 5; $k++) {
      $x = $left + $k * ($cell + $gap); $u = $k / 4.0
      Fill-Round $g $ink.surface $x $y $cell $cell 16
      $r = New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$cell, [single]$cell)
      $inkS = $ink.Clone(); $inkS.bg = $ink.surface
      Draw-Frame $g $r $Gd ($u * ($Gd.frames.Count - 1)) $inkS $scale2 $boundsBy[$Gd.slug] @{ bottomPad = 14; cue = $false }
      $fp = New-Font 'Segoe UI Semibold' 14; [void](Draw-Text $g ("{0}%" -f [int]($u * 100)) $fp $ink.text2 ($x + 10) ($y + 8) 80); $fp.Dispose()
    }
    $row++
  }
  Save-Png $c (Join-Path $Extras 'interpolation-strip-v2.png')
}
