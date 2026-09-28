# render-exercise-guides.ps1 — ferramenta de autoria do "Como fazer" (SPEC RF-40 e §7.12; docs/V23-CORE-CONTRACT.md
# §2.5 a §2.7). Promovida do protótipo v2, aprovado pelo dono em 2026-09-24.
#
# Desenha o manequim neutro do Magister a partir das guias em dados, com o MESMO cálculo que o app faz em
# Packages/TrainerCore/Sources/TrainerCore/Guide (GuideKinematics, GuideMotion). O golden gravado por -Golden é
# comparado pelo GuideGoldenTests em até 0,001 H: mudar o cálculo aqui sem mudar lá (ou o contrário) quebra o CI.
#   1. interpolação: para um instante t entre dois quadros-chave, cada ângulo de segmento vai pelo arco mais curto,
#      com easeInOut (senoide), dentro de cada trecho entre quadros;
#   2. cinemática direta: a partir do quadril, soma segmentos de comprimento fixo (Drillis e Contini, 1966, em
#      Winter) nas direções absolutas interpoladas; "legDepth" encurta coxa e perna (escorço);
#   3. âncora: translada o corpo inteiro para que a articulação-âncora (qualquer ponto do esqueleto) fique parada;
#      com "anchor": "none" (saltos), o quadril segue "root" de cada quadro e não há translação;
#   4. braços: por ângulos (cinemática direta, antes da âncora) ou por IK de dois ossos até a pegada do quadro ou
#      até um acessório nas costas, no peito ou no quadril (depois da âncora). "arms.forearm" trava o antebraço;
#      "farArm": "pose" deixa o braço de lá seguir os ângulos do quadro enquanto o de cá usa IK;
#   5. acessórios depois dos braços: num ponto do esqueleto, nas costas ou no peito, ou ao longo de um segmento;
#   6. desenho em camadas: cena de fundo -> fantasma -> lado de lá -> cena do meio -> cabos -> tronco -> perna e
#      braço do lado de cá -> acessórios -> cena da frente -> seta.
#
# Clareza (DESIGN §12): o que se move fica em accent; o resto do corpo em accent misturado ao fundo ("moving" no
# JSON sobrepõe o cálculo); o lado de lá é mais claro; seta sólida no quadro 1; fantasma tracejado da posição
# inicial nos quadros seguintes (só em "loop"); legenda por quadro e "Trabalha: ..." (ou "works"). O script confere
# os contrastes e para com erro se algum gráfico essencial ficar abaixo de 3:1.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File render-exercise-guides.ps1 [opções]
#   -Check                só valida (§2.5). Imprime "ok <slug>" ou "ERRO <slug> <regra>: <motivo>"; sai com 1 se houver erro
#   -Sheet <nome>         gera sheet-<nome>.png e sheet-<nome>-dark.png, com todos os quadros de cada guia
#   -Golden <saída.json>  grava as coordenadas de referência (t = 0, 1/4, 1/2, 3/4 e 1 x (n - 1))
#   -Vocabulary           gera vocabulary.png a partir de vocabulary.sample.json (claro em cima, escuro embaixo)
#   -Data <json>          arquivo de guias (padrão: PersonalTrainer/Resources/Seed/exercise-guides.v1.json)
#   -Catalog <json>       catálogo do seed (padrão: PersonalTrainer/Resources/Seed/exercises.v2.json)
#   -Only <slug,slug>     filtra as guias
#   -Out <pasta>          pasta de saída (padrão: a deste script)
# Toda saída (-Sheet, -Golden, -Vocabulary) valida antes e não grava nada se houver erro.
param(
  [string]$Data = '',
  [string]$Catalog = '',
  [switch]$Check,
  [string]$Sheet = '',
  [string]$Golden = '',
  [string]$Only = '',
  [switch]$Vocabulary,
  [string]$Out = '',
  # Interna: desliga o catálogo (E1 e "works" obrigatório). O -Vocabulary liga sozinho, porque os slugs vocab-*
  # não estão no catálogo e nunca vão para o seed.
  [switch]$NoCatalog
)
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\..'))
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$useCatalog = -not ($NoCatalog -or $Vocabulary)
function Resolve-Input([string]$path) {
  if ([System.IO.Path]::IsPathRooted($path)) { return $path }
  $fromCwd = Join-Path (Get-Location).Path $path
  if (Test-Path $fromCwd) { return [System.IO.Path]::GetFullPath($fromCwd) }
  [System.IO.Path]::GetFullPath((Join-Path $here $path))
}
if ($Data -eq '') {
  if ($Vocabulary) { $Data = Join-Path $here 'vocabulary.sample.json' }
  else { $Data = Join-Path $repo 'PersonalTrainer\Resources\Seed\exercise-guides.v1.json' }
}
$Data = Resolve-Input $Data
if ($Catalog -eq '') { $Catalog = Join-Path $repo 'PersonalTrainer\Resources\Seed\exercises.v2.json' } else { $Catalog = Resolve-Input $Catalog }
if ($Out -eq '') { $Out = $here } elseif (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location).Path $Out }

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

# ---------------------------------------------------------------- cores (DESIGN.md §3 e §12)
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
# Fração de cada tom que vai para o fundo do quadro. No escuro o accent já contrasta mais com o fundo, então as
# misturas são maiores para a figura manter a mesma hierarquia.
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
    ghostFill = Mix $accent $bg $m.ghostFill          # posição inicial: miolo quase fundo
    ghostLine = Mix $accent $bg $m.ghostLine          # ... e contorno tracejado, mais fraco que o corpo
    equip = $text2                                    # o que se move do equipamento (>= 3:1)
    structure = Mix $text2 $bg $m.structure           # estofado, assento, plataforma, polia
    structureSoft = Mix $text2 $bg $m.structureSoft   # pés do banco, trilho, torre
    floor = Mix $text2 $bg $m.floor
    arrow = HexColor $t.text                          # seta de movimento
  }
}
function Test-Contrast([bool]$quiet) {
  foreach ($look in 'light', 'dark') {
    $ink = New-Ink $look; $bg = $ink.bg; $line = @()
    foreach ($k in 'nearMove', 'farMove', 'equip', 'arrow', 'nearStill', 'farStill', 'structure', 'ghostLine', 'ghostFill') {
      $cr = Contrast $ink[$k] $bg; $line += ('{0} {1} {2:0.00}' -f $k, (Hex $ink[$k]), $cr)
      if (@('nearMove', 'farMove', 'equip', 'arrow') -contains $k -and $cr -lt 3.0) { throw "contraste abaixo de 3:1 ($look, $k): $cr" }
    }
    $sep = Contrast $ink.nearMove $ink.nearStill
    if (-not $quiet) { Write-Host ("contraste {0} contra o fundo {1}: {2}; forte x suave {3:0.00}" -f $look, (Hex $bg), ($line -join ' · '), $sep) }
  }
}

# ---------------------------------------------------------------- manequim (unidade = estatura H; GuideRig no Swift)
# Drillis e Contini (1966), em Winter, fig. 4.1: braço 0,186 H; antebraço 0,146 H; mão 0,108 H; coxa 0,245 H;
# perna 0,246 H. Tronco (quadril-ombro) 0,288 H e pescoço-cabeça 0,122 H.
$Rig = @{ trunk = 0.288; neck = 0.122; thigh = 0.245; shin = 0.246; foot = 0.125; upperArm = 0.186; forearm = 0.146; hand = 0.108 }
$GripAt = 0.40                          # pegada no meio da palma: 40% da mão depois do punho
$FistAt = 0.55                          # a mão fechada vai do punho até 55% do comprimento da mão
$Rad = @{ hip = 0.062; chest = 0.067; neck = 0.024; head = 0.064; thighTop = 0.055; knee = 0.038; kneeLow = 0.034; ankle = 0.024
          heel = 0.019; toe = 0.013; shoulder = 0.034; elbow = 0.029; elbowLow = 0.027; wrist = 0.021; hand = 0.025; plate = 0.074 }
$FarShift = [V2]::new(-0.016, 0.013)    # câmera levemente acima e à frente: o lado de lá aparece um pouco atrás e acima
$GapW = 0.011                           # contorno na cor do fundo que separa segmentos sobrepostos

# ---------------------------------------------------------------- vocabulário do formato (§2.5; nomes sensíveis a caixa)
$PoseKeys = @('trunk', 'neck', 'thigh', 'shin', 'foot', 'upperArm', 'forearm', 'thighFar', 'shinFar', 'footFar', 'upperArmFar', 'forearmFar')
$NearPoseKeys = @('trunk', 'neck', 'thigh', 'shin', 'foot', 'upperArm', 'forearm')
$SidePoints = @('hip', 'shoulder', 'head', 'knee', 'ankle', 'toe', 'heel', 'elbow', 'wrist', 'hand', 'fist',
                'kneeFar', 'ankleFar', 'toeFar', 'heelFar', 'elbowFar', 'wristFar', 'handFar', 'fistFar')
$FrontPoints = @('hip', 'neckBase', 'head', 'shoulder', 'shoulderFar', 'hipJ', 'hipJFar', 'elbow', 'elbowFar', 'wrist', 'wristFar',
                 'hand', 'handFar', 'fist', 'fistFar', 'knee', 'kneeFar', 'ankle', 'ankleFar', 'toe', 'toeFar')
$AllPoints = @('hip', 'shoulder', 'head', 'knee', 'ankle', 'toe', 'heel', 'elbow', 'wrist', 'hand', 'fist',
               'kneeFar', 'ankleFar', 'toeFar', 'heelFar', 'elbowFar', 'wristFar', 'handFar', 'fistFar', 'neckBase', 'shoulderFar', 'hipJ', 'hipJFar')
$ArmPoints = @('elbow', 'wrist', 'hand', 'fist', 'elbowFar', 'wristFar', 'handFar', 'fistFar')
$Segments = @('trunk', 'head', 'thigh', 'shin', 'foot', 'upperArm', 'forearm', 'thighFar', 'shinFar', 'footFar', 'upperArmFar', 'forearmFar')
$AttachSegments = @('thigh', 'shin', 'foot', 'upperArm', 'forearm', 'thighFar', 'shinFar', 'footFar', 'upperArmFar', 'forearmFar')
$ArmSegments = @('upperArm', 'forearm', 'upperArmFar', 'forearmFar')
$SceneKinds = @('bench', 'seat', 'rail', 'tower', 'footPlate', 'pulley', 'block', 'pad', 'post', 'wheel', 'steps')
$SceneParams = @{
  bench = @('x', 'top', 'length'); seat = @('x', 'top', 'length'); rail = @('x1', 'x2'); tower = @('x', 'width', 'height')
  footPlate = @('at', 'length', 'angle'); pulley = @('at'); block = @('x', 'y', 'width', 'height'); pad = @('at', 'length', 'angle')
  post = @('from', 'to'); wheel = @('at', 'radius'); steps = @('x', 'count', 'rise', 'run')
}
$SceneOptionalParams = @{ pad = @('thick'); post = @('thick') }
$SceneRefKinds = @('pulley', 'wheel', 'pad', 'footPlate', 'post')   # itens com ponto de referência para cable.from e band.from
$PositiveParams = @('length', 'width', 'height', 'radius', 'rise', 'run', 'thick')
$PropKinds = @('barbell', 'dumbbell', 'kettlebell', 'ball', 'vHandle', 'bar', 'rope', 'plate', 'roller', 'jumpRope', 'cable', 'band')
$LineKinds = @('cable', 'band')
$ReachAttach = @('back', 'chest', 'hip')
$GuideKeys = @('slug', 'view', 'motion', 'anchor', 'timing', 'scene', 'props', 'arms', 'frames', 'cue', 'moving', 'works', 'a11y', 'steps', 'mistakes')
$FrameKeys = @('label', 'caption', 'pose', 'grip', 'armDepth', 'legDepth', 'elbow', 'root')
$ArmsKeys = @('reach', 'depth', 'elbow', 'forearm', 'farArm')
$CueKeys = @('track', 'span', 'offset', 'side', 'gap')
$TimingKeys = @('toEnd', 'toStart', 'hold', 'easing')

# ---------------------------------------------------------------- interpolação (normativa: GuideKinematics)
function LerpAngle([double]$a, [double]$b, [double]$u) { $d = (($b - $a + 540.0) % 360.0) - 180.0; $a + $d * $u }
function Ease([double]$u) { 0.5 - 0.5 * [Math]::Cos([Math]::PI * [Math]::Max(0.0, [Math]::Min(1.0, $u))) }
function Lerp([double]$a, [double]$b, [double]$u) { $a + ($b - $a) * $u }
function NumOr($v, [double]$d) { if ($null -eq $v) { $d } else { [double]$v } }
function Get-Depth($a, $b, $def, [double]$u) {
  if ($null -eq $a) { $a = $def }
  if ($null -eq $b) { $b = $def }
  ,@((Lerp $a[0] $b[0] $u), (Lerp $a[1] $b[1] $u))
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

# Vista frontal: o lado "de cá" é o direito da tela (0 = para fora); o outro lado é espelhado (180 - a).
function MirrorAng([double]$a, [double]$k) { if ($k -gt 0) { $a } else { 180.0 - $a } }

# Par de quadros e fração suavizada para t em 0 .. n-1 (fora da faixa é limitado). Um quadro só: u = 0.
function Get-Pair($Gd, [double]$t) {
  $n = $Gd.frames.Count
  if ($n -lt 1) { return $null }
  if ($n -eq 1) { return @{ A = $Gd.frames[0]; B = $Gd.frames[0]; u = 0.0 } }
  $tt = [Math]::Max(0.0, [Math]::Min([double]($n - 1), $t))
  $i = [Math]::Max(0, [Math]::Min([int][Math]::Floor($tt), $n - 2))
  @{ A = $Gd.frames[$i]; B = $Gd.frames[$i + 1]; u = (Ease ($tt - $i)) }
}
function Get-Angles($pair) {
  $ang = @{}
  foreach ($k in $PoseKeys) {
    $va = $pair.A.pose[$k]; $vb = $pair.B.pose[$k]
    if ($null -ne $va -and $null -ne $vb) { $ang[$k] = LerpAngle $va $vb $pair.u }
    elseif ($null -ne $va) { $ang[$k] = [double]$va }
    elseif ($null -ne $vb) { $ang[$k] = [double]$vb }
  }
  foreach ($k in $NearPoseKeys) { if (-not $ang.ContainsKey($k)) { $ang[$k] = 0.0 } }
  foreach ($k in 'thigh', 'shin', 'foot', 'upperArm', 'forearm') { if (-not $ang.ContainsKey($k + 'Far')) { $ang[$k + 'Far'] = $ang[$k] } }
  $ang
}
function Move-ToAnchor($Gd, $P) {
  if ($Gd.anchorJoint -ceq 'none' -or $null -eq $Gd.anchorAt) { return }
  $cur = $P[$Gd.anchorJoint]; if ($null -eq $cur) { return }
  $off = $Gd.anchorAt.Minus($cur)
  foreach ($key in @($P.Keys)) { $P[$key] = $P[$key].Plus($off) }
}
# Pontas de um segmento (§2.5): nomes dos dois pontos do esqueleto, da vista lateral ou da frontal.
function Get-SegEndNames([string]$seg, [bool]$front) {
  $far = $seg.EndsWith('Far'); $base = $seg; $s = ''
  if ($far) { $base = $seg.Substring(0, $seg.Length - 3); $s = 'Far' }
  switch -CaseSensitive ($base) {
    'trunk'    { if ($front) { return ,@('hip', 'neckBase') } else { return ,@('hip', 'shoulder') } }
    'head'     { if ($front) { return ,@('neckBase', 'head') } else { return ,@('shoulder', 'head') } }
    'thigh'    { if ($front) { return ,@(('hipJ' + $s), ('knee' + $s)) } else { return ,@('hip', ('knee' + $s)) } }
    'shin'     { return ,@(('knee' + $s), ('ankle' + $s)) }
    'foot'     { return ,@(('ankle' + $s), ('toe' + $s)) }
    'upperArm' { if ($front) { return ,@(('shoulder' + $s), ('elbow' + $s)) } else { return ,@('shoulder', ('elbow' + $s)) } }
    'forearm'  { return ,@(('elbow' + $s), ('wrist' + $s)) }
  }
  $null
}
function Test-ArmAttach([string]$a) { ($ArmPoints -ccontains $a) -or ($ArmSegments -ccontains $a) }
# Ponto de um acessório: nas costas ou no peito (referencial do tronco a partir do topo do tronco), num ponto do
# esqueleto (+ offset no mundo) ou ao longo de um segmento (proximal + (distal - proximal) x along + n x side).
function Get-AttachPoint($P, $ang, $pr, [V2]$off, [bool]$front) {
  $a = $pr.attach
  if ($a -ceq 'back' -or $a -ceq 'chest') {
    $top = if ($front) { $P['neckBase'] } else { $P['shoulder'] }
    if ($null -eq $top) { return $null }
    $up = [V2]::Dir($ang.trunk); $fwd = [V2]::Dir($ang.trunk - 90)
    return $top.Plus($fwd.Times($off.X)).Plus($up.Times($off.Y))
  }
  if ($AllPoints -ccontains $a) { $pt0 = $P[$a]; if ($null -eq $pt0) { return $null }; return $pt0.Plus($off) }
  if ($AttachSegments -ccontains $a) {
    $ends = Get-SegEndNames $a $front
    $p0 = $P[$ends[0]]; $p1 = $P[$ends[1]]
    if ($null -eq $p0 -or $null -eq $p1) { return $null }
    $d = $p1.Minus($p0); $nrm = $d.Unit().Perp()
    return $p0.Plus($d.Times((NumOr $pr.along 0.0))).Plus($nrm.Times((NumOr $pr.side 0.0)))
  }
  $null
}
# Acessórios presos ao braço (armPass) ou ao resto do corpo. Na vista frontal, um acessório na mão aparece nas duas.
function Set-Props($Gd, $P, $ang, $props, [bool]$armPass, [bool]$front) {
  foreach ($pr in $Gd.props) {
    if ($LineKinds -ccontains $pr.kind -or $null -eq $pr.attach) { continue }
    if ((Test-ArmAttach $pr.attach) -ne $armPass) { continue }
    $off = if ($null -ne $pr.offset) { $pr.offset } else { [V2]::new(0, 0) }
    if ($front -and $pr.attach -ceq 'hand') {
      if ($null -ne $P['hand']) { $props[$pr.id] = $P['hand'].Plus($off) }
      if ($null -ne $P['handFar']) { $props[$pr.id + 'Far'] = $P['handFar'].Plus([V2]::new(-$off.X, $off.Y)) }
      continue
    }
    $pt = Get-AttachPoint $P $ang $pr $off $front
    if ($null -ne $pt) { $props[$pr.id] = $pt }
  }
}

function Solve-Front($Gd, $ang, [V2]$hip, $legD) {
  $P = @{}; $P['hip'] = $hip
  $up = [V2]::Dir($ang.trunk); $side = [V2]::Dir($ang.trunk - 90)
  $P['neckBase'] = $hip.Plus($up.Times($Rig.trunk))
  $P['head'] = $P['neckBase'].Plus([V2]::Dir($ang.neck).Times($Rig.neck))
  foreach ($sd in @(@('', 1.0), @('Far', -1.0))) {
    $s = $sd[0]; $k = [double]$sd[1]
    $P['shoulder' + $s] = $P['neckBase'].Plus($side.Times(0.118 * $k)).Minus($up.Times(0.012))
    $P['hipJ' + $s] = $hip.Plus($side.Times(0.085 * $k))
    $E = $P['shoulder' + $s].Plus([V2]::Dir((MirrorAng $ang['upperArm' + $s] $k)).Times($Rig.upperArm))
    Set-ForearmPoints $P $s $E ([V2]::Dir((MirrorAng $ang['forearm' + $s] $k))) 1.0
    $P['knee' + $s] = $P['hipJ' + $s].Plus([V2]::Dir((MirrorAng $ang['thigh' + $s] $k)).Times($Rig.thigh * $legD[0]))
    $P['ankle' + $s] = $P['knee' + $s].Plus([V2]::Dir((MirrorAng $ang['shin' + $s] $k)).Times($Rig.shin * $legD[1]))
    $P['toe' + $s] = $P['ankle' + $s].Plus([V2]::new(0.03 * $k, -0.026))
  }
  Move-ToAnchor $Gd $P
  $props = @{}
  Set-Props $Gd $P $ang $props $false $true
  Set-Props $Gd $P $ang $props $true $true
  @{ P = $P; props = $props; ang = $ang; front = $true; ua = $Rig.upperArm; reach = ($Rig.forearm + $GripAt * $Rig.hand); target = $null }
}

# Resolve a pose num instante t (0 .. n-1) e devolve pontos do corpo e dos acessórios em coordenadas do mundo.
function Solve-Guide($Gd, [double]$t) {
  $pair = Get-Pair $Gd $t
  if ($null -eq $pair) { return @{ P = @{}; props = @{}; ang = @{}; front = ($Gd.view -ceq 'front'); ua = 0.0; reach = 0.0; target = $null } }
  $ang = Get-Angles $pair
  $A = $pair.A; $B = $pair.B; $u = $pair.u
  $legD = Get-Depth $A.legDepth $B.legDepth @(1.0, 1.0) $u
  $hip = [V2]::new(0, 0)
  if ($Gd.anchorJoint -ceq 'none') {
    $ra = if ($null -ne $A.root) { $A.root } else { [V2]::new(0, 0) }
    $rb = if ($null -ne $B.root) { $B.root } else { [V2]::new(0, 0) }
    $hip = [V2]::Lerp($ra, $rb, $u)
  }
  if ($Gd.view -ceq 'front') { return Solve-Front $Gd $ang $hip $legD }

  $P = @{}
  $P['hip'] = $hip
  $P['shoulder'] = $hip.Plus([V2]::Dir($ang.trunk).Times($Rig.trunk))
  $P['head'] = $P['shoulder'].Plus([V2]::Dir($ang.neck).Times($Rig.neck))
  foreach ($s in '', 'Far') {
    $P['knee' + $s] = $hip.Plus([V2]::Dir($ang['thigh' + $s]).Times($Rig.thigh * $legD[0]))
    $P['ankle' + $s] = $P['knee' + $s].Plus([V2]::Dir($ang['shin' + $s]).Times($Rig.shin * $legD[1]))
    $P['toe' + $s] = $P['ankle' + $s].Plus([V2]::Dir($ang['foot' + $s]).Times($Rig.foot))
    $P['heel' + $s] = $P['ankle' + $s].Plus(([V2]::new(-0.035, -0.026)).Rotated($ang['foot' + $s]))
  }
  # escorço dos braços: fator de projeção de [braço, antebraço+mão] no plano do desenho
  $arms = $Gd.arms
  $armDef = @(1.0, 1.0); if ($null -ne $arms -and $null -ne $arms.depth) { $armDef = $arms.depth }
  $armD = Get-Depth $A.armDepth $B.armDepth $armDef $u
  $ua = $Rig.upperArm * $armD[0]; $reach = ($Rig.forearm + $GripAt * $Rig.hand) * $armD[1]
  $useIK = ($null -ne $arms) -and ($null -ne $arms.reach)
  if (-not $useIK) {
    # (b) braços por ângulos: cinemática direta antes da âncora (a âncora pode estar na mão)
    foreach ($s in '', 'Far') {
      $E = $P['shoulder'].Plus([V2]::Dir($ang['upperArm' + $s]).Times($ua))
      Set-ForearmPoints $P $s $E ([V2]::Dir($ang['forearm' + $s])) $armD[1]
    }
  }
  Move-ToAnchor $Gd $P
  $props = @{}
  Set-Props $Gd $P $ang $props $false $false
  $target = $null
  if ($useIK) {
    if ($arms.reach -ceq 'grip') {
      $ga = if ($null -ne $A.grip) { $A.grip } else { $P['shoulder'] }
      $gb = if ($null -ne $B.grip) { $B.grip } else { $P['shoulder'] }
      $target = [V2]::Lerp($ga, $gb, $u)
    } else { $target = $props[$arms.reach] }
    if ($null -eq $target) { $target = $P['shoulder'] }
    $farPose = ($arms.farArm -ceq 'pose')
    if ($null -ne $arms.forearm) {
      # antebraço com ângulo travado (supino: vertical sob a barra); o cotovelo fica sob a pegada
      $dir = [V2]::Dir([double]$arms.forearm); $E = $target.Minus($dir.Times($reach))
      Set-ForearmPoints $P '' $E $dir $armD[1]
      if (-not $farPose) { Set-ForearmPoints $P 'Far' $E $dir $armD[1] }
    } else {
      $hint = LerpAngle (NumOr $A.elbow (NumOr $arms.elbow -90)) (NumOr $B.elbow (NumOr $arms.elbow -90)) $u
      $ik = Solve-TwoBone $P['shoulder'] $target $ua $reach $hint
      $dir = $ik.end.Minus($ik.elbow).Unit()
      Set-ForearmPoints $P '' $ik.elbow $dir $armD[1]
      if (-not $farPose) { Set-ForearmPoints $P 'Far' $ik.elbow $dir $armD[1] }
    }
    if ($farPose) {
      # (d) o braço de lá segue os ângulos do quadro, a partir do ombro, com o mesmo escorço
      $E = $P['shoulder'].Plus([V2]::Dir($ang.upperArmFar).Times($ua))
      Set-ForearmPoints $P 'Far' $E ([V2]::Dir($ang.forearmFar)) $armD[1]
    }
  }
  Set-Props $Gd $P $ang $props $true $false
  @{ P = $P; props = $props; ang = $ang; front = $false; ua = $ua; reach = $reach; target = $target }
}

# ---------------------------------------------------------------- o que se move (E9, calculado dos dados)
function SegAng([V2]$p, [V2]$q) { $d = $q.Minus($p); [Math]::Atan2($d.Y, $d.X) * 180.0 / [Math]::PI }
function AngDiff([double]$a, [double]$b) { $d = ($b - $a) % 360.0; if ($d -gt 180) { $d -= 360 } elseif ($d -lt -180) { $d += 360 }; [Math]::Abs($d) }
function Norm180([double]$x) { $r = $x % 360.0; if ($r -le -180.0) { $r += 360.0 } elseif ($r -gt 180.0) { $r -= 360.0 }; $r }
function Get-Segs($sol) {
  $a = @{}
  foreach ($seg in $Segments) {
    $names = Get-SegEndNames $seg ([bool]$sol.front)
    $p0 = $sol.P[$names[0]]; $p1 = $sol.P[$names[1]]
    if ($null -ne $p0 -and $null -ne $p1) { $a[$seg] = @($p0, $p1) }
  }
  $a
}
$Parent = @{ trunk = $null; head = 'trunk'; thigh = 'trunk'; shin = 'thigh'; foot = 'shin'; upperArm = 'trunk'; forearm = 'upperArm' }
$Rigid = @{ head = $true; shin = $true; foot = $true; forearm = $true }   # podem só acompanhar o segmento-pai
$MoveMin = 12.0; $ShiftMin = 0.04
# Um segmento "se move" quando gira >= 12° ou o meio dele anda >= 0,04 H entre o primeiro e o último quadro, E a
# articulação com o pai muda >= 12° (ou ele só acompanha, rígido, um pai que se move no mesmo membro).
function Get-Moving($Gd, [bool]$verbose) {
  if ($null -ne $Gd.moving) {
    $mv = @{}; foreach ($k in $Gd.moving) { $mv[$k] = $true; if (-not $k.EndsWith('Far') -and $k -cne 'trunk' -and $k -cne 'head') { $mv[$k + 'Far'] = $true } }
    if ($verbose) { Write-Host ("  {0}: 'moving' do JSON sobrepõe o cálculo" -f $Gd.slug) }
    return $mv
  }
  $last = [Math]::Max(0, $Gd.frames.Count - 1)
  $s0 = Get-Segs (Solve-Guide $Gd 0.0); $s1 = Get-Segs (Solve-Guide $Gd ([double]$last))
  $mv = @{}; $report = @()
  foreach ($s in '', 'Far') {
    foreach ($seg in 'trunk', 'head', 'thigh', 'shin', 'foot', 'upperArm', 'forearm') {
      $central = ($seg -eq 'trunk' -or $seg -eq 'head')
      if ($central -and $s -eq 'Far') { continue }
      $key = if ($central) { $seg } else { $seg + $s }
      if (-not $s0.ContainsKey($key) -or -not $s1.ContainsKey($key)) { continue }
      $a0 = SegAng $s0[$key][0] $s0[$key][1]; $a1 = SegAng $s1[$key][0] $s1[$key][1]
      $abs = AngDiff $a0 $a1
      $mid0 = [V2]::Lerp($s0[$key][0], $s0[$key][1], 0.5); $mid1 = [V2]::Lerp($s1[$key][0], $s1[$key][1], 0.5)
      $shift = $mid1.Minus($mid0).Len()
      $par = $Parent[$seg]; $pkey = $null; $joint = $abs
      if ($null -ne $par) {
        $pkey = if ($par -eq 'trunk') { 'trunk' } else { $par + $s }
        $p0 = SegAng $s0[$pkey][0] $s0[$pkey][1]; $p1 = SegAng $s1[$pkey][0] $s1[$pkey][1]
        $joint = AngDiff ($a0 - $p0) ($a1 - $p1)
      }
      $follows = $Rigid.ContainsKey($seg) -and $null -ne $pkey -and $mv.ContainsKey($pkey)
      $m = (($abs -ge $MoveMin) -or ($shift -ge $ShiftMin)) -and (($joint -ge $MoveMin) -or $follows)
      if ($m) { $mv[$key] = $true }
      if ($s -eq '') { $report += ('{0} {1:0}°/{2:0.00}H/{3:0}°{4}' -f $key, $abs, $shift, $joint, $(if ($m) { ' MOVE' } else { '' })) }
    }
  }
  if ($verbose) { Write-Host ("  {0} (giro/deslocamento/articulação): {1}" -f $Gd.slug, ($report -join ' · ')) }
  $mv
}

# ---------------------------------------------------------------- seta de movimento (normativa: GuideMotion.cuePath)
# Trajetória do ponto principal ao longo da ida (80 passos), reamostrada por comprimento de arco em 41 pontos,
# recortada em "span" e deslocada "gap" para o lado indicado e/ou por "offset".
function Get-TrackPoint($Gd, $sol) {
  $tr = $Gd.cue.track
  if ($AllPoints -ccontains $tr) { $p = $sol.P[$tr]; if ($null -ne $p) { return $p } }
  $q = $sol.props[$tr]; if ($null -ne $q) { return $q }
  [V2]::new(0, 0)
}
function Get-CuePath($Gd) {
  $cue = $Gd.cue; if ($null -eq $cue -or $Gd.frames.Count -lt 1) { return $null }
  $last = $Gd.frames.Count - 1; $n = 80
  $raw = New-Object System.Collections.Generic.List[object]
  for ($k = 0; $k -le $n; $k++) { $raw.Add((Get-TrackPoint $Gd (Solve-Guide $Gd ($last * $k / $n)))) }
  $cum = @(0.0); for ($k = 1; $k -le $n; $k++) { $cum += $cum[$k - 1] + $raw[$k].Minus($raw[$k - 1]).Len() }
  $L = $cum[$n]; $a = 0.0; $b = 1.0; if ($null -ne $cue.span) { $a = [double]$cue.span[0]; $b = [double]$cue.span[1] }
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
    if ($null -ne $cue.side) {
      $tan = $pts[[Math]::Min($m, $k + 2)].Minus($pts[[Math]::Max(0, $k - 2)]).Unit()
      $nrm = [V2]::new($tan.Y, -$tan.X); if ($cue.side -ceq 'left') { $nrm = $nrm.Times(-1) }
      $p = $p.Plus($nrm.Times((NumOr $cue.gap 0.0)))
    }
    if ($null -ne $cue.offset) { $p = $p.Plus($cue.offset) }
    $outPts.Add($p)
  }
  ,$outPts
}

# ---------------------------------------------------------------- validação (§2.5; espelha ExerciseGuideValidator)
$script:Errors = New-Object System.Collections.Generic.List[object]
function Add-Err([string]$slug, [string]$rule, [string]$msg) { $script:Errors.Add(@{ slug = $slug; rule = $rule; msg = $msg }) }
function IsNum($v) { ($v -is [int]) -or ($v -is [long]) -or ($v -is [double]) -or ($v -is [decimal]) }
function IsStr($v) { $v -is [string] }
function IsArr($v) { $v -is [System.Array] }
function IsObj($v) { $v -is [System.Management.Automation.PSCustomObject] }
function IsPt($v) { (IsArr $v) -and $v.Count -eq 2 -and (IsNum $v[0]) -and (IsNum $v[1]) }
function KeysOf($o) { @($o.PSObject.Properties | ForEach-Object { $_.Name }) }
function Has($o, [string]$k) { (IsObj $o) -and ((KeysOf $o) -ccontains $k) }
function TextLen([string]$s) { if ([string]::IsNullOrWhiteSpace($s)) { 0 } else { $s.Length } }
function Test-Keys($o, [string[]]$allowed, [string]$where, [string]$slug) {
  foreach ($k in (KeysOf $o)) { if ($allowed -cnotcontains $k) { Add-Err $slug 'format' ("chave desconhecida em {0}: '{1}'" -f $where, $k) } }
}
function Test-Depth($v, [string]$where, [string]$slug) {
  $vals = @()
  if (IsNum $v) { $vals = @([double]$v) }
  elseif ((IsArr $v) -and $v.Count -eq 2 -and (IsNum $v[0]) -and (IsNum $v[1])) { $vals = @([double]$v[0], [double]$v[1]) }
  else { Add-Err $slug 'format' "$where deve ser um número ou [a, b]"; return }
  foreach ($x in $vals) { if ($x -lt 0.3 -or $x -gt 1.0) { Add-Err $slug 'format' ("{0} fora de 0,3 a 1: {1}" -f $where, $x) } }
}
function Test-Num($o, [string]$k, [string]$where, [string]$slug, [bool]$required) {
  if (-not (Has $o $k)) { if ($required) { Add-Err $slug 'format' "$where sem '$k'" }; return $false }
  if (-not (IsNum $o.$k)) { Add-Err $slug 'format' "$where.$k deve ser um número"; return $false }
  $true
}
function Test-Pt($o, [string]$k, [string]$where, [string]$slug, [bool]$required) {
  if (-not (Has $o $k)) { if ($required) { Add-Err $slug 'format' "$where sem '$k'" }; return $false }
  if (-not (IsPt $o.$k)) { Add-Err $slug 'format' "$where.$k deve ser [x, y]"; return $false }
  $true
}

# Formato de uma guia (tipos, chaves, enumerações, referências) e E1, E2, E7, E9. Devolve a guia normalizada, ou
# $null se houver erro de formato (as regras de cinemática só rodam sobre guias com formato válido).
function Test-Guide($raw, [int]$index) {
  $slug = if ((IsStr $raw.slug) -and $raw.slug -ne '') { [string]$raw.slug } else { "(guia $index)" }
  $before = $script:Errors.Count
  if (-not (IsObj $raw)) { Add-Err $slug 'format' 'a guia deve ser um objeto'; return $null }
  Test-Keys $raw $GuideKeys 'guia' $slug
  foreach ($k in 'slug', 'view', 'anchor', 'scene', 'props', 'frames', 'a11y', 'steps', 'mistakes') {
    if (-not (Has $raw $k)) { Add-Err $slug 'format' "falta a chave obrigatória '$k'" }
  }
  # E1
  if (-not (IsStr $raw.slug) -or $raw.slug -eq '') { Add-Err $slug 'E1' 'slug ausente' }
  else {
    if (-not $script:SeenSlugs.Add([string]$raw.slug)) { Add-Err $slug 'E1' 'slug repetido: no máximo uma guia por slug' }
    if ($useCatalog -and -not $script:CatalogSlugs.Contains([string]$raw.slug)) { Add-Err $slug 'E1' 'slug fora do catálogo do seed' }
  }
  $view = 'side'
  if (Has $raw 'view') { if (@('side', 'front') -ccontains $raw.view) { $view = [string]$raw.view } else { Add-Err $slug 'format' "view deve ser 'side' ou 'front'" } }
  $front = ($view -ceq 'front')
  $pointNames = if ($front) { $FrontPoints } else { $SidePoints }
  $motion = 'loop'
  if (Has $raw 'motion') { if (@('loop', 'static') -ccontains $raw.motion) { $motion = [string]$raw.motion } else { Add-Err $slug 'format' "motion deve ser 'loop' ou 'static'" } }
  $frames = @()
  if (IsArr $raw.frames) { $frames = @($raw.frames) } elseif (Has $raw 'frames') { Add-Err $slug 'format' 'frames deve ser uma lista' }
  $scene = @()
  if (IsArr $raw.scene) { $scene = @($raw.scene) } elseif (Has $raw 'scene') { Add-Err $slug 'format' 'scene deve ser uma lista' }
  $props = @()
  if (IsArr $raw.props) { $props = @($raw.props) } elseif (Has $raw 'props') { Add-Err $slug 'format' 'props deve ser uma lista' }

  # ids únicos na guia (cena e acessórios juntos)
  $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  $sceneById = @{}; $propById = @{}
  foreach ($s in $scene) {
    if (-not (IsObj $s)) { Add-Err $slug 'format' 'item de scene deve ser um objeto'; continue }
    if (Has $s 'id') {
      if (-not (IsStr $s.id) -or $s.id -eq '') { Add-Err $slug 'format' 'scene.id deve ser um texto' }
      elseif (-not $ids.Add([string]$s.id)) { Add-Err $slug 'format' "id repetido: $($s.id)" }
      else { $sceneById[[string]$s.id] = $s }
    }
  }
  foreach ($pr in $props) {
    if (-not (IsObj $pr)) { Add-Err $slug 'format' 'item de props deve ser um objeto'; continue }
    if (-not (IsStr $pr.id) -or $pr.id -eq '') { Add-Err $slug 'format' 'acessório sem id'; continue }
    if (-not $ids.Add([string]$pr.id)) { Add-Err $slug 'format' "id repetido: $($pr.id)" }
    elseif ($AllPoints -ccontains $pr.id) { Add-Err $slug 'format' "id de acessório não pode ser nome de ponto do esqueleto: $($pr.id)" }
    else { $propById[[string]$pr.id] = $pr }
  }

  # cena
  foreach ($s in $scene) {
    if (-not (IsObj $s)) { continue }
    $kind = $s.kind
    if (-not ($SceneKinds -ccontains $kind)) { Add-Err $slug 'format' "scene.kind desconhecido: $kind"; continue }
    $where = "scene $kind"
    $allowed = @('kind', 'id', 'layer', 'tone') + $SceneParams[$kind]
    if ($SceneOptionalParams.ContainsKey($kind)) { $allowed += $SceneOptionalParams[$kind] }
    Test-Keys $s $allowed $where $slug
    if ((Has $s 'layer') -and -not (@('back', 'mid', 'front') -ccontains $s.layer)) { Add-Err $slug 'format' "$where.layer deve ser back, mid ou front" }
    if ((Has $s 'tone') -and -not (@('structure', 'soft') -ccontains $s.tone)) { Add-Err $slug 'format' "$where.tone deve ser structure ou soft" }
    if ($kind -ceq 'pulley' -and -not (Has $s 'id')) { Add-Err $slug 'format' 'pulley precisa de id' }
    $params = @($SceneParams[$kind]); if ($SceneOptionalParams.ContainsKey($kind)) { $params += $SceneOptionalParams[$kind] }
    foreach ($p in $params) {
      $required = @($SceneParams[$kind]) -ccontains $p
      if (@('at', 'from', 'to') -ccontains $p) { [void](Test-Pt $s $p $where $slug $required); continue }
      if (-not (Test-Num $s $p $where $slug $required)) { continue }
      if ($PositiveParams -ccontains $p -and [double]$s.$p -le 0) { Add-Err $slug 'format' "$where.$p deve ser maior que 0" }
      if ($p -ceq 'count' -and ([double]$s.count -lt 1 -or [double]$s.count -ne [Math]::Floor([double]$s.count))) { Add-Err $slug 'format' "$where.count deve ser um inteiro >= 1" }
    }
  }

  # acessórios
  foreach ($pr in $props) {
    if (-not (IsObj $pr) -or -not (IsStr $pr.id)) { continue }
    $kind = $pr.kind
    $where = "props $($pr.id)"
    if (-not ($PropKinds -ccontains $kind)) { Add-Err $slug 'format' "$where.kind desconhecido: $kind"; continue }
    if ($LineKinds -ccontains $kind) {
      Test-Keys $pr @('id', 'kind', 'from', 'to') $where $slug
      $src = $null; if (IsStr $pr.from) { $src = $sceneById[[string]$pr.from] }
      if ($null -eq $src -or -not ($SceneRefKinds -ccontains $src.kind)) { Add-Err $slug 'format' "$where.from deve ser o id de um item da cena com ponto de referência (pulley, wheel, pad, footPlate ou post)" }
      $okTo = $false
      if (IsStr $pr.to) {
        if ($pointNames -ccontains $pr.to) { $okTo = $true }
        elseif ($propById.ContainsKey([string]$pr.to) -and -not ($LineKinds -ccontains $propById[[string]$pr.to].kind)) { $okTo = $true }
      }
      if (-not $okTo) { Add-Err $slug 'format' "$where.to deve ser um acessório ou um ponto do esqueleto desta vista" }
      continue
    }
    $allowed = @('id', 'kind', 'attach', 'offset', 'along', 'side')
    if ($kind -ceq 'plate') { $allowed += @('length', 'angle') }
    if ($kind -ceq 'roller') { $allowed += @('radius') }
    Test-Keys $pr $allowed $where $slug
    $attach = $pr.attach
    $isSeg = $false
    if (-not (IsStr $attach)) { Add-Err $slug 'format' "$where sem attach" }
    elseif ($attach -ceq 'back' -or $attach -ceq 'chest' -or $pointNames -ccontains $attach) { }
    elseif ($AttachSegments -ccontains $attach) { $isSeg = $true }
    else { Add-Err $slug 'format' "$where.attach desconhecido: $attach" }
    if ((Has $pr 'offset') -and -not (IsPt $pr.offset)) { Add-Err $slug 'format' "$where.offset deve ser [x, y]" }
    if ($isSeg) {
      if ((Test-Num $pr 'along' $where $slug $true) -and ([double]$pr.along -lt 0 -or [double]$pr.along -gt 1)) { Add-Err $slug 'format' "$where.along deve ficar entre 0 e 1" }
      [void](Test-Num $pr 'side' $where $slug $false)
    } elseif ((Has $pr 'along') -or (Has $pr 'side')) { Add-Err $slug 'format' "$where.along e .side só valem com attach num segmento" }
    if ($kind -ceq 'plate') {
      if ((Test-Num $pr 'length' $where $slug $true) -and [double]$pr.length -le 0) { Add-Err $slug 'format' "$where.length deve ser maior que 0" }
      [void](Test-Num $pr 'angle' $where $slug $true)
    }
    if ($kind -ceq 'roller' -and (Test-Num $pr 'radius' $where $slug $false) -and [double]$pr.radius -le 0) { Add-Err $slug 'format' "$where.radius deve ser maior que 0" }
  }

  # braços
  $useIK = $false; $farPose = $false; $armsRaw = $null
  if (Has $raw 'arms') {
    $armsRaw = $raw.arms
    if (-not (IsObj $armsRaw)) { Add-Err $slug 'format' 'arms deve ser um objeto'; $armsRaw = $null }
    else {
      Test-Keys $armsRaw $ArmsKeys 'arms' $slug
      if (Has $armsRaw 'reach') {
        if (-not (IsStr $armsRaw.reach)) { Add-Err $slug 'format' 'arms.reach deve ser um texto' }
        else {
          $useIK = $true
          if ($front) { Add-Err $slug 'format' 'na vista frontal os braços são por ângulos (sem arms.reach)' }
          if ($armsRaw.reach -cne 'grip') {
            $target = $propById[[string]$armsRaw.reach]
            if ($null -eq $target -or $LineKinds -ccontains $target.kind) { Add-Err $slug 'format' "arms.reach aponta para acessório inexistente: $($armsRaw.reach)" }
            elseif (-not ($ReachAttach -ccontains $target.attach)) { Add-Err $slug 'format' 'arms.reach exige um acessório em back, chest ou hip' }
          }
        }
      }
      if (Has $armsRaw 'depth') { Test-Depth $armsRaw.depth 'arms.depth' $slug }
      [void](Test-Num $armsRaw 'elbow' 'arms' $slug $false)
      if ((Test-Num $armsRaw 'forearm' 'arms' $slug $false) -and -not $useIK) { Add-Err $slug 'format' 'arms.forearm só vale com arms.reach' }
      if (Has $armsRaw 'farArm') {
        if (-not (@('mirror', 'pose') -ccontains $armsRaw.farArm)) { Add-Err $slug 'format' "arms.farArm deve ser 'mirror' ou 'pose'" }
        else {
          if ($front) { Add-Err $slug 'format' 'arms.farArm só vale na vista lateral' }
          if ($armsRaw.farArm -ceq 'pose') { $farPose = $true; if (-not $useIK) { Add-Err $slug 'format' "arms.farArm 'pose' só vale com arms.reach" } }
        }
      }
    }
  }
  $byAngles = -not $useIK

  # âncora
  $anchorJoint = 'none'
  if (Has $raw 'anchor') {
    $an = $raw.anchor
    if (-not (IsObj $an)) { Add-Err $slug 'format' 'anchor deve ser um objeto' }
    else {
      Test-Keys $an @('joint', 'at') 'anchor' $slug
      if (-not (IsStr $an.joint)) { Add-Err $slug 'format' 'anchor sem joint' }
      elseif ($an.joint -ceq 'none') { if (Has $an 'at') { [void](Test-Pt $an 'at' 'anchor' $slug $false) } }
      else {
        $anchorJoint = [string]$an.joint
        if (-not ($pointNames -ccontains $an.joint)) { Add-Err $slug 'format' "anchor.joint desconhecido nesta vista: $($an.joint)" }
        elseif ($ArmPoints -ccontains $an.joint -and $useIK) { Add-Err $slug 'format' 'âncora na mão ou no braço exige braços por ângulos' }
        [void](Test-Pt $an 'at' 'anchor' $slug $true)
      }
    }
  }

  # ritmo (E7)
  if (Has $raw 'timing') {
    $tm = $raw.timing
    if (-not (IsObj $tm)) { Add-Err $slug 'format' 'timing deve ser um objeto' }
    else {
      Test-Keys $tm $TimingKeys 'timing' $slug
      foreach ($k in 'toEnd', 'toStart') { if ((Test-Num $tm $k 'timing' $slug $true) -and ([double]$tm.$k -lt 0.8 -or [double]$tm.$k -gt 3.0)) { Add-Err $slug 'E7' ("timing.{0} fora de 0,8 a 3,0 s: {1}" -f $k, $tm.$k) } }
      if ((Test-Num $tm 'hold' 'timing' $slug $true) -and ([double]$tm.hold -lt 0.2 -or [double]$tm.hold -gt 1.0)) { Add-Err $slug 'E7' ("timing.hold fora de 0,2 a 1,0 s: {0}" -f $tm.hold) }
      if ($tm.easing -cne 'easeInOut') { Add-Err $slug 'format' "timing.easing deve ser 'easeInOut'" }
    }
  } elseif ($motion -ceq 'loop') { Add-Err $slug 'format' "timing é obrigatório em motion 'loop'" }

  # quadros (E2 e formato das poses)
  $n = $frames.Count
  if ($motion -ceq 'loop' -and ($n -lt 2 -or $n -gt 3)) { Add-Err $slug 'E2' "motion 'loop' precisa de 2 ou 3 quadros (tem $n)" }
  if ($motion -ceq 'static' -and ($n -lt 1 -or $n -gt 3)) { Add-Err $slug 'E2' "motion 'static' precisa de 1 a 3 quadros (tem $n)" }
  $labels = @(switch ($n) { 1 { 'Posição' } 2 { 'Início', 'Fim' } 3 { 'Início', 'Meio', 'Fim' } })
  $required = if ($front) { @('trunk', 'neck', 'thigh', 'shin', 'upperArm', 'forearm') } else { @('trunk', 'neck', 'thigh', 'shin', 'foot') }
  if (-not $front -and $byAngles) { $required += @('upperArm', 'forearm') }
  if ($farPose) { $required += @('upperArmFar', 'forearmFar') }
  $firstKeys = $null
  for ($i = 0; $i -lt $n; $i++) {
    $fr = $frames[$i]; $where = "frames[$i]"
    if (-not (IsObj $fr)) { Add-Err $slug 'format' "$where deve ser um objeto"; continue }
    Test-Keys $fr $FrameKeys $where $slug
    if (-not (IsStr $fr.label)) { Add-Err $slug 'format' "$where sem label" }
    elseif (-not (@('Início', 'Meio', 'Fim', 'Posição') -ccontains $fr.label)) { Add-Err $slug 'format' "$where.label desconhecido: $($fr.label)" }
    elseif ($labels.Count -gt 0 -and $fr.label -cne $labels[$i]) { Add-Err $slug 'E2' ("{0}.label deve ser '{1}'" -f $where, $labels[$i]) }
    if (-not (IsStr $fr.caption)) { Add-Err $slug 'format' "$where sem caption" }
    elseif ((TextLen $fr.caption) -lt 1 -or $fr.caption.Length -gt 28) { Add-Err $slug 'E2' ("{0}.caption precisa ter de 1 a 28 caracteres (tem {1})" -f $where, $fr.caption.Length) }
    if (-not (IsObj $fr.pose)) { Add-Err $slug 'format' "$where sem pose" }
    else {
      $keys = @(KeysOf $fr.pose)
      foreach ($k in $keys) {
        if (-not ($PoseKeys -ccontains $k)) { Add-Err $slug 'format' "chave desconhecida em $where.pose: '$k'" }
        elseif (-not (IsNum $fr.pose.$k)) { Add-Err $slug 'format' "$where.pose.$k deve ser um número" }
      }
      foreach ($k in $required) { if (-not ($keys -ccontains $k)) { Add-Err $slug 'format' "$where.pose sem '$k'" } }
      $sorted = [string[]]@($keys); [Array]::Sort($sorted, [StringComparer]::Ordinal); $sig = $sorted -join ','
      if ($null -eq $firstKeys) { $firstKeys = $sig } elseif ($sig -cne $firstKeys) { Add-Err $slug 'format' "$where.pose tem chaves diferentes do primeiro quadro (todos os quadros têm o mesmo conjunto)" }
    }
    if (Has $fr 'grip') { [void](Test-Pt $fr 'grip' $where $slug $false) }
    elseif ($useIK -and $armsRaw.reach -ceq 'grip') { Add-Err $slug 'format' "$where sem grip (arms.reach = grip)" }
    if (Has $fr 'armDepth') { Test-Depth $fr.armDepth "$where.armDepth" $slug }
    if (Has $fr 'legDepth') { Test-Depth $fr.legDepth "$where.legDepth" $slug }
    [void](Test-Num $fr 'elbow' $where $slug $false)
    if (Has $fr 'root') { [void](Test-Pt $fr 'root' $where $slug $false) }
    elseif ((Has $raw 'anchor') -and $raw.anchor.joint -ceq 'none') { Add-Err $slug 'format' "$where sem root (anchor none)" }
  }

  # seta
  if (Has $raw 'cue') {
    $cue = $raw.cue
    if (-not (IsObj $cue)) { Add-Err $slug 'format' 'cue deve ser um objeto' }
    else {
      Test-Keys $cue $CueKeys 'cue' $slug
      $okTrack = (IsStr $cue.track) -and (($pointNames -ccontains $cue.track) -or ($propById.ContainsKey([string]$cue.track) -and -not ($LineKinds -ccontains $propById[[string]$cue.track].kind)))
      if (-not $okTrack) { Add-Err $slug 'format' 'cue.track deve ser um ponto do esqueleto desta vista ou o id de um acessório' }
      if (Has $cue 'span') {
        $sp = $cue.span
        if (-not (IsPt $sp) -or [double]$sp[0] -lt 0 -or [double]$sp[0] -ge [double]$sp[1] -or [double]$sp[1] -gt 1) { Add-Err $slug 'format' 'cue.span deve ser [a, b] com 0 <= a < b <= 1' }
      }
      $hasOffset = Has $cue 'offset'
      if ($hasOffset -and -not (IsPt $cue.offset)) { Add-Err $slug 'format' 'cue.offset deve ser [x, y]' }
      $hasSide = Has $cue 'side'
      if ($hasSide -and -not (@('left', 'right') -ccontains $cue.side)) { Add-Err $slug 'format' "cue.side deve ser 'left' ou 'right'" }
      if ($hasSide -and -not ((Has $cue 'gap') -and (IsNum $cue.gap) -and [double]$cue.gap -gt 0)) { Add-Err $slug 'format' 'cue.side exige gap maior que 0' }
      if ((Has $cue 'gap') -and -not $hasSide) { Add-Err $slug 'format' 'cue.gap só vale com cue.side' }
      if (-not $hasOffset -and -not $hasSide) { Add-Err $slug 'format' 'cue precisa de offset ou de side com gap (a seta não cobre o corpo)' }
      if ($n -eq 1) { Add-Err $slug 'format' 'com 1 quadro não há caminho para a seta: tire o cue' }
    }
  } elseif ($motion -ceq 'loop') { Add-Err $slug 'format' "cue é obrigatório em motion 'loop'" }

  # E9
  if (Has $raw 'moving') {
    $mvRaw = $raw.moving
    if (-not (IsArr $mvRaw) -or $mvRaw.Count -eq 0) { Add-Err $slug 'E9' 'moving deve ser uma lista não vazia de segmentos' }
    else { foreach ($k in $mvRaw) { if (-not ($Segments -ccontains $k)) { Add-Err $slug 'E9' "moving tem segmento desconhecido: $k" } } }
  } elseif ($motion -ceq 'static' -and $n -eq 1) { Add-Err $slug 'E9' "moving é obrigatório em motion 'static' com 1 quadro" }

  # E2: textos
  $pattern = $null; if ($useCatalog -and (IsStr $raw.slug)) { $pattern = $script:Patterns[[string]$raw.slug] }
  if (Has $raw 'works') {
    if (-not (IsStr $raw.works)) { Add-Err $slug 'format' 'works deve ser um texto' }
    elseif ((TextLen $raw.works) -lt 1 -or $raw.works.Length -gt 60) { Add-Err $slug 'E2' ("works precisa ter de 1 a 60 caracteres (tem {0})" -f $raw.works.Length) }
    elseif ([char]::IsUpper($raw.works.TrimStart()[0])) { Add-Err $slug 'E2' 'works vai no meio da frase: comece com minúscula' }
  } elseif ($pattern -ceq 'cardio' -or $pattern -ceq 'neck') { Add-Err $slug 'E2' "works é obrigatório em exercícios de padrão $pattern" }
  if (-not (IsStr $raw.a11y)) { if (Has $raw 'a11y') { Add-Err $slug 'format' 'a11y deve ser um texto' } }
  elseif ((TextLen $raw.a11y) -lt 1 -or $raw.a11y.Length -gt 240) { Add-Err $slug 'E2' ("a11y precisa ter de 1 a 240 caracteres (tem {0})" -f $raw.a11y.Length) }
  if (Has $raw 'steps') {
    if (-not (IsArr $raw.steps) -or $raw.steps.Count -ne 3) { Add-Err $slug 'E2' 'steps precisa de exatamente 3 passos' }
    else { foreach ($x in $raw.steps) { if (-not (IsStr $x) -or (TextLen $x) -lt 1 -or $x.Length -gt 120) { Add-Err $slug 'E2' "passo precisa ter de 1 a 120 caracteres: $x" } } }
  }
  if (Has $raw 'mistakes') {
    if (-not (IsArr $raw.mistakes) -or $raw.mistakes.Count -ne 2) { Add-Err $slug 'E2' 'mistakes precisa de exatamente 2 erros' }
    else {
      foreach ($x in $raw.mistakes) {
        if (-not (IsStr $x) -or (TextLen $x) -lt 1 -or $x.Length -gt 120) { Add-Err $slug 'E2' "erro comum precisa ter de 1 a 120 caracteres: $x" }
        elseif (-not $x.Contains(': ')) { Add-Err $slug 'E2' "erro comum no formato 'o erro: o que fazer': $x" }
      }
    }
  }

  for ($i = $before; $i -lt $script:Errors.Count; $i++) { if ($script:Errors[$i].rule -ceq 'format') { return $null } }
  if ($n -lt 1) { return $null }
  Convert-Guide $raw
}

# Guia normalizada para o cálculo (só chamada sobre guias com formato válido).
function PtOrNull($v) { if ($null -eq $v) { return $null }; [V2]::new([double]$v[0], [double]$v[1]) }
function PairOrNull($v) {
  if ($null -eq $v) { return $null }
  if ($v -is [System.Array]) { return ,@([double]$v[0], [double]$v[1]) }
  ,@([double]$v, [double]$v)
}
function NumOrNull($v) { if ($null -eq $v) { return $null }; [double]$v }
function StrOrNull($v) { if ($null -eq $v) { return $null }; [string]$v }
function Convert-Guide($raw) {
  $Gd = @{ slug = [string]$raw.slug; view = [string]$raw.view; raw = $raw }
  $Gd.motion = if ($null -eq $raw.motion) { 'loop' } else { [string]$raw.motion }
  $Gd.anchorJoint = [string]$raw.anchor.joint
  $Gd.anchorAt = if ($Gd.anchorJoint -ceq 'none') { $null } else { PtOrNull $raw.anchor.at }
  $Gd.timing = $null
  if ($null -ne $raw.timing) { $Gd.timing = @{ toEnd = [double]$raw.timing.toEnd; toStart = [double]$raw.timing.toStart; hold = [double]$raw.timing.hold } }
  $Gd.scene = New-Object System.Collections.Generic.List[object]
  foreach ($s in @($raw.scene)) {
    $h = @{ kind = [string]$s.kind; id = (StrOrNull $s.id); layer = (StrOrNull $s.layer); tone = (StrOrNull $s.tone) }
    foreach ($k in 'x', 'x1', 'x2', 'y', 'top', 'length', 'width', 'height', 'angle', 'thick', 'radius', 'count', 'rise', 'run') { $h[$k] = NumOrNull $s.$k }
    foreach ($k in 'at', 'from', 'to') { $h[$k] = PtOrNull $s.$k }
    $Gd.scene.Add($h)
  }
  $Gd.props = New-Object System.Collections.Generic.List[object]
  foreach ($pr in @($raw.props)) {
    $Gd.props.Add(@{ id = [string]$pr.id; kind = [string]$pr.kind; attach = (StrOrNull $pr.attach); offset = (PtOrNull $pr.offset)
                    along = (NumOrNull $pr.along); side = (NumOrNull $pr.side); length = (NumOrNull $pr.length); angle = (NumOrNull $pr.angle)
                    radius = (NumOrNull $pr.radius); from = (StrOrNull $pr.from); to = (StrOrNull $pr.to) })
  }
  $Gd.arms = $null
  if ($null -ne $raw.arms) {
    $Gd.arms = @{ reach = (StrOrNull $raw.arms.reach); depth = (PairOrNull $raw.arms.depth); elbow = (NumOrNull $raw.arms.elbow)
                 forearm = (NumOrNull $raw.arms.forearm); farArm = (StrOrNull $raw.arms.farArm) }
  }
  $Gd.frames = New-Object System.Collections.Generic.List[object]
  foreach ($f in @($raw.frames)) {
    $pose = @{}
    foreach ($pp in $f.pose.PSObject.Properties) { $pose[$pp.Name] = [double]$pp.Value }
    $Gd.frames.Add(@{ label = [string]$f.label; caption = [string]$f.caption; pose = $pose; grip = (PtOrNull $f.grip)
                     armDepth = (PairOrNull $f.armDepth); legDepth = (PairOrNull $f.legDepth); elbow = (NumOrNull $f.elbow); root = (PtOrNull $f.root) })
  }
  $Gd.cue = $null
  if ($null -ne $raw.cue) {
    $span = $null; if ($null -ne $raw.cue.span) { $span = @([double]$raw.cue.span[0], [double]$raw.cue.span[1]) }
    $Gd.cue = @{ track = [string]$raw.cue.track; span = $span; offset = (PtOrNull $raw.cue.offset); side = (StrOrNull $raw.cue.side); gap = (NumOrNull $raw.cue.gap) }
  }
  $Gd.moving = $null; if ($null -ne $raw.moving) { $Gd.moving = @($raw.moving | ForEach-Object { [string]$_ }) }
  $Gd.works = StrOrNull $raw.works
  $Gd.a11y = [string]$raw.a11y
  $Gd.steps = @($raw.steps); $Gd.mistakes = @($raw.mistakes)
  $Gd
}

function IsFinitePt($p) { $null -ne $p -and -not ([double]::IsNaN($p.X) -or [double]::IsInfinity($p.X) -or [double]::IsNaN($p.Y) -or [double]::IsInfinity($p.Y)) }
# E4, E5, E6 e E10 em t = 0, 0,05, ..., n - 1 (espelha ExerciseGuideValidator+Kinematics). Cada regra aparece no
# máximo uma vez por guia e por articulação, no primeiro t que falha.
function Test-Kinematics($Gd) {
  $slug = $Gd.slug; $last = $Gd.frames.Count - 1; $seen = @{}
  $front = ($Gd.view -ceq 'front')
  $useIK = ($null -ne $Gd.arms) -and ($null -ne $Gd.arms.reach) -and -not $front
  $eps = 1e-6
  for ($k = 0; $k -le 20 * $last; $k++) {
    $t = $k / 20.0
    $sol = Solve-Guide $Gd $t
    $P = $sol.P
    foreach ($pt in @(@($P.Values) + @($sol.props.Values))) {
      # com uma coordenada não finita, as outras contas não dizem nada: para aqui
      if (-not (IsFinitePt $pt)) { Add-Err $slug 'E4' ("coordenada não finita em t = {0:0.00}" -f $t); return }
    }
    if ($Gd.anchorJoint -cne 'none' -and -not $seen.ContainsKey('E5')) {
      $ap = $P[$Gd.anchorJoint]
      if ($null -eq $ap -or $ap.Minus($Gd.anchorAt).Len() -gt 0.001) { Add-Err $slug 'E5' ("a âncora {0} sai do lugar em t = {1:0.00}" -f $Gd.anchorJoint, $t); $seen['E5'] = $true }
    }
    if ($useIK -and -not $seen.ContainsKey('E6')) {
      $sh = $P['shoulder']
      if ($null -ne $Gd.arms.forearm) {
        $need = $P['elbow'].Minus($sh).Len()
        if ($need -gt $Rig.upperArm + 0.005) { Add-Err $slug 'E6' ("com o antebraço travado, o braço precisaria medir {0:0.000} H em t = {1:0.00} (máx. {2})" -f $need, $t, $Rig.upperArm); $seen['E6'] = $true }
      } else {
        $dist = $sol.target.Minus($sh).Len()
        if ($dist -ge [Math]::Abs($sol.ua - $sol.reach) -and $dist -le $sol.ua + $sol.reach) {
          $miss = $P['hand'].Minus($sol.target).Len()
          if ($miss -gt 0.005) { Add-Err $slug 'E6' ("a mão fica a {0:0.000} H do alvo em t = {1:0.00}" -f $miss, $t); $seen['E6'] = $true }
        }
      }
    }
    if (-not $front) {
      $tr = SegAng $P['hip'] $P['shoulder']; $hd = SegAng $P['shoulder'] $P['head']
      $checks = @(,@('pescoço', 'neck', (Norm180 ($hd - $tr))))
      foreach ($s in '', 'Far') {
        $side = if ($s -eq '') { 'lado de cá' } else { 'lado de lá' }
        $th = SegAng $P['hip'] $P['knee' + $s]; $sn = SegAng $P['knee' + $s] $P['ankle' + $s]; $ft = SegAng $P['ankle' + $s] $P['toe' + $s]
        $checks += ,@("joelho ($side)", ('knee' + $s), (Norm180 ($sn - $th)))
        $checks += ,@("tornozelo ($side)", ('ankle' + $s), (Norm180 ($ft - $sn)))
        $checks += ,@("quadril ($side)", ('hip' + $s), (Norm180 ($th - $tr)))
      }
      foreach ($c in $checks) {
        $name = $c[0]; $key = 'E10' + $c[1]; $v = [double]$c[2]
        if ($seen.ContainsKey($key)) { continue }
        $base = $c[1] -replace 'Far$', ''
        $ok = switch ($base) {
          'knee'  { $v -ge -165 - $eps -and $v -le 5 + $eps }
          'ankle' { $v -ge 0 - $eps -and $v -le 140 + $eps }
          'neck'  { $v -ge -60 - $eps -and $v -le 60 + $eps }
          'hip'   { ($v -ge 150 - $eps -and $v -le 180 + $eps) -or ($v -ge -180 - $eps -and $v -le -25 + $eps) }
        }
        if (-not $ok) {
          $range = switch ($base) { 'knee' { 'de -165° a 5°' } 'ankle' { 'de 0° a 140°' } 'neck' { 'de -60° a 60°' } 'hip' { 'de 150° a 180° ou de -180° a -25°' } }
          Add-Err $slug 'E10' ("{0} em {1:0.0}° em t = {2:0.00} (aceito {3})" -f $name, $v, $t, $range); $seen[$key] = $true
        }
      }
    }
  }
}

# ---------------------------------------------------------------- golden (normativo para o GuideGoldenTests)
function F6([double]$v) { $r = [Math]::Round($v, 6); if ($r -eq 0) { $r = 0.0 }; $r.ToString('0.000000', $Inv) }
function PtJson([V2]$p) { '[' + (F6 $p.X) + ', ' + (F6 $p.Y) + ']' }
function JsonStr([string]$s) {
  $sb = New-Object System.Text.StringBuilder; [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    switch ($ch) {
      '"' { [void]$sb.Append('\"') } '\' { [void]$sb.Append('\\') } "`n" { [void]$sb.Append('\n') } "`r" { [void]$sb.Append('\r') } "`t" { [void]$sb.Append('\t') }
      default { if ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
    }
  }
  [void]$sb.Append('"'); $sb.ToString()
}
function Sort-Ordinal($items) { $arr = [string[]]@($items); [Array]::Sort($arr, [StringComparer]::Ordinal); ,$arr }
function Write-Golden($guides, [string]$path) {
  $L = New-Object System.Collections.Generic.List[string]
  $L.Add('{'); $L.Add('  "version": 1,'); $L.Add('  "tolerance": 0.001,'); $L.Add('  "guides": [')
  $sortedGuides = @($guides | Sort-Object -Property @{ Expression = { $_.slug } } -CaseSensitive)
  $gi = 0
  foreach ($Gd in $sortedGuides) {
    $L.Add('    {')
    $L.Add('      "slug": ' + (JsonStr $Gd.slug) + ',')
    $L.Add('      "samples": [')
    $last = [Math]::Max(0, $Gd.frames.Count - 1)
    $names = if ($Gd.view -ceq 'front') { $FrontPoints } else { $SidePoints }
    for ($q = 0; $q -le 4; $q++) {
      $t = $q * $last / 4.0
      $sol = Solve-Guide $Gd $t
      $pts = @(); foreach ($nm in $names) { if ($sol.P.ContainsKey($nm)) { $pts += ((JsonStr $nm) + ': ' + (PtJson $sol.P[$nm])) } }
      $prs = @(); foreach ($k in (Sort-Ordinal @($sol.props.Keys))) { $prs += ((JsonStr $k) + ': ' + (PtJson $sol.props[$k])) }
      $line = '        {"t": ' + (F6 $t) + ', "points": {' + ($pts -join ', ') + '}, "props": {' + ($prs -join ', ') + '}}'
      if ($q -lt 4) { $line += ',' }
      $L.Add($line)
    }
    $L.Add('      ],')
    $mv = Sort-Ordinal @((Get-Moving $Gd $false).Keys)
    $L.Add('      "moving": [' + ((@($mv) | ForEach-Object { JsonStr $_ }) -join ', ') + '],')
    $cp = Get-CuePath $Gd
    $cueTxt = @(); if ($null -ne $cp) { foreach ($i in 0, 10, 20, 30, 40) { $cueTxt += (PtJson $cp[$i]) } }
    $L.Add('      "cue": [' + ($cueTxt -join ', ') + ']')
    $gi++
    if ($gi -lt $sortedGuides.Count) { $L.Add('    },') } else { $L.Add('    }') }
  }
  $L.Add('  ]'); $L.Add('}')
  $dir = Split-Path -Parent $path; if ($dir -ne '') { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($path, (($L -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
  Write-Host "ok  $path ($($sortedGuides.Count) guias)"
}

# ---------------------------------------------------------------- câmera
$script:sc = 100.0; $script:ox = 0.0; $script:oy = 0.0
function ToS([V2]$w) { [V2]::new($script:ox + $w.X * $script:sc, $script:oy - $w.Y * $script:sc) }
function PF([V2]$v) { New-Object System.Drawing.PointF([single]$v.X, [single]$v.Y) }

function Get-SceneRef($Gd, [string]$id) {
  foreach ($s in $Gd.scene) {
    if ($s.id -cne $id) { continue }
    switch -CaseSensitive ($s.kind) { 'pulley' { return $s.at } 'wheel' { return $s.at } 'pad' { return $s.at } 'footPlate' { return $s.at } 'post' { return $s.to } }
  }
  $null
}
function Get-PropRadius($pr) {
  switch -CaseSensitive ($pr.kind) {
    'barbell' { return $Rad.plate } 'dumbbell' { return 0.042 } 'kettlebell' { return 0.12 } 'ball' { return 0.075 } 'vHandle' { return 0.07 }
    'bar' { return 0.03 } 'rope' { return 0.08 } 'plate' { return ((NumOr $pr.length 0.1) / 2.0 + 0.02) } 'roller' { return ((NumOr $pr.radius 0.035) + 0.01) }
    'jumpRope' { return 0.03 }
  }
  0.03
}
function Get-Bounds($Gd) {
  $b = @{ minX = 1e9; maxX = -1e9; minY = 0.0; maxY = -1e9 }
  $grow = { param($x1, $y1, $x2, $y2) $b.minX = [Math]::Min($b.minX, $x1); $b.maxX = [Math]::Max($b.maxX, $x2); $b.minY = [Math]::Min($b.minY, $y1); $b.maxY = [Math]::Max($b.maxY, $y2) }
  $last = [Math]::Max(0, $Gd.frames.Count - 1)
  $propR = @{}; foreach ($pr in $Gd.props) { $propR[$pr.id] = Get-PropRadius $pr; $propR[$pr.id + 'Far'] = $propR[$pr.id] }
  $hasRope = @($Gd.props | Where-Object { $_.kind -ceq 'jumpRope' }).Count -gt 0
  $steps = [Math]::Max(1, [int]($last * 10))
  for ($i = 0; $i -le $steps; $i++) {
    $sol = Solve-Guide $Gd ($last * $i / $steps)
    foreach ($k in $sol.P.Keys) { $p = $sol.P[$k]; $r = if ($k -eq 'head') { 0.072 } else { 0.062 }; & $grow ($p.X - $r) ($p.Y - $r) ($p.X + $r) ($p.Y + $r) }
    foreach ($k in $sol.props.Keys) { $p = $sol.props[$k]; $r = $propR[$k]; if ($null -eq $r) { $r = 0.03 }; & $grow ($p.X - $r) ($p.Y - $r) ($p.X + $r) ($p.Y + $r) }
    if ($hasRope -and $null -ne $sol.P['hand']) { & $grow ($sol.P['hand'].X - 0.22) -0.03 ($sol.P['hand'].X + 0.22) 0.0 }
  }
  $cp = Get-CuePath $Gd
  if ($null -ne $cp) { foreach ($p in $cp) { & $grow ($p.X - 0.04) ($p.Y - 0.04) ($p.X + 0.04) ($p.Y + 0.04) } }
  foreach ($s in $Gd.scene) {
    switch -CaseSensitive ($s.kind) {
      'bench'     { & $grow $s.x 0 ($s.x + $s.length) $s.top }
      'seat'      { & $grow $s.x 0 ($s.x + $s.length) $s.top }
      'rail'      { & $grow $s.x1 0 $s.x2 0.04 }
      'tower'     { & $grow $s.x 0 ($s.x + $s.width) $s.height }
      'block'     { & $grow $s.x $s.y ($s.x + $s.width) ($s.y + $s.height) }
      'steps'     { & $grow $s.x 0 ($s.x + $s.count * $s.run) ($s.count * $s.rise) }
      'post'      { & $grow ([Math]::Min($s.from.X, $s.to.X) - 0.02) ([Math]::Min($s.from.Y, $s.to.Y)) ([Math]::Max($s.from.X, $s.to.X) + 0.02) ([Math]::Max($s.from.Y, $s.to.Y) + 0.02) }
      'wheel'     { & $grow ($s.at.X - $s.radius) ($s.at.Y - $s.radius) ($s.at.X + $s.radius) ($s.at.Y + $s.radius) }
      'pulley'    { & $grow ($s.at.X - 0.03) ($s.at.Y - 0.03) ($s.at.X + 0.03) ($s.at.Y + 0.03) }
      default     {
        if ($null -ne $s.at) { $h = (NumOr $s.length 0.1) / 2.0 + 0.03; & $grow ($s.at.X - $h) ($s.at.Y - $h) ($s.at.X + $h) ($s.at.Y + $h) }
      }
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
  $d = [V2]::Dir($angle).Times([Math]::Max(0.0, $length / 2.0 - $thick / 2.0))
  $path = New-HullPath (ToS ($center.Minus($d))) ($thick / 2.0 * $script:sc) (ToS ($center.Plus($d))) ($thick / 2.0 * $script:sc)
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPath($br, $path); $br.Dispose(); $path.Dispose()
}
function Stroke-WorldBar($g, $color, [V2]$center, [double]$angle, [double]$length, [double]$thick, [double]$w) {
  $d = [V2]::Dir($angle).Times([Math]::Max(0.0, $length / 2.0 - $thick / 2.0))
  $path = New-HullPath (ToS ($center.Minus($d))) ($thick / 2.0 * $script:sc) (ToS ($center.Plus($d))) ($thick / 2.0 * $script:sc)
  $pen = New-Object System.Drawing.Pen($color, [single]($w * $script:sc)); $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
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
  if ($line.Count -ge 2) { $g.DrawLines($pen, $line.ToArray()) }; $pen.Dispose()
  $tri = [System.Drawing.PointF[]]@((PF $end), (PF $base.Plus($n.Times($hw))), (PF $notch), (PF $base.Minus($n.Times($hw))))
  $br = New-Object System.Drawing.SolidBrush($color); $g.FillPolygon($br, $tri); $br.Dispose()
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
  Draw-Limb $g $tn['thigh' + $s] $gap $P['hip'] $Rad.thighTop $P['knee' + $s] $Rad.knee $shift
}
function Draw-Arm($g, $P, [string]$s, $tn, $gap, [V2]$shift, $shoulder = $null) {
  if ($null -eq $shoulder) { $shoulder = $P['shoulder'] }
  Draw-Limb $g $tn['upperArm' + $s] $gap $shoulder $Rad.shoulder $P['elbow' + $s] $Rad.elbow $shift
  Draw-Limb $g $tn['forearm' + $s] $gap $P['elbow' + $s] $Rad.elbowLow $P['wrist' + $s] $Rad.wrist $shift
  Draw-Limb $g $tn['forearm' + $s] $null $P['wrist' + $s] $Rad.wrist $P['fist' + $s] $Rad.hand $shift
}
function Draw-TrunkHead($g, $sol, $tn, $gap) {
  $P = $sol.P; $up = [V2]::Dir($sol.ang.trunk); $zero = [V2]::new(0, 0)
  Draw-Limb $g $tn.trunk $gap $P['hip'] $Rad.hip $P['shoulder'].Minus($up.Times(0.012)) $Rad.chest $zero
  Draw-Limb $g $tn.head $null $P['shoulder'] $Rad.neck $P['head'] $Rad.neck $zero
  Draw-Limb $g $tn.head $gap $P['head'] $Rad.head $P['head'] $Rad.head $zero
  # nariz discreto: diz para onde a pessoa olha sem desenhar rosto
  $face = [V2]::Dir($sol.ang.neck - 90)
  Draw-Limb $g $tn.head $null $P['head'].Plus($face.Times(0.047)) 0.017 $P['head'].Plus($face.Times(0.061)).Plus([V2]::Dir($sol.ang.neck).Times(-0.004)) 0.011 $zero
}

# ---------------------------------------------------------------- corpo (vista frontal)
function Get-FrontTorsoPts($sol) {
  $P = $sol.P; $u = [V2]::Dir($sol.ang.trunk); $r = [V2]::Dir($sol.ang.trunk - 90)
  ,@(
    $P['neckBase'].Plus($r.Times(0.118)).Minus($u.Times(0.01)), $P['hip'].Plus($u.Times(0.13)).Plus($r.Times(0.088)), $P['hip'].Plus($r.Times(0.100)).Minus($u.Times(0.02)),
    $P['hip'].Minus($r.Times(0.100)).Minus($u.Times(0.02)), $P['hip'].Plus($u.Times(0.13)).Minus($r.Times(0.088)), $P['neckBase'].Minus($r.Times(0.118)).Minus($u.Times(0.01)))
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
  Draw-Limb $g $tn.head $null $P['neckBase'] $Rad.neck $P['head'] $Rad.neck $zero
  Draw-Limb $g $tn.head $gap $P['head'] $Rad.head $P['head'] $Rad.head $zero
  foreach ($s in 'Far', '') { Draw-Arm $g $P $s $tn $gap $zero $P['shoulder' + $s] }
}

# ---------------------------------------------------------------- equipamento fixo (cena)
function Get-Layer($s) {
  if ($null -ne $s.layer) { return $s.layer }
  switch -CaseSensitive ($s.kind) { 'tower' { 'back' } 'rail' { 'back' } 'footPlate' { 'back' } 'post' { 'back' } 'steps' { 'back' } default { 'mid' } }
}
function Draw-SceneItem($g, $s, $ink) {
  $cs = $ink.structure; $css = $ink.structureSoft
  if ($s.tone -ceq 'soft') { $cs = $ink.structureSoft; $css = Mix $ink.structureSoft $ink.bg 0.45 }
  switch -CaseSensitive ($s.kind) {
    'bench' {
      $x = $s.x; $top = $s.top; $len = $s.length; $th = 0.042
      foreach ($px in @(($x + 0.10), ($x + $len - 0.10))) {
        Fill-WorldRect $g $css ($px - 0.014) 0.0 0.028 ($top - $th) 0.004
        Fill-WorldRect $g $css ($px - 0.075) 0.0 0.15 0.018 0.009
      }
      Fill-WorldRect $g $cs $x ($top - $th) $len $th 0.016
    }
    'seat' {
      $x = $s.x; $top = $s.top; $len = $s.length; $th = 0.042; $mid = $x + $len / 2.0
      Fill-WorldRect $g $css ($mid - 0.016) 0.03 0.032 ($top - $th - 0.03) 0.004
      Fill-WorldRect $g $cs $x ($top - $th) $len $th 0.016
    }
    'rail' { Fill-WorldRect $g $css $s.x1 0.0 ($s.x2 - $s.x1) 0.036 0.012 }
    'tower' {
      $x = $s.x; $w = $s.width; $h = $s.height
      Fill-WorldRect $g $css $x 0.0 $w $h 0.02
      $inner = Mix $css $ink.bg 0.55
      Fill-WorldRect $g $inner ($x + 0.022) 0.05 ($w - 0.044) ($h - 0.10) 0.012
      for ($k = 0; $k -lt 7; $k++) { Fill-WorldRect $g $cs ($x + 0.034) (0.065 + $k * 0.046) ($w - 0.068) 0.036 0.008 }
      Fill-WorldCircle $g $cs ([V2]::new($x + $w / 2.0, $h - 0.045)) 0.02
    }
    'footPlate' { Fill-WorldBar $g $cs $s.at $s.angle $s.length 0.036 }
    'pulley' { Fill-WorldCircle $g $cs $s.at 0.028; Fill-WorldCircle $g $ink.equip $s.at 0.010 }
    'block' { Fill-WorldRect $g $cs $s.x $s.y $s.width $s.height 0.014 }
    'pad' { Fill-WorldBar $g $cs $s.at $s.angle $s.length (NumOr $s.thick 0.042) }
    'post' {
      $th = NumOr $s.thick 0.024; $d = $s.to.Minus($s.from)
      Fill-WorldBar $g $css ([V2]::Lerp($s.from, $s.to, 0.5)) (SegAng $s.from $s.to) ($d.Len() + $th) $th
    }
    'wheel' {
      if ($s.radius -le 0.03) { Fill-WorldCircle $g $cs $s.at $s.radius }
      else { Stroke-WorldCircle $g $cs $s.at ($s.radius - 0.007) 0.014; Fill-WorldCircle $g $cs $s.at 0.014 }
    }
    'steps' {
      $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
      $pts.Add((PF (ToS ([V2]::new($s.x, 0.0)))))
      for ($i = 0; $i -lt [int]$s.count; $i++) {
        $pts.Add((PF (ToS ([V2]::new($s.x + $i * $s.run, ($i + 1) * $s.rise)))))
        $pts.Add((PF (ToS ([V2]::new($s.x + ($i + 1) * $s.run, ($i + 1) * $s.rise)))))
      }
      $pts.Add((PF (ToS ([V2]::new($s.x + $s.count * $s.run, 0.0)))))
      $br = New-Object System.Drawing.SolidBrush($cs); $g.FillPolygon($br, $pts.ToArray()); $br.Dispose()
    }
  }
}

# ---------------------------------------------------------------- acessórios (movem-se com o corpo)
# Origem do cabo ou elástico que termina neste acessório (para orientar puxador e corda).
function Get-LineSource($Gd, [string]$toId) {
  foreach ($q in $Gd.props) { if (($LineKinds -ccontains $q.kind) -and $q.to -ceq $toId) { $src = Get-SceneRef $Gd $q.from; if ($null -ne $src) { return $src } } }
  $null
}
function Get-LineTarget($Gd, $sol, $pr) {
  $p = $sol.props[$pr.to]; if ($null -ne $p) { return $p }
  $sol.P[$pr.to]
}
function Draw-Lines($g, $Gd, $sol, $color) {
  foreach ($pr in $Gd.props) {
    if (-not ($LineKinds -ccontains $pr.kind)) { continue }
    $from = Get-SceneRef $Gd $pr.from; $to = Get-LineTarget $Gd $sol $pr
    if ($null -eq $from -or $null -eq $to) { continue }
    $tgt = $null; foreach ($q in $Gd.props) { if ($q.id -ceq $pr.to) { $tgt = $q } }
    if ($null -ne $tgt -and ($tgt.kind -ceq 'vHandle' -or $tgt.kind -ceq 'rope')) { $to = $to.Plus($from.Minus($to).Unit().Times(0.06)) }
    $w = if ($pr.kind -ceq 'band') { 0.02 } else { 0.0075 }
    Stroke-WorldLine $g $color $from $to $w
  }
}
function Draw-VHandle($g, $Gd, $pr, [V2]$c, $color) {
  $pull = Get-LineSource $Gd $pr.id
  $dir = if ($null -ne $pull) { $pull.Minus($c).Unit() } else { [V2]::new(1, 0) }
  $apex = $c.Plus($dir.Times(0.06)); $n = $dir.Perp()
  $top = $c.Plus($n.Times(0.044)); $bot = $c.Minus($n.Times(0.044))
  Stroke-WorldLine $g $color $top $apex 0.013
  Stroke-WorldLine $g $color $bot $apex 0.013
  Stroke-WorldLine $g $color $top $bot 0.022
}
function Draw-RopeHandle($g, $Gd, $pr, [V2]$c, $color) {
  $pull = Get-LineSource $Gd $pr.id
  $dir = if ($null -ne $pull) { $pull.Minus($c).Unit() } else { [V2]::new(0, 1) }
  $apex = $c.Plus($dir.Times(0.06)); $n = $dir.Perp()
  foreach ($k in 1.0, -1.0) {
    $end = $c.Plus($n.Times(0.02 * $k)).Minus($dir.Times(0.018))
    Stroke-WorldLine $g $color $apex $end 0.011
    Fill-WorldCircle $g $color $end 0.012
  }
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
# A corda gira em volta do eixo das mãos; no instante desenhado ela passa por baixo dos pés. De frente é um U de
# uma mão à outra; de lado, as duas pontas coincidem e ela aparece como um fio da mão até embaixo dos pés.
function Draw-JumpRope($g, $sol, $color, [V2]$shift) {
  $P = $sol.P; $h1 = $P['hand']
  if ($null -eq $h1) { return }
  $feet = @('toe', 'toeFar', 'heel', 'heelFar', 'ankle', 'ankleFar') | Where-Object { $null -ne $P[$_] } | ForEach-Object { $P[$_] }
  $low = 1e9; $cx = 0.0; $k = 0
  foreach ($f in $feet) { $low = [Math]::Min($low, $f.Y); $cx += $f.X; $k++ }
  if ($k -eq 0) { return }
  $cx /= $k; $low -= 0.022
  $pen = New-Object System.Drawing.Pen($color, [single](0.007 * $script:sc)); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
  if ($sol.front) {
    $h2 = $P['handFar']; if ($null -eq $h2) { $pen.Dispose(); return }
    $cy = ($low - 0.25 * ($h1.Y + $h2.Y) / 2.0) / 0.75
    $g.DrawBezier($pen, (PF (ToS $h1)), (PF (ToS ([V2]::new($h1.X, $cy)))), (PF (ToS ([V2]::new($h2.X, $cy)))), (PF (ToS $h2)))
  } else {
    $bottom = [V2]::new($cx, $low)
    $c1 = $h1.Plus([V2]::new(0.06, -0.22)); $c2 = $bottom.Plus([V2]::new(0.16, 0.06))
    $g.DrawBezier($pen, (PF (ToS $h1.Plus($shift))), (PF (ToS $c1)), (PF (ToS $c2)), (PF (ToS $bottom)))
  }
  $pen.Dispose()
}
function Draw-Prop($g, $Gd, $sol, $pr, [V2]$c, $ink, $color, [bool]$ghost) {
  switch -CaseSensitive ($pr.kind) {
    'barbell' { Draw-Plate $g $c $ink $color ((-not $ghost) -and $pr.attach -cne 'back') }
    'dumbbell' { Draw-Dumbbell $g $c $ink $color (-not $ghost) }
    'kettlebell' {
      # sino pendurado abaixo da pegada: alça em volta da mão e corpo redondo embaixo
      $body = $c.Plus([V2]::new(0, -0.068))
      Stroke-WorldCircle $g $color $c.Plus([V2]::new(0, -0.012)) 0.024 0.011
      if ($ghost) { Stroke-WorldCircle $g $color $body 0.045 0.01 } else { Fill-WorldCircle $g $color $body 0.046 }
    }
    'ball' {
      if (-not $ghost) { Fill-WorldCircle $g (WithAlpha $ink.bg 90) $c 0.07 }
      Stroke-WorldCircle $g $color $c 0.064 0.012
      Stroke-WorldLine $g $color $c.Plus([V2]::new(-0.058, 0.012)) $c.Plus([V2]::new(0.058, 0.012)) 0.008
    }
    'vHandle' { Draw-VHandle $g $Gd $pr $c $color }
    'bar' { if ($ghost) { Stroke-WorldCircle $g $color $c 0.018 0.01 } else { Fill-WorldCircle $g $color $c 0.021 } }
    'rope' { Draw-RopeHandle $g $Gd $pr $c $color }
    'plate' { if ($ghost) { Stroke-WorldBar $g $color $c $pr.angle $pr.length 0.03 0.008 } else { Fill-WorldBar $g $color $c $pr.angle $pr.length 0.03 } }
    'roller' {
      $r = NumOr $pr.radius 0.035
      if (-not $ghost) { Fill-WorldCircle $g (Mix $color $ink.bg 0.55) $c $r }
      Stroke-WorldCircle $g $color $c ($r - 0.005) 0.01
    }
  }
}
# Camada de desenho de um acessório na vista lateral.
function Get-PropLayer($pr, [bool]$front) {
  if ($pr.kind -ceq 'jumpRope') { return 'mid' }
  if ($pr.attach -ceq 'back') { return 'behindTrunk' }
  if ($front) { return 'front' }
  if ($pr.attach -ceq 'chest' -or $pr.kind -ceq 'vHandle' -or $pr.kind -ceq 'rope') { return 'beforeNearArm' }
  if ($pr.attach.EndsWith('Far')) { return 'far' }
  'front'
}
function Draw-HeldProps($g, $Gd, $sol, $ink, [string]$layer) {
  foreach ($pr in $Gd.props) {
    if ($LineKinds -ccontains $pr.kind -or $null -eq $pr.attach) { continue }
    if ((Get-PropLayer $pr ([bool]$sol.front)) -cne $layer) { continue }
    $shift = if ($layer -ceq 'far') { $FarShift } else { [V2]::new(0, 0) }
    if ($pr.kind -ceq 'jumpRope') { Draw-JumpRope $g $sol $ink.equip $shift; continue }
    foreach ($key in @($pr.id, ($pr.id + 'Far'))) {
      $c = $sol.props[$key]; if ($null -eq $c) { continue }
      Draw-Prop $g $Gd $sol $pr $c.Plus($shift) $ink $ink.equip $false
    }
  }
}

# ---------------------------------------------------------------- fantasma (posição inicial, nos quadros seguintes)
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
    & $hull $P['neckBase'] $Rad.neck $P['head'] $Rad.neck
    & $hull $P['head'] $Rad.head $P['head'] $Rad.head
    foreach ($s in 'Far', '') {
      & $hull $P['shoulder' + $s] $Rad.shoulder $P['elbow' + $s] $Rad.elbow
      & $hull $P['elbow' + $s] $Rad.elbowLow $P['wrist' + $s] $Rad.wrist
      & $hull $P['wrist' + $s] $Rad.wrist $P['fist' + $s] $Rad.hand
    }
  } else {
    $up = [V2]::Dir($sol.ang.trunk); $face = [V2]::Dir($sol.ang.neck - 90)
    & $hull $P['heel'] $Rad.heel $P['toe'] $Rad.toe
    & $hull $P['ankle'] $Rad.ankle $P['heel'] $Rad.heel
    & $hull $P['knee'] $Rad.kneeLow $P['ankle'] $Rad.ankle
    & $hull $P['hip'] $Rad.thighTop $P['knee'] $Rad.knee
    & $hull $P['hip'] $Rad.hip $P['shoulder'].Minus($up.Times(0.012)) $Rad.chest
    & $hull $P['shoulder'] $Rad.neck $P['head'] $Rad.neck
    & $hull $P['head'] $Rad.head $P['head'] $Rad.head
    & $hull $P['head'].Plus($face.Times(0.047)) 0.017 $P['head'].Plus($face.Times(0.061)).Plus([V2]::Dir($sol.ang.neck).Times(-0.004)) 0.011
    & $hull $P['shoulder'] $Rad.shoulder $P['elbow'] $Rad.elbow
    & $hull $P['elbow'] $Rad.elbowLow $P['wrist'] $Rad.wrist
    & $hull $P['wrist'] $Rad.wrist $P['fist'] $Rad.hand
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
function Draw-Ghost($g, $Gd, [double]$t, [double]$tNow, $ink) {
  $sol = Solve-Guide $Gd $t; $now = Solve-Guide $Gd $tNow
  $a = Get-BodyShapes $sol; $b = Get-BodyShapes $now
  $sel = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $a.Count; $i++) { if (Test-ShapeMoved $a[$i] $b[$i]) { $sel.Add($a[$i]) } }
  $moved = @{}
  foreach ($k in $sol.props.Keys) { $p1 = $now.props[$k]; $moved[$k] = ($null -eq $p1) -or ($sol.props[$k].Minus($p1).Len() -gt $GhostTol) }
  foreach ($pr in $Gd.props) { if ($pr.kind -ceq 'barbell' -and $pr.attach -ceq 'back' -and $moved[$pr.id]) { Draw-Plate $g $sol.props[$pr.id] $ink $ink.ghostLine $false } }
  Draw-GhostShapes $g $sel $ink
  foreach ($pr in $Gd.props) {
    if ($LineKinds -ccontains $pr.kind -or $pr.kind -ceq 'jumpRope' -or ($pr.kind -ceq 'barbell' -and $pr.attach -ceq 'back')) { continue }
    foreach ($k in @($pr.id, ($pr.id + 'Far'))) { if ($moved[$k]) { Draw-Prop $g $Gd $sol $pr $sol.props[$k] $ink $ink.ghostLine $true } }
  }
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

# Desenha um quadro completo dentro de $rect. $opts: bottomPad, ghostT (posição anterior), cue ($true/$false)
function Draw-Frame($g, [System.Drawing.RectangleF]$rect, $Gd, [double]$t, $ink, [double]$scale, $bounds, $opts) {
  Set-Camera $rect $bounds $scale ([double]$opts.bottomPad)
  $fy = (ToS ([V2]::new(0, 0))).Y
  $pen = New-Object System.Drawing.Pen($ink.floor, [single](0.007 * $script:sc)); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
  $g.DrawLine($pen, [single]($rect.X + 0.05 * $rect.Width), [single]$fy, [single]($rect.Right - 0.05 * $rect.Width), [single]$fy); $pen.Dispose()

  foreach ($s in $Gd.scene) { if ((Get-Layer $s) -ceq 'back') { Draw-SceneItem $g $s $ink } }
  if ($null -ne $opts.ghostT) { Draw-Ghost $g $Gd ([double]$opts.ghostT) $t $ink }
  $sol = Solve-Guide $Gd $t; $P = $sol.P; $tn = Get-Tones $ink $script:movingBy[$Gd.slug] ([bool]$sol.front); $zero = [V2]::new(0, 0)
  if ($sol.front) {
    foreach ($s in $Gd.scene) { if ((Get-Layer $s) -ceq 'mid') { Draw-SceneItem $g $s $ink } }
    Draw-Lines $g $Gd $sol $ink.equip
    Draw-HeldProps $g $Gd $sol $ink 'mid'
    Draw-HeldProps $g $Gd $sol $ink 'behindTrunk'
    Draw-FrontBody $g $sol $tn $ink.bg
    Draw-HeldProps $g $Gd $sol $ink 'front'
  } else {
    Draw-Arm $g $P 'Far' $tn $null $FarShift
    Draw-Leg $g $P 'Far' $tn $null $FarShift
    Draw-HeldProps $g $Gd $sol $ink 'far'
    foreach ($s in $Gd.scene) { if ((Get-Layer $s) -ceq 'mid') { Draw-SceneItem $g $s $ink } }
    Draw-Lines $g $Gd $sol $ink.equip
    Draw-HeldProps $g $Gd $sol $ink 'mid'
    Draw-HeldProps $g $Gd $sol $ink 'behindTrunk'
    Draw-TrunkHead $g $sol $tn $ink.bg
    Draw-Leg $g $P '' $tn $ink.bg $zero
    Draw-HeldProps $g $Gd $sol $ink 'beforeNearArm'
    Draw-Arm $g $P '' $tn $ink.bg $zero
    Draw-HeldProps $g $Gd $sol $ink 'front'
  }
  foreach ($s in $Gd.scene) { if ((Get-Layer $s) -ceq 'front') { Draw-SceneItem $g $s $ink } }
  if ($opts.cue -and $null -ne $script:cueBy[$Gd.slug]) { Draw-Arrow $g $script:cueBy[$Gd.slug] $ink.arrow }
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
function Save-Png($c, [string]$path) { $c.g.Dispose(); $c.bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $c.bmp.Dispose(); Write-Host "ok  $path" }

# ---------------------------------------------------------------- nomes e "Trabalha:"
$script:names = @{}; $script:muscles = @{}; $script:Patterns = @{}
$script:CatalogSlugs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$script:SeenSlugs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
if ($useCatalog) {
  if (-not (Test-Path $Catalog)) { throw "catálogo não encontrado: $Catalog" }
  foreach ($ex in (Get-Content -Raw -Encoding UTF8 $Catalog | ConvertFrom-Json).exercises) {
    [void]$script:CatalogSlugs.Add([string]$ex.slug)
    $script:names[$ex.slug] = $ex.name; $script:muscles[$ex.slug] = @($ex.primaryMuscles); $script:Patterns[$ex.slug] = $ex.movementPattern
  }
}
# mesmos nomes de ReviewText.muscleName (TrainerCore), em minúsculas porque entram no meio da frase
$MuscleNames = @{ chest = 'peito'; back = 'costas'; shoulders = 'ombros'; biceps = 'bíceps'; triceps = 'tríceps'; quads = 'quadríceps'
                  hamstrings = 'posteriores da coxa'; glutes = 'glúteos'; calves = 'panturrilhas'; core = 'abdômen e lombar' }
# Termo técnico que o app mantém ganha a explicação em palavras comuns no "Trabalha:" (DESIGN §7).
$MuscleGloss = @{ quads = 'frente das coxas' }
function NameOf($Gd) { if ($script:names.ContainsKey($Gd.slug)) { $script:names[$Gd.slug] } else { $Gd.slug } }
function WorksOf($Gd) {
  if ($null -ne $Gd.works) { return $Gd.works }
  $list = @()
  foreach ($m in @($script:muscles[$Gd.slug])) {
    if ($null -eq $m) { continue }
    $nm = if ($MuscleNames.ContainsKey($m)) { $MuscleNames[$m] } else { $m }
    if ($MuscleGloss.ContainsKey($m)) { $nm = '{0} ({1})' -f $nm, $MuscleGloss[$m] }
    $list += $nm
  }
  if ($list.Count -eq 0) { return '' }
  if ($list.Count -eq 1) { return $list[0] }
  (($list[0..($list.Count - 2)]) -join ', ') + ' e ' + $list[$list.Count - 1]
}
function Seconds([double]$s) { ($s.ToString('0.0#', [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR'))) + ' s' }
function InfoOf($Gd) {
  $anchor = if ($Gd.anchorJoint -ceq 'none') { 'sem âncora (quadril por quadro)' } else { "âncora: $($Gd.anchorJoint)" }
  if ($Gd.motion -ceq 'static') { return "Figura parada, com setas · $anchor" }
  $tm = $Gd.timing
  "Anima em loop · ida {0} · volta {1} · pausas {2} · {3}" -f (Seconds $tm.toEnd), (Seconds $tm.toStart), (Seconds $tm.hold), $anchor
}

# ---------------------------------------------------------------- folhas de revisão
$Gutter = 36
$Layout = @{
  sheet = @{ panel = 360; cardPad = 28; between = 32; cols = 2; title = 31; compact = $false }
  vocab = @{ panel = 290; cardPad = 22; between = 24; cols = 3; title = 22; compact = $true }
}
# Largura do cartão: cabe o maior número de quadros da folha (1 a 3).
function Get-ColW($lay) { $k = [Math]::Max(1, $script:MaxFrames); 2 * $lay.cardPad + $k * $lay.panel + ($k - 1) * $lay.between }
function Get-CommonScale($guides, [double]$panel, [double]$pad, [double]$topPad, [double]$bottomPad) {
  $s = 1e9
  foreach ($Gd in $guides) { $b = $script:boundsBy[$Gd.slug]; $s = [Math]::Min($s, [Math]::Min(($panel - 2 * $pad) / ($b.maxX - $b.minX), ($panel - $bottomPad - $topPad) / ($b.maxY - $b.minY))) }
  $s
}
# Cartão de um exercício; devolve a coordenada y do fim do conteúdo.
function Draw-Card($g, $ink, $Gd, [double]$x0, [double]$y0, [double]$scale, $lay) {
  $colW = Get-ColW $lay; $pad = $lay.cardPad; $panel = $lay.panel; $between = $lay.between
  $tw = $colW - 2 * $pad; $x = $x0 + $pad
  $y = $y0 + 20
  $fn = New-Font 'Georgia' $lay.title; $y += (Draw-Text $g (NameOf $Gd) $fn $ink.text $x $y $tw); $fn.Dispose()
  $y += 2
  $fsz = if ($lay.compact) { 15 } else { 18 }
  $works = WorksOf $Gd
  if ($works -ne '') {
    $fl = New-Font 'Segoe UI Semibold' $fsz; $fv = New-Font 'Segoe UI' $fsz
    $wl = TextWidth $g 'Trabalha:' $fl
    [void](Draw-Text $g 'Trabalha:' $fl $ink.text2 $x $y 200)
    $y += (Draw-Text $g $works $fv $ink.text ($x + $wl + 6) $y ($tw - $wl - 6)); $fl.Dispose(); $fv.Dispose()
  }
  $fi = New-Font 'Segoe UI' ($fsz - 3); $y += (Draw-Text $g (InfoOf $Gd) $fi $ink.text2 $x $y $tw) + 12; $fi.Dispose()
  $py = $y; $n = $Gd.frames.Count
  for ($f = 0; $f -lt $n; $f++) {
    $px = $x + $f * ($panel + $between)
    Fill-Round $g $ink.page $px $py $panel $panel 18
    $r = New-Object System.Drawing.RectangleF([single]$px, [single]$py, [single]$panel, [single]$panel)
    $opts = @{ bottomPad = 14; cue = ($f -eq 0); ghostT = $null }
    if ($f -gt 0 -and $Gd.motion -ceq 'loop') { $opts.ghostT = 0.0 }
    Draw-Frame $g $r $Gd ([double]$f) $ink $scale $script:boundsBy[$Gd.slug] $opts
    $fr = $Gd.frames[$f]
    $bd = if ($lay.compact) { 24 } else { 28 }
    Draw-Badge $g $ink ([string]($f + 1)) $px ($py + $panel + 12) $bd
    $fc = New-Font 'Segoe UI Semibold' ($fsz); [void](Draw-Text $g $fr.caption $fc $ink.text ($px + $bd + 10) ($py + $panel + 13) ($panel - $bd - 10)); $fc.Dispose()
    if ($f -gt 0) {
      $ax = $px - $between / 2.0; $ay = $py + $panel / 2.0
      $pen = New-Object System.Drawing.Pen($ink.text2, 2.6); $pen.EndCap = 'Round'; $pen.StartCap = 'Round'; $pen.LineJoin = 'Round'
      $g.DrawLine($pen, [single]($ax - 9), [single]$ay, [single]($ax + 8), [single]$ay)
      $g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF([single]($ax + 1), [single]($ay - 7))), (New-Object System.Drawing.PointF([single]($ax + 8), [single]$ay)), (New-Object System.Drawing.PointF([single]($ax + 1), [single]($ay + 7)))))
      $pen.Dispose()
    }
  }
  $y = $py + $panel + 12 + 28 + 20
  if ($lay.compact) {
    $fsm = New-Font 'Segoe UI' 14.5; $y += (Draw-Text $g $Gd.a11y $fsm $ink.text2 $x $y $tw) + 4; $fsm.Dispose()
    return $y
  }
  $sw = $tw - 42
  $fh = New-Font 'Segoe UI Semibold' 18; $fb = New-Font 'Segoe UI' 17.5; $fbb = New-Font 'Segoe UI Semibold' 17.5; $fsm = New-Font 'Segoe UI' 15
  $y += (Draw-Text $g 'Passos' $fh $ink.text $x $y $tw) + 8
  $k = 1
  foreach ($step in $Gd.steps) {
    Draw-Badge $g $ink ([string]$k) $x ($y + 1) 28
    $y += [Math]::Max(30, (Draw-Text $g $step $fb $ink.text ($x + 42) ($y + 2) $sw)) + 10
    $k++
  }
  $y += 12
  $y += (Draw-Text $g 'Erros comuns' $fh $ink.text $x $y $tw) + 8
  foreach ($m in $Gd.mistakes) {
    $pen = New-Object System.Drawing.Pen($ink.text2, 2); $g.DrawEllipse($pen, [single]($x + 9), [single]($y + 8), 10, 10); $pen.Dispose()
    $y += (Draw-Mistake $g $m $fbb $fb $ink ($x + 42) $y $sw) + 10
  }
  $y += 14
  $line = New-Object System.Drawing.Pen((Mix $ink.text2 $ink.surface 0.8), 1); $g.DrawLine($line, [single]$x, [single]$y, [single]($x0 + $colW - $pad), [single]$y); $line.Dispose()
  $y += 12
  $y += (Draw-Text $g ('VoiceOver: "' + $Gd.a11y + '"') $fsm $ink.text2 $x $y $tw) + 4
  $fh.Dispose(); $fb.Dispose(); $fbb.Dispose(); $fsm.Dispose()
  $y
}

# Cabeçalho com título, explicação e legenda de cores; devolve a coordenada y do fim.
function Draw-Header($g, $ink, [double]$W, [string]$title, [string]$sub) {
  $ft = New-Font 'Georgia' 40; [void](Draw-Text $g $title $ft $ink.text $Gutter 28 ($W - 2 * $Gutter)); $ft.Dispose()
  $fs = New-Font 'Segoe UI' 18
  $y = 88 + (Draw-Text $g $sub $fs $ink.text2 $Gutter 88 ($W - 2 * $Gutter)) + 14
  $fs.Dispose()
  # legenda: amostras sobre o fundo do quadro, com as mesmas cores da figura (só da folha: no app não há legenda)
  $items = @(
    @('limb', $ink.nearMove, 'o que se move'), @('limb', $ink.nearStill, 'resto do corpo'), @('pair', $null, 'lado de lá, mais suave'),
    @('ghost', $null, 'posição inicial'), @('arrow', $ink.arrow, 'caminho da ida'), @('ring', $ink.equip, 'equipamento que se move'))
  $fl = New-Font 'Segoe UI' 16.5; $flb = New-Font 'Segoe UI Semibold' 16.5
  $lead = 'Legenda (só da revisão):'
  $leadW = TextWidth $g $lead $flb
  $totalW = $leadW + 24; foreach ($it in $items) { $totalW += 44 + 10 + (TextWidth $g $it[2] $fl) + 30 }
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
        $p = New-HullPath ([V2]::new($x + 7, $cy)) 7 ([V2]::new($x + 37, $cy)) 7
        $pen = New-Object System.Drawing.Pen($ink.ghostLine, 5.0); $pen.DashPattern = [single[]]@(1.8, 1.2); $g.DrawPath($pen, $p); $pen.Dispose()
        $b = New-Object System.Drawing.SolidBrush($ink.ghostFill); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
      }
      'pair' {
        $p = New-HullPath ([V2]::new($x + 7, $cy - 4)) 6 ([V2]::new($x + 37, $cy - 4)) 6; $b = New-Object System.Drawing.SolidBrush($ink.farMove); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
        $p = New-HullPath ([V2]::new($x + 7, $cy + 5)) 6 ([V2]::new($x + 37, $cy + 5)) 6; $b = New-Object System.Drawing.SolidBrush($ink.farStill); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
      }
      'arrow' {
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

# Uma aparência (clara ou escura) da folha: devolve o canvas desenhado.
function Render-Look($guides, [string]$look, $lay, [string]$title, [string]$sub, [string]$footer) {
  $ink = New-Ink $look
  $script:MaxFrames = 1; foreach ($Gd in $guides) { $script:MaxFrames = [Math]::Max($script:MaxFrames, $Gd.frames.Count) }
  $colW = Get-ColW $lay; $cols = $lay.cols; $rows = [int][Math]::Ceiling($guides.Count / $cols)
  $W = [int]($cols * $colW + ($cols + 1) * $Gutter)
  $scale = Get-CommonScale $guides $lay.panel 8 10 14
  $probe = New-Canvas $W 2400; $headH = Draw-Header $probe.g $ink $W $title $sub
  $heights = @(); foreach ($Gd in $guides) { $heights += (Draw-Card $probe.g $ink $Gd 0 0 $scale $lay) }
  $probe.g.Dispose(); $probe.bmp.Dispose()
  $rowH = @(); for ($r = 0; $r -lt $rows; $r++) { $m = 0.0; for ($c = 0; $c -lt $cols; $c++) { $i = $r * $cols + $c; if ($i -lt $guides.Count) { $m = [Math]::Max($m, $heights[$i]) } }; $rowH += $m + 22 }
  $H = [int][Math]::Ceiling($headH + ($rowH | Measure-Object -Sum).Sum + ($rows - 1) * $Gutter + 72)
  $cv = New-Canvas $W $H; $g = $cv.g; $g.Clear($ink.page)
  [void](Draw-Header $g $ink $W $title $sub)
  $y = $headH
  for ($r = 0; $r -lt $rows; $r++) {
    for ($c = 0; $c -lt $cols; $c++) {
      $i = $r * $cols + $c; if ($i -ge $guides.Count) { continue }
      $x0 = $Gutter + $c * ($colW + $Gutter)
      Fill-Round $g $ink.surface $x0 $y $colW $rowH[$r] 24
      [void](Draw-Card $g $ink $guides[$i] $x0 $y $scale $lay)
    }
    $y += $rowH[$r] + $Gutter
  }
  $ff = New-Font 'Segoe UI' 15
  [void](Draw-Text $g $footer $ff $ink.text2 $Gutter ($H - 50) ($W - 2 * $Gutter))
  $ff.Dispose()
  Write-Host ("escala comum ({0}): {1:0} px por estatura; quadro de {2} px" -f $look, $scale, $lay.panel)
  $cv
}
function Render-Sheet($guides, [string]$name) {
  $lay = $Layout.sheet
  $title = "Como fazer · lote $name"
  $sub = "Folha de revisão (docs/V23-CORE-CONTRACT.md §4). No app a figura anima em loop entre os quadros; com Reduzir Movimento, ou numa guia parada (static), os quadros ficam lado a lado, como aqui."
  $footer = 'Cores: DESIGN.md §3 e §12 · proporções: Drillis e Contini (1966), em Winter · "Trabalha:": primaryMuscles de exercises.v2.json ou "works" · dados: ' + (Split-Path -Leaf $Data)
  foreach ($look in 'light', 'dark') {
    $cv = Render-Look $guides $look $lay $title $sub $footer
    $file = if ($look -eq 'light') { "sheet-$name.png" } else { "sheet-$name-dark.png" }
    Save-Png $cv (Join-Path $Out $file)
  }
}
function Render-Vocabulary($guides) {
  $lay = $Layout.vocab
  $title = 'Como fazer · vocabulário do formato'
  $sub = 'Um exemplo de cada cena, acessório e recurso novo do formato (docs/V23-CORE-CONTRACT.md §2.5), para quem vai desenhar os lotes. O título de cada cartão é o recurso; o texto embaixo é a frase do VoiceOver. Aparência clara em cima, escura embaixo.'
  $footer = 'dados: vocabulary.sample.json (slugs vocab-*, validados com -Catalog desligado; nunca vão para o seed)'
  $light = Render-Look $guides 'light' $lay $title $sub $footer
  $dark = Render-Look $guides 'dark' $lay $title $sub $footer
  $W = [Math]::Max($light.bmp.Width, $dark.bmp.Width); $H = $light.bmp.Height + $dark.bmp.Height
  $cv = New-Canvas $W $H
  $cv.g.DrawImageUnscaled($light.bmp, 0, 0); $cv.g.DrawImageUnscaled($dark.bmp, 0, $light.bmp.Height)
  $light.g.Dispose(); $light.bmp.Dispose(); $dark.g.Dispose(); $dark.bmp.Dispose()
  Save-Png $cv (Join-Path $Out 'vocabulary.png')
}

# ---------------------------------------------------------------- principal
$bytes = [System.IO.File]::ReadAllBytes($Data)
$fileErrors = @()
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $fileErrors += 'arquivo com BOM: grave em UTF-8 sem BOM' }
if ([Array]::IndexOf($bytes, [byte]13) -ge 0) { $fileErrors += 'fim de linha CRLF: use LF' }
$doc = $null
try { $doc = (New-Object System.Text.UTF8Encoding $false).GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json }
catch { $fileErrors += ('JSON inválido: ' + $_.Exception.Message) }
if ($null -ne $doc) {
  if (-not (IsObj $doc)) { $fileErrors += 'o topo deve ser um objeto' }
  else {
    foreach ($k in (KeysOf $doc)) { if (@('version', 'rig', 'units', 'guides') -cnotcontains $k) { $fileErrors += "chave desconhecida no topo: '$k'" } }
    if (-not ((IsNum $doc.version) -and [double]$doc.version -eq 1)) { $fileErrors += 'version deve ser 1' }
    if ($doc.units -cne 'stature') { $fileErrors += "units deve ser 'stature'" }
    if (-not (IsArr $doc.guides)) { $fileErrors += 'guides deve ser uma lista' }
  }
}
$rigError = ($null -ne $doc) -and (IsObj $doc) -and ($doc.rig -cne 'mannequin-v2')
$rawGuides = @()
if ($null -ne $doc -and (IsObj $doc) -and (IsArr $doc.guides)) { $rawGuides = @($doc.guides) }
if ($Only -ne '') {
  $onlySet = @($Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  $rawGuides = @($rawGuides | Where-Object { $onlySet -ccontains $_.slug })
}
$guides = New-Object System.Collections.Generic.List[object]
$index = 0
foreach ($raw in $rawGuides) {
  $Gd = Test-Guide $raw $index
  if ($null -ne $Gd) { Test-Kinematics $Gd; $guides.Add($Gd) }
  $index++
}
$bad = $fileErrors.Count + $(if ($rigError) { 1 } else { 0 }) + $script:Errors.Count
foreach ($m in $fileErrors) { Write-Host "ERRO (arquivo) format: $m" }
if ($rigError) { Write-Host "ERRO (arquivo) E3: rig deve ser 'mannequin-v2'" }
$bySlug = @{}; foreach ($e in $script:Errors) { if (-not $bySlug.ContainsKey($e.slug)) { $bySlug[$e.slug] = @() }; $bySlug[$e.slug] += $e }
$index = 0
foreach ($raw in $rawGuides) {
  $slug = if ((IsStr $raw.slug) -and $raw.slug -ne '') { [string]$raw.slug } else { "(guia $index)" }
  if ($bySlug.ContainsKey($slug)) { foreach ($e in $bySlug[$slug]) { Write-Host ("ERRO {0} {1}: {2}" -f $slug, $e.rule, $e.msg) }; $bySlug.Remove($slug) }
  elseif ($Check) { Write-Host "ok $slug" }
  $index++
}
if ($bad -gt 0) { Write-Host ("{0} erro(s) em {1}" -f $bad, $Data); exit 1 }
if ($Check -and $Sheet -eq '' -and $Golden -eq '' -and -not $Vocabulary) { Write-Host ("{0} guia(s) válidas em {1}" -f $guides.Count, $Data); exit 0 }
if ($Sheet -eq '' -and $Golden -eq '' -and -not $Vocabulary) { Write-Host 'nada a fazer: use -Check, -Sheet <nome>, -Golden <arquivo> ou -Vocabulary'; exit 0 }
if ($guides.Count -eq 0) { Write-Host 'nenhuma guia para desenhar'; exit 1 }

$script:movingBy = @{}; $script:cueBy = @{}; $script:boundsBy = @{}
$verbose = ($Sheet -ne '' -or $Vocabulary)
if ($verbose) { Test-Contrast $false; Write-Host 'o que se move (MOVE = acento forte):' }
foreach ($Gd in $guides) { $script:movingBy[$Gd.slug] = Get-Moving $Gd $verbose; $script:cueBy[$Gd.slug] = Get-CuePath $Gd; $script:boundsBy[$Gd.slug] = Get-Bounds $Gd }
if ($Golden -ne '') {
  $gpath = if ([System.IO.Path]::IsPathRooted($Golden)) { $Golden } else { Join-Path (Get-Location).Path $Golden }
  Write-Golden $guides $gpath
}
New-Item -ItemType Directory -Force -Path $Out | Out-Null
if ($Sheet -ne '') { Render-Sheet $guides $Sheet }
if ($Vocabulary) { Render-Vocabulary $guides }
exit 0
