# Deja el dominio ip2.local como en el diseno (IP2-79, IP2-80).
#
#   1. DNS: lo que no es del dominio se reenvia a los DNS de la universidad.
#   2. Unidades organizativas, grupos y cuentas del equipo.
#   3. Politica de contrasenas y bloqueo, en la GPO "Default Domain Policy".
#   4. Auditoria de inicios de sesion, que alimenta el monitoreo de seguridad.
#
# Se corre en vm-dc como Administrator, despues de promover-dominio.ps1. Se puede repetir:
# lo que ya existe no se toca.
#
# Las cuentas nacen con una contrasena temporal aleatoria que hay que cambiar en el
# primer inicio de sesion. Quedan en C:\ip2\secretos\cuentas-iniciales.txt, que solo
# leen los administradores; ese archivo se borra cuando cada persona cambio la suya.
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$Base = 'DC=ip2,DC=local'
$Raiz = "OU=IP2,$Base"
$Reenviadores = @('10.100.8.2', '10.100.8.3', '1.1.1.1')
$Secretos = 'C:\ip2\secretos'

# Sin tildes en los datos: asi el script no depende de la codificacion del archivo.
$Personas = @(
  @{ Cuenta = 'stiff.aleman';      Nombre = 'Stiff';     Apellido = 'Aleman';   Grupo = 'GG-IP2-Administradores' }
  @{ Cuenta = 'alexander.jimenez'; Nombre = 'Alexander'; Apellido = 'Jimenez';  Grupo = 'GG-IP2-Administradores' }
  @{ Cuenta = 'angel.gallardo';    Nombre = 'Angel';     Apellido = 'Gallardo'; Grupo = 'GG-IP2-Administradores' }
  @{ Cuenta = 'jeffrey.herrera';   Nombre = 'Jeffrey';   Apellido = 'Herrera';  Grupo = 'GG-IP2-Operadores' }
  @{ Cuenta = 'alvaro.alvarez';    Nombre = 'Alvaro';    Apellido = 'Alvarez';  Grupo = 'GG-IP2-Operadores' }
)

function Nueva-Clave {
  # 20 letras y numeros, con mayuscula, minuscula y numero asegurados.
  $letras = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
  $bytes = New-Object byte[] 17
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  'Ip2' + -join ($bytes | ForEach-Object { $letras[$_ % $letras.Length] })
}

function Guardar-Clave($cuenta, $clave) {
  Add-Content -Path "$Secretos\cuentas-iniciales.txt" -Value "$cuenta $clave"
}

# Carpeta de secretos: solo Administrators y SYSTEM (por SID).
if (-not (Test-Path $Secretos)) {
  New-Item -ItemType Directory -Force $Secretos | Out-Null
  icacls $Secretos /inheritance:r /grant '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
}

# ---------------------------------------------------------------------------
Write-Output '== 1. DNS =='
Set-DnsServerForwarder -IPAddress $Reenviadores
$tarjeta = Get-NetAdapter -Physical | Sort-Object ifIndex | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $tarjeta.ifIndex -ServerAddresses '127.0.0.1'
Write-Output ("  reenviadores: " + ((Get-DnsServerForwarder).IPAddress -join ', '))

# ---------------------------------------------------------------------------
Write-Output '== 2. Unidades, grupos y cuentas =='
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'IP2'" -SearchBase $Base -SearchScope OneLevel)) {
  New-ADOrganizationalUnit -Name 'IP2' -Path $Base
}
foreach ($unidad in 'Usuarios', 'Servicios', 'Equipos') {
  if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$unidad'" -SearchBase $Raiz -SearchScope OneLevel)) {
    New-ADOrganizationalUnit -Name $unidad -Path $Raiz
  }
}

$Grupos = @{
  'GG-IP2-Administradores' = 'Acceso total a la plataforma: Proxmox, servidor Windows, SSH y edicion en Zabbix y Grafana'
  'GG-IP2-Operadores'      = 'Solo lectura en Zabbix y Grafana'
}
foreach ($grupo in $Grupos.Keys) {
  if (-not (Get-ADGroup -Filter "Name -eq '$grupo'")) {
    New-ADGroup -Name $grupo -GroupScope Global -GroupCategory Security -Path $Raiz -Description $Grupos[$grupo]
  }
}

foreach ($persona in $Personas) {
  $cuenta = $persona.Cuenta
  if (-not (Get-ADUser -Filter "SamAccountName -eq '$cuenta'")) {
    $clave = Nueva-Clave
    New-ADUser -Name ($persona.Nombre + ' ' + $persona.Apellido) -GivenName $persona.Nombre -Surname $persona.Apellido `
      -SamAccountName $cuenta -UserPrincipalName "$cuenta@ip2.local" -Path "OU=Usuarios,$Raiz" `
      -AccountPassword (ConvertTo-SecureString $clave -AsPlainText -Force) -Enabled $true -ChangePasswordAtLogon $true
    Guardar-Clave $cuenta $clave
    Write-Output "  creada $cuenta"
  }
  if ((Get-ADGroupMember -Identity $persona.Grupo).SamAccountName -notcontains $cuenta) {
    Add-ADGroupMember -Identity $persona.Grupo -Members $cuenta
  }
}

# Cuenta de servicio: solo lee el directorio. La usan Zabbix, Grafana y Proxmox.
if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc-ldap'")) {
  $clave = Nueva-Clave
  New-ADUser -Name 'svc-ldap' -SamAccountName 'svc-ldap' -UserPrincipalName 'svc-ldap@ip2.local' `
    -Path "OU=Servicios,$Raiz" -Description 'Consultas LDAP de Zabbix, Grafana y Proxmox (solo lectura)' `
    -AccountPassword (ConvertTo-SecureString $clave -AsPlainText -Force) -Enabled $true `
    -PasswordNeverExpires $true -CannotChangePassword $true
  Set-Content -Path "$Secretos\svc-ldap.txt" -Value $clave
  Write-Output '  creada svc-ldap'
}

# ---------------------------------------------------------------------------
Write-Output '== 3. Politica de contrasenas y bloqueo (RNF-09) =='
# Se escribe en la GPO, no solo en el dominio: el controlador vuelve a aplicar la GPO
# cada 16 horas y pisaria un cambio hecho por fuera de ella.
$Gpo = '{31B2F340-016D-11D2-945F-00C04FB984F9}'   # Default Domain Policy
$Carpeta = "C:\Windows\SYSVOL\sysvol\ip2.local\Policies\$Gpo"
$Plantilla = "$Carpeta\MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
$Reglas = [ordered]@{
  MinimumPasswordLength = 12   # caracteres
  PasswordComplexity    = 1
  MaximumPasswordAge    = 90   # dias
  PasswordHistorySize   = 5
  LockoutBadCount       = 5    # intentos fallidos
  ResetLockoutCount     = 15   # minutos
  LockoutDuration       = 15   # minutos
}
$lineas = Get-Content $Plantilla
$original = $lineas -join "`n"
foreach ($regla in $Reglas.Keys) {
  $nueva = "$regla = $($Reglas[$regla])"
  if ($lineas -match "^$regla\s*=") {
    $lineas = $lineas -replace "^$regla\s*=.*", $nueva
  } else {
    # La regla no estaba: va justo debajo del encabezado de su seccion.
    $lineas = $lineas | ForEach-Object { $_; if ($_ -eq '[System Access]') { $nueva } }
  }
}
if (($lineas -join "`n") -ne $original) {
  Set-Content -Path $Plantilla -Value $lineas -Encoding Unicode
  # Subir la version de la GPO (la mitad baja del numero es la de equipo) para que se aplique.
  $objeto = Get-ADObject "CN=$Gpo,CN=Policies,CN=System,$Base" -Properties versionNumber
  $version = $objeto.versionNumber + 1
  Set-ADObject $objeto -Replace @{ versionNumber = $version }
  (Get-Content "$Carpeta\GPT.INI") -replace '^Version=.*', "Version=$version" | Set-Content "$Carpeta\GPT.INI"
  gpupdate /target:computer /force | Out-Null
  Write-Output '  GPO actualizada y aplicada.'
}
Get-ADDefaultDomainPasswordPolicy |
  Format-List MinPasswordLength, ComplexityEnabled, MaxPasswordAge, PasswordHistoryCount, LockoutThreshold, LockoutDuration

# ---------------------------------------------------------------------------
Write-Output '== 4. Auditoria de inicios de sesion =='
# Eventos 4624/4625 (inicio correcto y fallido) y 4740 (cuenta bloqueada). Por GUID de
# subcategoria, que no cambia con el idioma de Windows.
$Subcategorias = @{
  'Logon'                           = '{0CCE9215-69AE-11D9-BED3-505054503030}'
  'Account Lockout'                 = '{0CCE9217-69AE-11D9-BED3-505054503030}'
  'User Account Management'         = '{0CCE9235-69AE-11D9-BED3-505054503030}'
  'Credential Validation'           = '{0CCE923F-69AE-11D9-BED3-505054503030}'
  'Kerberos Authentication Service' = '{0CCE9242-69AE-11D9-BED3-505054503030}'
}
foreach ($guid in $Subcategorias.Values) {
  auditpol /set /subcategory:$guid /success:enable /failure:enable | Out-Null
}
Write-Output '  auditoria activada: inicios de sesion, bloqueos y cambios de cuentas.'

Write-Output ''
Write-Output "Listo. Contrasenas temporales en $Secretos (solo administradores)."
