param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$netDir = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
$wpfDir = Join-Path $netDir "WPF"
$csc = Join-Path $netDir "csc.exe"

if (-not (Test-Path $csc)) {
    throw "未找到 C# 编译器: $csc"
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $root "Program.cs"
$manifest = Join-Path $root "app.manifest"
$iconPath = Join-Path $root "app.ico"

# Generate multi-size crisp app.ico if missing
if (-not (Test-Path $iconPath)) {
    Add-Type -AssemblyName System.Drawing
    $sizes = @(16, 32, 48, 256)
    $pngList = New-Object System.Collections.Generic.List[byte[]]

    foreach ($sz in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($sz, $sz)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)

        $pad = [float]($sz * 0.06)
        $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 22, 27, 38))
        $ringWidth = [Math]::Max(1.5, [float]($sz * 0.085))
        $ringPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 52, 211, 153), $ringWidth)
        $dotBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 52, 211, 153))

        $g.FillEllipse($bgBrush, $pad, $pad, $sz - 2 * $pad, $sz - 2 * $pad)
        $ringPad = $pad + $ringWidth * 0.6
        $g.DrawEllipse($ringPen, $ringPad, $ringPad, $sz - 2 * $ringPad, $sz - 2 * $ringPad)
        $dotSize = [float]($sz * 0.34)
        $dotOffset = ($sz - $dotSize) / 2.0
        $g.FillEllipse($dotBrush, $dotOffset, $dotOffset, $dotSize, $dotSize)

        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngList.Add($ms.ToArray())

        $ms.Dispose()
        $bgBrush.Dispose()
        $ringPen.Dispose()
        $dotBrush.Dispose()
        $g.Dispose()
        $bmp.Dispose()
    }

    $fs = [System.IO.File]::Create($iconPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    # ICONDIR header
    $bw.Write([uint16]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]$sizes.Count)

    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $sz = $sizes[$i]
        $data = $pngList[$i]
        $bSz = if ($sz -ge 256) { [byte]0 } else { [byte]$sz }
        $bw.Write($bSz)         # width
        $bw.Write($bSz)         # height
        $bw.Write([byte]0)      # color count
        $bw.Write([byte]0)      # reserved
        $bw.Write([uint16]1)    # planes
        $bw.Write([uint16]32)   # bpp
        $bw.Write([uint32]$data.Length)
        $bw.Write([uint32]$offset)
        $offset += $data.Length
    }
    foreach ($data in $pngList) {
        $bw.Write($data)
    }
    $bw.Flush()
    $bw.Dispose()
    $fs.Dispose()
}

if ($Release) {
    $releaseDir = Join-Path $root "release"
    if (-not (Test-Path $releaseDir)) {
        New-Item -ItemType Directory -Path $releaseDir | Out-Null
    }
    $outExe = Join-Path $releaseDir "LatencyMonitor.exe"
} else {
    $outExe = Join-Path $root "LatencyMonitor.exe"
}

$argsList = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/debug-",
    "/utf8output",
    "/codepage:65001",
    "/win32manifest:$manifest",
    "/win32icon:$iconPath",
    "/out:$outExe",
    "/reference:$(Join-Path $wpfDir 'PresentationCore.dll')",
    "/reference:$(Join-Path $wpfDir 'PresentationFramework.dll')",
    "/reference:$(Join-Path $wpfDir 'WindowsBase.dll')",
    "/reference:$(Join-Path $netDir 'System.Xaml.dll')",
    "/reference:$(Join-Path $netDir 'System.Windows.Forms.dll')",
    "/reference:$(Join-Path $netDir 'System.Drawing.dll')",
    "/reference:$(Join-Path $netDir 'System.Web.Extensions.dll')",
    $src
)

Write-Host "正在编译 $outExe ..." -ForegroundColor Cyan
& $csc @argsList

if ($LASTEXITCODE -ne 0) {
    throw "编译失败，退出码: $LASTEXITCODE"
}

Write-Host "编译成功: $outExe" -ForegroundColor Green
