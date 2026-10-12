$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$in = $args[0]; $out = $args[1]
$fs = [System.IO.File]::OpenRead($in)
$br = New-Object System.IO.BinaryReader($fs)
$tokens = @()
$tok = ''
while ($tokens.Count -lt 4) {
  $b = $br.ReadByte()
  $c = [char]$b
  if ($c -eq '#') { while (($ch = [char]$br.ReadByte()) -ne "`n") {} ; continue }
  if ($c -match '\s') { if ($tok -ne '') { $tokens += $tok; $tok = '' }; continue }
  $tok += $c
}
$tokens += $tok
$w = [int]$tokens[1]; $h = [int]$tokens[2]
$px = $br.ReadBytes($w * $h)
$br.Close(); $fs.Close()
$stride = [int]([Math]::Ceiling($w * 3 / 4) * 4)
$pad = $stride - $w * 3
$bw = New-Object System.IO.BinaryWriter([System.IO.File]::Create($out))
$fsLen = 14 + 40 + $stride * $h
foreach ($v in @(0x42,0x4D)) { $bw.Write([byte]$v) }
$bw.Write([int]$fsLen); $bw.Write([int]0); $bw.Write([int]54)
$bw.Write([int]40); $bw.Write([int]$w); $bw.Write([int]$h)
$bw.Write([System.Int16]1); $bw.Write([System.Int16]24); $bw.Write([int]0)
$bw.Write([int]($stride * $h)); $bw.Write([int]2835); $bw.Write([int]2835)
$bw.Write([int]0); $bw.Write([int]0)
for ($y = $h - 1; $y -ge 0; $y--) {
  for ($x = 0; $x -lt $w; $x++) {
    $g = $px[$y * $w + $x]
    $bw.Write([byte]$g); $bw.Write([byte]$g); $bw.Write([byte]$g)
  }
  for ($p = 0; $p -lt $pad; $p++) { $bw.Write([byte]0) }
}
$bw.Close()
Write-Host ("bmp ok " + $w + "x" + $h)
