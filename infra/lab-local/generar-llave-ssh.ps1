# Genera la llave SSH que n8n usa para entrar a vm-app-sim como n8n-ops.
# Queda en secrets/ (ignorado por Git). La privada se pega en la credencial SSH de n8n.
$dir = Join-Path $PSScriptRoot 'secrets'
New-Item -ItemType Directory -Force $dir | Out-Null
$llave = Join-Path $dir 'n8n_ops_ed25519'
if (Test-Path $llave) {
    Write-Host "Ya existe $llave (no se sobrescribe)."
} else {
    ssh-keygen -t ed25519 -N '""' -C 'n8n-ops@integrador2' -f $llave | Out-Null
    Write-Host "Llave creada: $llave y $llave.pub"
}
# OpenSSH de Linux no lee llaves con fin de línea de Windows (CRLF): se normalizan a LF.
foreach ($f in @($llave, "$llave.pub")) {
    $texto = [IO.File]::ReadAllText($f)
    if ($texto.Contains("`r")) { [IO.File]::WriteAllText($f, $texto.Replace("`r`n", "`n")); Write-Host "Normalizado a LF: $f" }
}
