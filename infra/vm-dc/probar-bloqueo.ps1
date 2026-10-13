# Prueba la politica de bloqueo del dominio con una cuenta de prueba (IP2-80).
#
# Crea la cuenta prueba.bloqueo, falla el inicio de sesion seis veces a proposito,
# comprueba que el dominio la bloqueo al quinto intento y que quedaron los eventos de
# seguridad (4625 inicio fallido en este equipo, 4771 fallo de Kerberos, 4740 cuenta
# bloqueada), y la borra.
#
# Se corre en vm-dc como Administrator:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\probar-bloqueo.ps1
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

$Cuenta = 'prueba.bloqueo'
$inicio = Get-Date

# Contrasena valida al azar; no se usa para entrar, solo para crear la cuenta.
$bytes = New-Object byte[] 18
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$clave = 'Ip2' + [Convert]::ToBase64String($bytes).Replace('+', 'x').Replace('/', 'y')

Get-ADUser -Filter "SamAccountName -eq '$Cuenta'" | Remove-ADUser -Confirm:$false
New-ADUser -Name $Cuenta -SamAccountName $Cuenta -Path 'OU=Usuarios,OU=IP2,DC=ip2,DC=local' `
  -AccountPassword (ConvertTo-SecureString $clave -AsPlainText -Force) -Enabled $true

# La politica rechaza una contrasena corta: se intenta poner una de 8 caracteres.
try {
  Set-ADAccountPassword $Cuenta -Reset -NewPassword (ConvertTo-SecureString 'Corta123' -AsPlainText -Force)
  Write-Output 'Contrasena de 8 caracteres: ACEPTADA (la politica no se aplico)'
} catch {
  Write-Output 'Contrasena de 8 caracteres: rechazada por la politica'
}

$dominio = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', 'ip2.local')
foreach ($intento in 1..6) {
  $entro = $dominio.ValidateCredentials($Cuenta, "Incorrecta-$intento")
  $bloqueada = (Get-ADUser $Cuenta -Properties LockedOut).LockedOut
  Write-Output ("Intento {0} con contrasena incorrecta: entro={1}  cuenta bloqueada={2}" -f $intento, $entro, $bloqueada)
}

# Ya bloqueada, ni la contrasena correcta entra.
Write-Output ("Con la contrasena correcta, estando bloqueada: entro={0}" -f $dominio.ValidateCredentials($Cuenta, $clave))

Start-Sleep -Seconds 3
foreach ($id in 4740, 4771, 4776, 4625) {
  $eventos = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = $id; StartTime = $inicio } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match $Cuenta })
  Write-Output ("Eventos {0} de la cuenta: {1}" -f $id, $eventos.Count)
}

Remove-ADUser $Cuenta -Confirm:$false
Write-Output 'Cuenta de prueba borrada.'
