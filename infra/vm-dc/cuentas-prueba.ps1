# Crea las cuentas de prueba del acceso por grupos (IP2-83, prueba PR-13).
#
#   prueba.admin      en GG-IP2-Administradores: debe poder administrar
#   prueba.operador   en GG-IP2-Operadores: debe poder solo ver
#   prueba.singrupo   sin grupo del proyecto: debe ser rechazada en todas las herramientas
#
# Las contrasenas son aleatorias y quedan en C:\ip2\secretos\cuentas-prueba.txt, que solo
# leen los administradores; las pruebas las toman de ahi sin mostrarlas. Estas cuentas no
# son de nadie: se borran al terminar el proyecto. Se corre como Administrator; se puede repetir.
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$Unidad = 'OU=Usuarios,OU=IP2,DC=ip2,DC=local'
$Archivo = 'C:\ip2\secretos\cuentas-prueba.txt'
$Cuentas = [ordered]@{
  'prueba.admin'    = 'GG-IP2-Administradores'
  'prueba.operador' = 'GG-IP2-Operadores'
  'prueba.singrupo' = ''
}

function Nueva-Clave {
  $letras = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
  $bytes = New-Object byte[] 21
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  'Ip2' + -join ($bytes | ForEach-Object { $letras[$_ % $letras.Length] })
}

$guardadas = @{}
if (Test-Path $Archivo) {
  Get-Content $Archivo | ForEach-Object { $c, $k = $_ -split ' ', 2; $guardadas[$c] = $k }
}

foreach ($cuenta in $Cuentas.Keys) {
  if (-not (Get-ADUser -Filter "SamAccountName -eq '$cuenta'")) {
    $clave = Nueva-Clave
    New-ADUser -Name $cuenta -SamAccountName $cuenta -UserPrincipalName "$cuenta@ip2.local" -Path $Unidad `
      -GivenName 'Prueba' -Surname ($cuenta -replace '^prueba\.', '') -Description 'Cuenta de prueba PR-13 (IP2-83)' `
      -AccountPassword (ConvertTo-SecureString $clave -AsPlainText -Force) -Enabled $true -PasswordNeverExpires $true
    $guardadas[$cuenta] = $clave
    Write-Output "creada $cuenta"
  }
  $grupo = $Cuentas[$cuenta]
  if ($grupo -and (Get-ADGroupMember $grupo).SamAccountName -notcontains $cuenta) {
    Add-ADGroupMember -Identity $grupo -Members $cuenta
  }
}
$guardadas.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Value)" } | Set-Content $Archivo -Encoding ascii
Write-Output 'Cuentas de prueba listas:'
foreach ($cuenta in $Cuentas.Keys) {
  $grupos = (Get-ADPrincipalGroupMembership $cuenta | Where-Object Name -like 'GG-IP2-*').Name -join ', '
  Write-Output ("  {0,-16} {1}" -f $cuenta, $(if ($grupos) { $grupos } else { '(sin grupo del proyecto)' }))
}
