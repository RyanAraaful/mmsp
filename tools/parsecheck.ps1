$ErrorActionPreference = 'Stop'
$errs = $null
[void][System.Management.Automation.PSParser]::Tokenize((Get-Content $args[0] -Raw), [ref]$errs)
Write-Host ("errors=" + $errs.Count)
foreach ($e in $errs) { Write-Host ($e.Token.StartLine.ToString() + ': ' + $e.Message) }
