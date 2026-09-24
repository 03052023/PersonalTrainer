# render-final.ps1 - icone final do app: "Florescer" (conceito Engobe refinado).
# Cinco petalas de engobe creme sobre barro bege; onde duas petalas vizinhas se cruzam, uma lente mais densa;
# no centro, um miolo vazado (o proprio barro aparece). Desenho 100% geometrico, sem texto, sem cantos
# arredondados (o iOS aplica a mascara), sem sombra nem brilho pintados (o sistema aplica o Liquid Glass).
#
# Saidas (pasta deste script):
#   AppIcon.png          1024x1024, opaco (24 bpp) - icone padrao
#   AppIcon-dark.png     1024x1024, opaco - variante escura (extra, para o catalogo do iOS 18)
#   AppIcon-tinted.png   1024x1024, opaco, tons de cinza - variante tingida (extra)
#   AppIcon-120.png      reducao bicubica de alta qualidade
#   AppIcon-preview.png  360x360: tela inicial clara (#F2F2F7) e escura (#1C1C1E), 120/40 px + recorte do Watch
#   AppIcon-checks.png   checagem: aparencias padrao/escura/tingida, recorte circular do Watch no 1024
#
# Execute: powershell -NoProfile -ExecutionPolicy Bypass -File render-final.ps1
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$out = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $out) { $out = 'C:\Users\leona\AppData\Local\Temp\claude\C--Users-leona-Developer-PersonalTrainer\92bc4612-e4c3-4f04-82ff-84e69e1c6f27\scratchpad\design\blue-3' }
New-Item -ItemType Directory -Force $out | Out-Null

# ---------------- parametros ----------------
$Shape = @{
    k          = 0.685   # raio tangencial da petala / distancia do centro (define quanto as vizinhas se cruzam)
    elong      = 1.10    # alongamento radial da petala: 1 = circulo (umebachi); >1 da direcao "para fora"
    widthFrac  = 0.60    # largura real do simbolo / lado (folga dentro do squircle e do recorte do Watch)
    holeMargin = 5       # miolo vazado = ponta interna da lente + margem (contorno circular limpo, sem farpas)
    optical    = 0.75    # 0 = centroide no centro da tela; 1 = caixa envolvente no centro
}
$Palettes = [ordered]@{
    default = @{ bgTop='#3E5F7E'; bgBot='#2C4763'; slipIn='#EEEBE2'; slipOut='#F8F7F2'; lens='#A8B8C6'; halo='#F6ECDC'; haloA=0 }
    dark    = @{ bgTop='#17202B'; bgBot='#10171F'; slipIn='#D8D7CF'; slipOut='#E7E6DF'; lens='#8D9DAB'; halo='#000000'; haloA=0 }
    tinted  = @{ bgTop='#000000'; bgBot='#000000'; slipIn='#D2D2D2'; slipOut='#EAEAEA'; lens='#9C9C9C'; halo='#000000'; haloA=0 }
}

# ---------------- utilitarios ----------------
function New-Color([string]$hex, [int]$a = 255) {
    $h = $hex.TrimStart('#')
    [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16))
}
function Get-Luminance([string]$hex) {
    $h = $hex.TrimStart('#')
    $ch = 0..2 | ForEach-Object {
        $v = [Convert]::ToInt32($h.Substring($_*2,2),16) / 255.0
        if ($v -le 0.04045) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) }
    }
    0.2126*$ch[0] + 0.7152*$ch[1] + 0.0722*$ch[2]
}
function Get-Contrast([string]$a, [string]$b) {
    $la = Get-Luminance $a; $lb = Get-Luminance $b
    ([math]::Max($la,$lb) + 0.05) / ([math]::Min($la,$lb) + 0.05)
}
function Get-Hex([System.Drawing.Color]$c) { '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B }
function Resize-Image([System.Drawing.Image]$src, [int]$size) {
    $dst = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $gr = [System.Drawing.Graphics]::FromImage($dst)
    $gr.InterpolationMode = 'HighQualityBicubic'; $gr.PixelOffsetMode = 'HighQuality'; $gr.CompositingQuality = 'HighQuality'
    $ia = New-Object System.Drawing.Imaging.ImageAttributes
    $ia.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)   # evita escurecer a borda na reducao
    $gr.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $size, $size), 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    $gr.Dispose(); $ia.Dispose()
    return $dst
}

# petala i (0 = topo, sentido horario a cada 72 graus): elipse com semi-eixo radial rr e tangencial rt
function New-Petal([double]$cx, [double]$cy, [double]$d, [double]$rr, [double]$rt, [int]$i) {
    $deg = -90 + 72 * $i
    $a = $deg * [math]::PI / 180
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddEllipse([single](-$rr), [single](-$rt), [single](2*$rr), [single](2*$rt))
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate([single]($cx + $d*[math]::Cos($a)), [single]($cy + $d*[math]::Sin($a)))
    $m.Rotate([single]$deg)
    $gp.Transform($m); $m.Dispose()
    return $gp
}
function Test-InPetal([double]$x, [double]$y, [double]$rr, [double]$rt, [int]$i) {
    # em d = 1, centro da flor na origem
    $a = (-90 + 72 * $i) * [math]::PI / 180
    $dx = $x - [math]::Cos($a); $dy = $y - [math]::Sin($a)
    $u = $dx*[math]::Cos($a) + $dy*[math]::Sin($a)
    $v = -$dx*[math]::Sin($a) + $dy*[math]::Cos($a)
    return (($u/$rr)*($u/$rr) + ($v/$rt)*($v/$rt)) -le 1
}
# resolve a geometria em px: escala pela largura real (amostrando as elipses), ponta interna da lente,
# centro optico e raio externo
function Solve-Geometry([hashtable]$S) {
    $rt1 = $S.k; $rr1 = $S.k * $S.elong
    $minX = 1e9; $maxX = -1e9; $minY = 1e9; $maxY = -1e9; $maxR = 0
    for ($i = 0; $i -lt 5; $i++) {
        $a = (-90 + 72 * $i) * [math]::PI / 180
        for ($s0 = 0; $s0 -lt 1440; $s0++) {
            $t = $s0 * [math]::PI / 720
            $u = $rr1*[math]::Cos($t); $w = $rt1*[math]::Sin($t)
            $x = [math]::Cos($a) + $u*[math]::Cos($a) - $w*[math]::Sin($a)
            $y = [math]::Sin($a) + $u*[math]::Sin($a) + $w*[math]::Cos($a)
            if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
            $rad = [math]::Sqrt($x*$x + $y*$y); if ($rad -gt $maxR) { $maxR = $rad }
        }
    }
    $scale = $S.widthFrac * 1024 / ($maxX - $minX)
    # ponta interna da lente (petalas 0 e 1) fica na bissetriz, a -54 graus
    $bis = -54 * [math]::PI / 180; $tipIn = 0; $tipOut = 0
    for ($t = 0.0; $t -lt 2.5; $t += 0.0002) {
        $inside = Test-InPetal ($t*[math]::Cos($bis)) ($t*[math]::Sin($bis)) $rr1 $rt1 0
        if ($inside -and $tipIn -eq 0) { $tipIn = $t }
        if ((-not $inside) -and $tipIn -gt 0) { $tipOut = $t; break }
    }
    # nao vizinhas nao podem se tocar (sem sobreposicao tripla, sem estrela no centro)
    $nonNeighbor = 2 * [math]::Sin(72 * [math]::PI / 180)
    $bboxC = ($minY + $maxY) / 2 * $scale
    [pscustomobject]@{
        d = $scale; rr = $rr1*$scale; rt = $rt1*$scale
        tipIn = $tipIn*$scale; tipOut = $tipOut*$scale
        hole = $tipIn*$scale + $S.holeMargin
        cy = 512 - $S.optical*$bboxC
        width = ($maxX - $minX)*$scale; height = ($maxY - $minY)*$scale
        top = $minY*$scale; bottom = $maxY*$scale; outerR = $maxR*$scale
        nonNeighborGap = ($nonNeighbor - 2*$rr1) * $scale   # folga aproximada (pior caso, eixo radial)
    }
}

function Render-Icon($Geom, [hashtable]$Pal) {
    $SS = 4; $N = 1024 * $SS          # supersampling 4x
    $big = New-Object System.Drawing.Bitmap $N, $N, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $gr = [System.Drawing.Graphics]::FromImage($big)
    $gr.SmoothingMode = 'AntiAlias'; $gr.CompositingQuality = 'HighQuality'; $gr.PixelOffsetMode = 'HighQuality'
    $gr.ScaleTransform($SS, $SS)
    $full = New-Object System.Drawing.RectangleF 0, 0, 1024, 1024
    $cx = 512.0; $cy = [double]$Geom.cy

    # 1. barro: degrade vertical suave (bege-caramelo no alto, couro embaixo)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $full, (New-Color $Pal.bgTop), (New-Color $Pal.bgBot), 90
    $gr.FillRectangle($bg, $full); $bg.Dispose()

    # 1b. halo quente opcional atras da flor (desligado por padrao: haloA = 0)
    if ($Pal.haloA -gt 0) {
        $hr = $Geom.outerR * 1.35
        $hp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $hp.AddEllipse([single]($cx-$hr), [single]($cy-$hr), [single](2*$hr), [single](2*$hr))
        $hb = New-Object System.Drawing.Drawing2D.PathGradientBrush $hp
        $hb.CenterPoint = New-Object System.Drawing.PointF ([single]$cx), ([single]$cy)
        $hb.CenterColor = New-Color $Pal.halo $Pal.haloA
        $hb.SurroundColors = [System.Drawing.Color[]]@(New-Color $Pal.halo 0)
        $gr.FillPath($hb, $hp); $hb.Dispose(); $hp.Dispose()
    }

    $petals = @(); for ($i = 0; $i -lt 5; $i++) { $petals += ,(New-Petal $cx $cy $Geom.d $Geom.rr $Geom.rt $i) }
    $hole = New-Object System.Drawing.Drawing2D.GraphicsPath
    $hole.AddEllipse([single]($cx-$Geom.hole), [single]($cy-$Geom.hole), [single](2*$Geom.hole), [single](2*$Geom.hole))

    # 2. engobe creme: degrade radial quase imperceptivel, mais quente no centro e mais claro nas pontas
    $R = $Geom.outerR + 2
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddEllipse([single]($cx-$R), [single]($cy-$R), [single](2*$R), [single](2*$R))
    $slip = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp
    $slip.CenterPoint = New-Object System.Drawing.PointF ([single]$cx), ([single]$cy)
    $slip.CenterColor = New-Color $Pal.slipIn
    $slip.SurroundColors = [System.Drawing.Color[]]@(New-Color $Pal.slipOut)
    $gr.SetClip($hole, [System.Drawing.Drawing2D.CombineMode]::Exclude)
    foreach ($p in $petals) { $gr.FillPath($slip, $p) }

    # 3. lentes: so vizinhas se cruzam; a camada dupla de engobe fica mais densa
    $lens = New-Object System.Drawing.SolidBrush (New-Color $Pal.lens)
    for ($i = 0; $i -lt 5; $i++) {
        $gr.SetClip($petals[$i], [System.Drawing.Drawing2D.CombineMode]::Replace)
        $gr.SetClip($petals[($i + 1) % 5], [System.Drawing.Drawing2D.CombineMode]::Intersect)
        $gr.SetClip($hole, [System.Drawing.Drawing2D.CombineMode]::Exclude)
        $gr.FillRectangle($lens, $full)
    }
    $gr.ResetClip()
    $gr.Dispose(); $slip.Dispose(); $lens.Dispose(); $gp.Dispose(); $hole.Dispose()
    foreach ($p in $petals) { $p.Dispose() }
    $img = Resize-Image $big 1024
    $big.Dispose()
    return $img
}

function New-RoundedRect([single]$x, [single]$y, [single]$s, [single]$rad) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $dd = 2 * $rad
    $p.AddArc($x, $y, $dd, $dd, 180, 90); $p.AddArc($x + $s - $dd, $y, $dd, $dd, 270, 90)
    $p.AddArc($x + $s - $dd, $y + $s - $dd, $dd, $dd, 0, 90); $p.AddArc($x, $y + $s - $dd, $dd, $dd, 90, 90)
    $p.CloseFigure(); return $p
}
function Draw-Masked($gr, $img, [single]$x, [single]$y, [bool]$circle) {
    $tb = New-Object System.Drawing.TextureBrush $img, ([System.Drawing.Drawing2D.WrapMode]::Clamp)
    $tb.TranslateTransform($x, $y)
    $s = [single]$img.Width
    if ($circle) { $gr.FillEllipse($tb, $x, $y, $s, $s) }
    else { $rr = New-RoundedRect $x $y $s ([single](0.2237 * $s)); $gr.FillPath($tb, $rr); $rr.Dispose() }
    $tb.Dispose()
}
function Get-Pixel($img, [int]$x, [int]$y) { Get-Hex ($img.GetPixel($x, $y)) }

# ---------------- render ----------------
$Geom = Solve-Geometry $Shape
$icons = [ordered]@{}
foreach ($name in $Palettes.Keys) { $icons[$name] = Render-Icon $Geom $Palettes[$name] }
$icons.default.Save("$out\AppIcon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$icons.dark.Save("$out\AppIcon-dark.png", [System.Drawing.Imaging.ImageFormat]::Png)
$icons.tinted.Save("$out\AppIcon-tinted.png", [System.Drawing.Imaging.ImageFormat]::Png)
$i120 = Resize-Image $icons.default 120
$i120.Save("$out\AppIcon-120.png", [System.Drawing.Imaging.ImageFormat]::Png)
$i60 = Resize-Image $icons.default 60
$i40 = Resize-Image $icons.default 40

# ---------------- previa de tela inicial 360x360 ----------------
# metade esquerda: papel de parede claro #F2F2F7; direita: escuro #1C1C1E.
# Em cada metade: 120 px (tela inicial, raio 22%), 40 px (Ajustes/Spotlight) e 60 px em circulo (Watch).
$pv = New-Object System.Drawing.Bitmap 360, 360, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gv = [System.Drawing.Graphics]::FromImage($pv)
$gv.SmoothingMode = 'AntiAlias'; $gv.PixelOffsetMode = 'HighQuality'; $gv.CompositingQuality = 'HighQuality'
$gv.FillRectangle((New-Object System.Drawing.SolidBrush (New-Color '#F2F2F7')), 0, 0, 180, 360)
$gv.FillRectangle((New-Object System.Drawing.SolidBrush (New-Color '#1C1C1E')), 180, 0, 180, 360)
foreach ($ox in 0, 180) {
    Draw-Masked $gv $i120 ($ox + 30) 36 $false
    Draw-Masked $gv $i40  ($ox + 30) 226 $false
    Draw-Masked $gv $i60  ($ox + 90) 216 $true
}
$gv.Dispose()
$pv.Save("$out\AppIcon-preview.png", [System.Drawing.Imaging.ImageFormat]::Png)

# ---------------- checagens: aparencias + recorte circular do Watch sobre o 1024 ----------------
$ck = New-Object System.Drawing.Bitmap 860, 300, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gc = [System.Drawing.Graphics]::FromImage($ck)
$gc.SmoothingMode = 'AntiAlias'; $gc.PixelOffsetMode = 'HighQuality'
$gc.FillRectangle((New-Object System.Drawing.SolidBrush (New-Color '#1C1C1E')), 0, 0, 860, 300)
$x = 20
foreach ($name in $icons.Keys) {
    $sm = Resize-Image $icons[$name] 180
    Draw-Masked $gc $sm $x 60 $false
    $sm.Dispose(); $x += 200
}
$w = Resize-Image $icons.default 240
Draw-Masked $gc $w 610 30 $true           # Watch: o sistema recorta em circulo o quadrado inteiro
$gc.DrawEllipse((New-Object System.Drawing.Pen (New-Color '#FFFFFF' 60), 1), 610 + 120 - 0.72*120, 30 + 120 - 0.72*120, 1.44*120, 1.44*120)
$w.Dispose(); $gc.Dispose()
$ck.Save("$out\AppIcon-checks.png", [System.Drawing.Imaging.ImageFormat]::Png)

# ---------------- relatorio ----------------
$P = $Palettes.default
"geometria: d={0:N1} rr={1:N1} rt={2:N1} miolo={3:N1} (ponta interna da lente {4:N1}; externa {5:N1}) cy={6:N1}" -f $Geom.d, $Geom.rr, $Geom.rt, $Geom.hole, $Geom.tipIn, $Geom.tipOut, $Geom.cy
"simbolo: {0:N0} x {1:N0} px ({2:P1} x {3:P1}); topo y={4:N0}, base y={5:N0}; raio externo {6:N0} px (recorte do Watch: 512)" -f $Geom.width, $Geom.height, ($Geom.width/1024), ($Geom.height/1024), ($Geom.cy + $Geom.top), ($Geom.cy + $Geom.bottom), $Geom.outerR
"lente: largura {0:N1} px, comprimento {1:N1} px; folga entre nao vizinhas >= {2:N1} px" -f (2*$Geom.rt - 2*$Geom.d*[math]::Sin(36*[math]::PI/180)), ($Geom.tipOut - $Geom.tipIn), $Geom.nonNeighborGap
$img = $icons.default
$yTop = [int]($Geom.cy + $Geom.top + 6); $yBot = [int]($Geom.cy + $Geom.bottom - 6)
$bgTopPx = Get-Pixel $img 512 ([int]($Geom.cy + $Geom.top - 4)); $petTopPx = Get-Pixel $img 512 $yTop
"contraste medido na ponta de cima: petala {0} x fundo {1} = {2:N2}:1" -f $petTopPx, $bgTopPx, (Get-Contrast $petTopPx $bgTopPx)
$lx = [int](512 + ($Geom.tipIn + $Geom.tipOut)/2 * [math]::Cos(-54*[math]::PI/180)); $ly = [int]($Geom.cy + ($Geom.tipIn + $Geom.tipOut)/2 * [math]::Sin(-54*[math]::PI/180))
$lensPx = Get-Pixel $img $lx $ly
$nearPx = Get-Pixel $img 512 ([int]($Geom.cy - $Geom.d))
"contraste lente {0} x petala {1} = {2:N2}:1; lente x fundo(topo) = {3:N2}:1" -f $lensPx, $nearPx, (Get-Contrast $lensPx $nearPx), (Get-Contrast $lensPx $bgTopPx)
$corePx = Get-Pixel $img 512 ([int]$Geom.cy)
"miolo {0} x petala perto do centro {1} = {2:N2}:1" -f $corePx, (Get-Pixel $img 512 ([int]($Geom.cy - $Geom.hole - 6))), (Get-Contrast $corePx (Get-Pixel $img 512 ([int]($Geom.cy - $Geom.hole - 6))))
$edge = Get-Pixel $img 512 60
"bloco (borda alta {0}, media {1}) x papel claro #F2F2F7 = {2:N2} / {3:N2}; x escuro #1C1C1E = {4:N2} / {5:N2}" -f $edge, (Get-Pixel $img 60 512), (Get-Contrast $edge '#F2F2F7'), (Get-Contrast (Get-Pixel $img 60 512) '#F2F2F7'), (Get-Contrast $edge '#1C1C1E'), (Get-Contrast (Get-Pixel $img 60 512) '#1C1C1E')
$D = $Palettes.dark
"escura: petala x fundo = {0:N2}:1; lente x petala = {1:N2}:1" -f (Get-Contrast $D.slipIn $D.bgTop), (Get-Contrast $D.lens $D.slipIn)
foreach ($k in @($icons.Keys)) { $icons[$k].Dispose() }
$i120.Dispose(); $i60.Dispose(); $i40.Dispose(); $pv.Dispose(); $ck.Dispose()
"ok"
