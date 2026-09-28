# merge-guides.ps1 — junta os lotes do "Como fazer" no arquivo do seed (docs/V23-CORE-CONTRACT.md §2.7).
#
# Lê batches.json e os batch-<id>.json que existirem nesta pasta e:
#   1. recusa lote com erro no -Check (render-exercise-guides.ps1), slug fora do manifesto do lote e slug repetido;
#   2. grava PersonalTrainer/Resources/Seed/exercise-guides.v1.json com as guias em ordem de slug. O serializador é
#      próprio e determinístico (2 espaços, listas de números numa linha, chaves na ordem de §2.5, números com até
#      6 casas, UTF-8 sem BOM, LF): rodar duas vezes dá os mesmos bytes. O arquivo do seed é gerado; nunca o edite
#      à mão;
#   3. roda -Check (com o catálogo do seed) e -Golden sobre o resultado, gravando
#      Packages/TrainerCore/Tests/TrainerCoreTests/Fixtures/exercise-guides-golden.v1.json, e o golden do vocabulário
#      (exercise-guides-vocabulary-golden.v1.json, com o catálogo desligado);
#   4. lista os slugs do manifesto que ainda não têm guia.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File merge-guides.ps1
param()
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\..'))
$renderer = Join-Path $here 'render-exercise-guides.ps1'
$seedFile = Join-Path $repo 'PersonalTrainer\Resources\Seed\exercise-guides.v1.json'
$goldenFile = Join-Path $repo 'Packages\TrainerCore\Tests\TrainerCoreTests\Fixtures\exercise-guides-golden.v1.json'
$vocabularyGoldenFile = Join-Path $repo 'Packages\TrainerCore\Tests\TrainerCoreTests\Fixtures\exercise-guides-vocabulary-golden.v1.json'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Fail([string]$msg) { Write-Host "ERRO $msg"; exit 1 }
function Read-Json([string]$path) { ($Utf8.GetString([System.IO.File]::ReadAllBytes($path))).TrimStart([char]0xFEFF) | ConvertFrom-Json }
function Invoke-Renderer([string[]]$arguments) {
  $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $renderer @arguments 2>&1
  @{ code = $LASTEXITCODE; lines = @($output | ForEach-Object { [string]$_ }) }
}

# ---------------------------------------------------------------- serializador determinístico
# Ordem das chaves por contexto (§2.5). Chaves fora da tabela (não deveriam existir: o -Check as recusa) vão no fim.
$Order = @{
  top    = @('version', 'rig', 'units', 'guides')
  guide  = @('slug', 'view', 'motion', 'anchor', 'timing', 'scene', 'props', 'arms', 'frames', 'cue', 'moving', 'works', 'a11y', 'steps', 'mistakes')
  anchor = @('joint', 'at')
  timing = @('toEnd', 'toStart', 'hold', 'easing')
  scene  = @('kind', 'id', 'layer', 'tone', 'x', 'x1', 'x2', 'y', 'top', 'at', 'from', 'to', 'length', 'width', 'height', 'angle', 'thick', 'radius', 'count', 'rise', 'run')
  prop   = @('id', 'kind', 'attach', 'offset', 'along', 'side', 'length', 'angle', 'radius', 'from', 'to')
  arms   = @('reach', 'depth', 'elbow', 'forearm', 'farArm')
  frame  = @('label', 'caption', 'pose', 'grip', 'armDepth', 'legDepth', 'elbow', 'root')
  pose   = @('trunk', 'neck', 'thigh', 'shin', 'foot', 'upperArm', 'forearm', 'thighFar', 'shinFar', 'footFar', 'upperArmFar', 'forearmFar')
  cue    = @('track', 'span', 'offset', 'side', 'gap')
}
$ChildCtx = @{ guides = 'guide'; anchor = 'anchor'; timing = 'timing'; scene = 'scene'; props = 'prop'; arms = 'arms'; frames = 'frame'; pose = 'pose'; cue = 'cue' }
function IsNum($v) { ($v -is [int]) -or ($v -is [long]) -or ($v -is [double]) -or ($v -is [decimal]) }
function KeysOf($o) { @($o.PSObject.Properties | ForEach-Object { $_.Name }) }
function Format-Num($v) { $d = [Math]::Round([double]$v, 6); if ($d -eq 0) { $d = 0.0 }; $d.ToString('0.######', $Inv) }
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
function Test-AllNumbers($arr) { if ($arr.Count -eq 0) { return $false }; foreach ($x in $arr) { if (-not (IsNum $x)) { return $false } }; $true }
function Write-Value($sb, $v, [string]$ctx, [int]$level) {
  $pad = '  ' * $level; $pad2 = '  ' * ($level + 1)
  if ($null -eq $v) { [void]$sb.Append('null'); return }
  if ($v -is [bool]) { if ($v) { [void]$sb.Append('true') } else { [void]$sb.Append('false') }; return }
  if (IsNum $v) { [void]$sb.Append((Format-Num $v)); return }
  if ($v -is [string]) { [void]$sb.Append((JsonStr $v)); return }
  if ($v -is [System.Array]) {
    if ($v.Count -eq 0) { [void]$sb.Append('[]'); return }
    if (Test-AllNumbers $v) { [void]$sb.Append('[' + ((@($v) | ForEach-Object { Format-Num $_ }) -join ', ') + ']'); return }
    [void]$sb.Append("[`n")
    for ($i = 0; $i -lt $v.Count; $i++) {
      [void]$sb.Append($pad2); Write-Value $sb $v[$i] $ctx ($level + 1)
      if ($i -lt $v.Count - 1) { [void]$sb.Append(',') }
      [void]$sb.Append("`n")
    }
    [void]$sb.Append($pad + ']'); return
  }
  $keys = KeysOf $v; $ordered = New-Object System.Collections.Generic.List[string]
  if ($Order.ContainsKey($ctx)) { foreach ($k in $Order[$ctx]) { if ($keys -ccontains $k) { $ordered.Add($k) } } }
  foreach ($k in $keys) { if (-not $ordered.Contains($k)) { $ordered.Add($k) } }
  if ($ordered.Count -eq 0) { [void]$sb.Append('{}'); return }
  [void]$sb.Append("{`n")
  for ($i = 0; $i -lt $ordered.Count; $i++) {
    $k = $ordered[$i]; $child = if ($ChildCtx.ContainsKey($k)) { $ChildCtx[$k] } else { '' }
    [void]$sb.Append($pad2 + (JsonStr $k) + ': ')
    Write-Value $sb ($v.PSObject.Properties[$k].Value) $child ($level + 1)
    if ($i -lt $ordered.Count - 1) { [void]$sb.Append(',') }
    [void]$sb.Append("`n")
  }
  [void]$sb.Append($pad + '}')
}

# ---------------------------------------------------------------- lotes
$manifest = Read-Json (Join-Path $here 'batches.json')
if ($manifest.version -ne 1) { Fail 'batches.json: version deve ser 1' }
$owner = @{}            # slug -> id do lote no manifesto
$batchIds = @{}
$wanted = New-Object System.Collections.Generic.List[string]
foreach ($b in @($manifest.batches)) {
  $id = [string]$b.id
  if ($batchIds.ContainsKey($id)) { Fail "batches.json: lote $id repetido" }
  $batchIds[$id] = $true
  foreach ($s in @($b.slugs)) {
    if ($owner.ContainsKey([string]$s)) { Fail "batches.json: slug $s em dois lotes ($($owner[[string]$s]) e $id)" }
    $owner[[string]$s] = $id; $wanted.Add([string]$s)
  }
}

$guides = @{}           # slug -> guia (objeto do ConvertFrom-Json)
foreach ($b in @($manifest.batches)) {
  $id = [string]$b.id
  $file = Join-Path $here ("batch-{0}.json" -f $id)
  if (-not (Test-Path $file)) { Write-Host "lote ${id}: ainda sem batch-$id.json"; continue }
  $check = Invoke-Renderer @('-Check', '-Data', $file)
  if ($check.code -ne 0) { $check.lines | ForEach-Object { Write-Host "  $_" }; Fail "lote $id reprovado no -Check" }
  $doc = Read-Json $file
  $count = 0
  foreach ($g in @($doc.guides)) {
    $slug = [string]$g.slug
    if ($owner[$slug] -cne $id) { Fail "lote ${id}: slug $slug não é deste lote no manifesto" }
    if ($guides.ContainsKey($slug)) { Fail "slug repetido: $slug" }
    $guides[$slug] = $g; $count++
  }
  Write-Host ("lote {0} ({1}): {2} guia(s)" -f $id, $b.title, $count)
}

# ---------------------------------------------------------------- arquivo do seed
$slugs = [string[]]@($guides.Keys); [Array]::Sort($slugs, [StringComparer]::Ordinal)
$top = [pscustomobject][ordered]@{ version = 1; rig = 'mannequin-v2'; units = 'stature'; guides = @($slugs | ForEach-Object { $guides[$_] }) }
$sb = New-Object System.Text.StringBuilder
Write-Value $sb $top 'top' 0
[void]$sb.Append("`n")
[System.IO.File]::WriteAllText($seedFile, $sb.ToString(), $Utf8)
Write-Host ("ok  {0} ({1} guias)" -f $seedFile, $slugs.Count)

$check = Invoke-Renderer @('-Check', '-Data', $seedFile)
if ($check.code -ne 0) { $check.lines | ForEach-Object { Write-Host "  $_" }; Fail 'o arquivo do seed reprovou no -Check' }
$gold = Invoke-Renderer @('-Golden', $goldenFile, '-Data', $seedFile)
$gold.lines | ForEach-Object { Write-Host "  $_" }
if ($gold.code -ne 0) { Fail 'falhou ao gravar o golden' }
# O vocabulário usa todos os recursos do formato; o golden dele protege no Swift os caminhos que os lotes ainda não usam.
$vocabGold = Invoke-Renderer @('-Golden', $vocabularyGoldenFile, '-Data', (Join-Path $here 'vocabulary.sample.json'), '-NoCatalog')
$vocabGold.lines | ForEach-Object { Write-Host "  $_" }
if ($vocabGold.code -ne 0) { Fail 'falhou ao gravar o golden do vocabulário' }

$missing = @($wanted | Where-Object { -not $guides.ContainsKey($_) })
if ($missing.Count -eq 0) { Write-Host "todas as $($wanted.Count) guias do manifesto estão no seed" }
else { Write-Host ("faltam {0} de {1} guias: {2}" -f $missing.Count, $wanted.Count, ($missing -join ', ')) }
exit 0
