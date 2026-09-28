# review-sheets.ps1 — folhas de revisão do dono para o arquivo do seed (docs/V23-CORE-CONTRACT.md §5 passo 3, CA6-7).
#
# Depois de merge-guides.ps1, desenha com render-exercise-guides.ps1:
#   - sheet-all.png e sheet-all-dark.png: todas as guias do seed, em ordem de slug;
#   - sheet-grupo-<id>.png e sheet-grupo-<id>-dark.png: as mesmas guias por grupo de movimento (movementPattern do
#     catálogo), com uns 10 exercícios por folha, porque a folha inteira fica alta demais para revisar de uma vez.
# Um padrão fora da tabela vai para o grupo "outros", para nenhuma guia ficar sem folha.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File review-sheets.ps1
param()
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\..'))
$renderer = Join-Path $here 'render-exercise-guides.ps1'
$seedFile = Join-Path $repo 'PersonalTrainer\Resources\Seed\exercise-guides.v1.json'
$catalogFile = Join-Path $repo 'PersonalTrainer\Resources\Seed\exercises.v2.json'
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Read-Json([string]$path) { ($Utf8.GetString([System.IO.File]::ReadAllBytes($path))).TrimStart([char]0xFEFF) | ConvertFrom-Json }
function Invoke-Sheet([string]$name, [string]$title, [string]$only) {
  $arguments = @('-Data', $seedFile, '-Sheet', $name, '-Title', $title)
  if ($only -ne '') { $arguments += @('-Only', $only) }
  $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $renderer @arguments 2>&1
  $code = $LASTEXITCODE
  $output | ForEach-Object { [string]$_ } | Where-Object { $_ -like 'ok  *' -or $_ -like 'ERRO*' } | ForEach-Object { Write-Host "  $_" }
  if ($code -ne 0) { Write-Host "ERRO a folha $name falhou"; exit 1 }
}

# Grupos da revisão: id do arquivo, título e padrões de movimento (MovementPattern).
$Groups = @(
  @{ id = 'pernas'; title = 'Pernas: agachar, avançar e panturrilha'; patterns = @('squat', 'lunge', 'kneeExtension', 'calfRaise') },
  @{ id = 'quadril'; title = 'Quadril, glúteos e parte de trás das coxas'; patterns = @('hinge', 'hipThrust', 'kneeFlexion') },
  @{ id = 'empurrar'; title = 'Empurrar: peito, ombros e tríceps'; patterns = @('horizontalPush', 'verticalPush', 'chestFly', 'shoulderIsolation', 'elbowExtension') },
  @{ id = 'puxar'; title = 'Puxar: costas e bíceps'; patterns = @('horizontalPull', 'verticalPull', 'elbowFlexion') },
  @{ id = 'tronco'; title = 'Tronco, carregar e pescoço'; patterns = @('coreFlexion', 'coreStability', 'carry', 'neck') },
  @{ id = 'potencia-aerobico'; title = 'Potência e aeróbico'; patterns = @('explosive', 'cardio') }
)

$patternBySlug = @{}
foreach ($e in @((Read-Json $catalogFile).exercises)) { $patternBySlug[[string]$e.slug] = [string]$e.movementPattern }
$slugs = @(@((Read-Json $seedFile).guides) | ForEach-Object { [string]$_.slug })
if ($slugs.Count -eq 0) { Write-Host 'ERRO o arquivo do seed não tem guias'; exit 1 }

Write-Host ("todas ({0} guias)" -f $slugs.Count)
Invoke-Sheet 'all' ("Como fazer · todas as guias ({0})" -f $slugs.Count) ''

$grouped = @{}
foreach ($grp in $Groups) {
  $members = @($slugs | Where-Object { $grp.patterns -ccontains $patternBySlug[$_] })
  foreach ($s in $members) { $grouped[$s] = $true }
  if ($members.Count -eq 0) { continue }
  Write-Host ("grupo {0} ({1} guias)" -f $grp.id, $members.Count)
  Invoke-Sheet ("grupo-{0}" -f $grp.id) ("Como fazer · {0} ({1})" -f $grp.title, $members.Count) ($members -join ',')
}
$others = @($slugs | Where-Object { -not $grouped.ContainsKey($_) })
if ($others.Count -gt 0) {
  Write-Host ("grupo outros ({0} guias): {1}" -f $others.Count, ($others -join ', '))
  Invoke-Sheet 'grupo-outros' ("Como fazer · outros ({0})" -f $others.Count) ($others -join ',')
}
exit 0
