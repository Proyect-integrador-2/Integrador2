# Contrasena nueva para cuentas del dominio ip2.local (IP2-79).
#
# El cambio obligatorio en el primer inicio de sesion no funciona en este diseno: mientras
# la cuenta tiene "debe cambiar la contrasena", el dominio rechaza la validacion por LDAP que
# usan Proxmox, Zabbix, Grafana y el SSH de las VM Linux. Este script le pone a cada cuenta
# una contrasena aleatoria de 16 caracteres, sin esa marca, y la desbloquea.
#
# Las contrasenas no se muestran: quedan en C:\ip2\secretos\claves-integrantes.txt (solo
# administradores). Quien administra las lee una por una y las entrega por privado:
#   ssh Administrator@10.10.30.17 "findstr <usuario> C:\ip2\secretos\claves-integrantes.txt"
#
#   powershell -File nueva-clave.ps1 alexander.jimenez angel.gallardo ...
param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Usuarios)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$archivo = 'C:\ip2\secretos\claves-integrantes.txt'
# Sin caracteres que se confunden al leerlos (I l 1 O 0) ni comillas.
$mayus = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; $minus = 'abcdefghijkmnopqrstuvwxyz'
$digitos = '23456789'; $simbolos = '#%+=?@!*'
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
function Azar([int]$n) { $b = New-Object byte[] 4; $rng.GetBytes($b); [BitConverter]::ToUInt32($b, 0) % $n }
function Clave {
    $todos = $mayus + $minus + $digitos + $simbolos
    $c = @($mayus[(Azar $mayus.Length)], $minus[(Azar $minus.Length)],
           $digitos[(Azar $digitos.Length)], $simbolos[(Azar $simbolos.Length)])
    while ($c.Count -lt 16) { $c += $todos[(Azar $todos.Length)] }
    # Mezcla para que los cuatro obligatorios no queden siempre al principio.
    for ($i = $c.Count - 1; $i -gt 0; $i--) { $j = Azar ($i + 1); $t = $c[$i]; $c[$i] = $c[$j]; $c[$j] = $t }
    -join $c
}

$lineas = @{}
if (Test-Path $archivo) {
    foreach ($l in Get-Content $archivo) { if ($l -match '^(\S+)\s') { $lineas[$Matches[1]] = $l } }
}
foreach ($u in $Usuarios) {
    $cuenta = Get-ADUser $u
    $clave = Clave
    Set-ADAccountPassword $cuenta -Reset -NewPassword (ConvertTo-SecureString $clave -AsPlainText -Force)
    Set-ADUser $cuenta -ChangePasswordAtLogon $false
    Unlock-ADAccount $cuenta
    $lineas[$u] = "$u  $clave  (puesta el $(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    Write-Host "$u : contrasena nueva puesta"
}
Remove-Variable clave -ErrorAction SilentlyContinue
$lineas.Values | Sort-Object | Set-Content -Path $archivo -Encoding ASCII
# Solo administradores y SYSTEM pueden leer el archivo.
icacls $archivo /inheritance:r /grant:r 'Administrators:F' 'SYSTEM:F' | Out-Null
Write-Host "Guardadas en $archivo"
