# render-paper-fiber.ps1 — a fibra de washi do papel do Magister (DESIGN §14; docs/V23-UI-CONTRACT.md
# §4.1 item 2): um PNG de 256 px, ladrilhável, com fibras curtas e curvas espalhadas pelo quadro, gerado
# por um PRNG de SEMENTE FIXA (determinístico: rodar de novo dá o mesmo PNG, mesmo SHA-256, embora
# `System.Random` não seja `Get-Random` "de verdade" — a decisão do dono pede exatamente isso: "gerador
# com semente fixa, nada de aleatório de verdade").
#
# `PaperBackground.swift` (`paperBackground()`) desenha esta imagem ladrilhada (`.resizable(resizingMode:
# .tile)`) a mais 4 % de opacidade por cima de `Theme.background`; por isso as fibras aqui já saem bem
# mais fortes do que o resultado final na tela (a diluição final é feita no app, não aqui).
#
# Ladrilhamento sem costura: cada fibra é desenhada 9 vezes, deslocada por (-256/0/256, -256/0/256); o
# GDI+ recorta sozinho o que cai fora do quadro 256×256, então só a parte que "voltaria" pela borda
# oposta aparece — o mesmo truque de qualquer textura ladrilhável por deslocamento.
#
# Saída: <ImageSet>\PaperFiber.png (clara) e PaperFiber-dark.png (escura), mais o Contents.json do
# imageset (`appearances`/`luminosity`, o mesmo mecanismo do `AppIcon-dark.png`).
#
# Uso: powershell -ExecutionPolicy Bypass -File docs/design/v23-ink/render-paper-fiber.ps1 [-ImageSet <pasta>]
param([string]$ImageSet = '')
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# $here = docs\design\v23-ink: sobe 3 níveis (v23-ink → design → docs → raiz do repo).
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
if ($ImageSet -eq '') { $ImageSet = Join-Path $repo 'PersonalTrainer\Resources\Assets.xcassets\PaperFiber.imageset' }
New-Item -ItemType Directory -Force -Path $ImageSet | Out-Null

$S = 256
# Semente fixa (não é a hora do relógio): sempre o mesmo washi.
$Seed = 20260928

function HexColor([string]$hex, [int]$a = 255) {
  $h = $hex.TrimStart('#')
  [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16))
}
function P([double]$x, [double]$y) { New-Object System.Drawing.PointF([single]$x, [single]$y) }

# Uma fibra: um traço curto e levemente curvo (3 pontos, `AddCurve` faz a spline), com espessura e alfa
# próprios. `perp` desvia o ponto do meio para o lado, dando a leve curva (senão seria um segmento reto).
function New-Fiber([System.Random]$rng, [string]$hex) {
  $x = $rng.NextDouble() * $S
  $y = $rng.NextDouble() * $S
  $angle = $rng.NextDouble() * 2 * [Math]::PI
  $len = 6 + $rng.NextDouble() * 16
  $bend = ($rng.NextDouble() - 0.5) * 3.0
  $dx = [Math]::Cos($angle); $dy = [Math]::Sin($angle)
  $px = -$dy; $py = $dx
  $start = P ($x - $dx * $len / 2) ($y - $dy * $len / 2)
  $end   = P ($x + $dx * $len / 2) ($y + $dy * $len / 2)
  $mid   = P ($x + $px * $bend) ($y + $py * $bend)
  @{
    Points = @($start, $mid, $end)
    Alpha = [int](40 + $rng.NextDouble() * 110)
    Width = [single](0.6 + $rng.NextDouble() * 1.1)
    Color = (HexColor $hex)
  }
}

function Render-Fiber([int]$count, [string]$hex) {
  $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.Clear([System.Drawing.Color]::Transparent)
  $rng = New-Object System.Random($Seed)
  $shifts = @(-$S, 0, $S)
  for ($i = 0; $i -lt $count; $i++) {
    $fiber = New-Fiber $rng $hex
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($fiber.Alpha, $fiber.Color.R, $fiber.Color.G, $fiber.Color.B), $fiber.Width)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    foreach ($sx in $shifts) {
      foreach ($sy in $shifts) {
        $shifted = $fiber.Points | ForEach-Object { P ($_.X + $sx) ($_.Y + $sy) }
        $g.DrawCurve($pen, [System.Drawing.PointF[]]$shifted, 0.5)
      }
    }
    $pen.Dispose()
  }
  $g.Dispose()
  $bmp
}

# Tons de fibra (DESIGN §3): um pouco mais escuros que `background` claro e um pouco mais claros que
# `background` escuro — o suficiente para aparecer nas fibras individuais (antes da diluição a 4 % que o
# app aplica por cima).
$light = Render-Fiber 420 '#B9A88C'
$dark = Render-Fiber 420 '#5A5049'

$light.Save((Join-Path $ImageSet 'PaperFiber.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$dark.Save((Join-Path $ImageSet 'PaperFiber-dark.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$light.Dispose(); $dark.Dispose()

$contents = @'
{
  "images" : [
    {
      "filename" : "PaperFiber.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "PaperFiber-dark.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $ImageSet 'Contents.json'), $contents, (New-Object System.Text.UTF8Encoding($false)))

"fibra de washi: $ImageSet (PaperFiber.png, PaperFiber-dark.png, Contents.json)"
