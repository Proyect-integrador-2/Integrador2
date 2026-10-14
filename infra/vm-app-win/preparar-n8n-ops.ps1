# Crea en vm-app-win la cuenta restringida con la que n8n inicia el servicio MSMotos (IP2-74).
#
# Los mismos controles que en Linux (docs/diseno/automatizacion.md):
#   C1  Lista cerrada: la cuenta solo puede iniciar el servicio MSMotos y consultar su estado.
#       Cualquier otro comando que llegue por SSH se descarta.
#   C4  Minimo privilegio: no es administradora, entra solo con llave y solo desde vm-n8n.
#
# La llave publica de n8n llega por la entrada estandar. Se corre en la VM como Administrator:
#
#   type n8n_ops_ed25519.pub | powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\preparar-n8n-ops.ps1
#
# Se puede repetir.
$ErrorActionPreference = 'Stop'

$Usuario  = 'n8n-ops'
$Origen   = '10.10.30.14'
$Servicio = 'MSMotos'
$Carpeta  = 'C:\opt\n8n-ops'
$Llaves   = 'C:\ProgramData\ssh\n8n-ops_authorized_keys'
$Config   = 'C:\ProgramData\ssh\sshd_config'

$llave = ([Console]::In.ReadLine()).Trim()
if ($llave -notmatch '^ssh-(ed25519|rsa) ') { throw 'Falta la llave publica de n8n por la entrada estandar.' }

# 1. La cuenta. Windows exige una contrasena para crearla: se pone una al azar que nadie
#    conoce ni se guarda, porque por SSH solo se entra con llave.
if (-not (Get-LocalUser $Usuario -ErrorAction SilentlyContinue)) {
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $clave = ConvertTo-SecureString ('Ip2' + [Convert]::ToBase64String($bytes)) -AsPlainText -Force
  New-LocalUser -Name $Usuario -Password $clave -PasswordNeverExpires -UserMayNotChangePassword `
    -Description 'n8n: solo inicia el servicio MSMotos' | Out-Null
}
$sid = (Get-LocalUser $Usuario).SID.Value

# 2. La unica accion permitida. sshd obliga a que toda sesion de esta cuenta ejecute este
#    script, que solo acepta dos pedidos.
New-Item -ItemType Directory -Force $Carpeta | Out-Null
@'
# Lo unico que n8n puede hacer en esta VM. Lo ejecuta sshd (ForceCommand).
$pedido = "$env:SSH_ORIGINAL_COMMAND".Trim()
switch ($pedido) {
  'start MSMotos' {
    sc.exe start MSMotos | Out-Null
    # 1056 = ya estaba en ejecucion: no es un error.
    if ($LASTEXITCODE -notin 0, 1056) { Write-Output "sc start devolvio $LASTEXITCODE"; exit 1 }
    foreach ($i in 1..15) {
      if ((sc.exe query MSMotos | Out-String) -match 'RUNNING') { Write-Output 'MSMotos en ejecucion'; exit 0 }
      Start-Sleep -Seconds 1
    }
    Write-Output 'MSMotos no llego a iniciar'; exit 1
  }
  'status MSMotos' {
    if ((sc.exe query MSMotos | Out-String) -match 'STATE\s+:\s+\d+\s+(\w+)') { Write-Output $Matches[1] }
    exit 0
  }
  default { Write-Output 'Accion no permitida'; exit 2 }
}
'@ | Set-Content "$Carpeta\accion.ps1" -Encoding ascii
icacls $Carpeta /inheritance:r /grant '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' "*${sid}:(OI)(CI)RX" | Out-Null

# 3. Permiso sobre el servicio: iniciar y consultar, nada mas (ni detener ni cambiar).
#    Es el equivalente a la lista de sudoers de Linux.
$permiso = "(A;;CCLCSWRPLORC;;;$sid)"
$actual = (sc.exe sdshow $Servicio | Where-Object { $_ }) -join ''
if ($actual -notmatch [regex]::Escape($sid)) {
  # Las entradas de permiso van antes de la seccion de auditoria (S:), si existe.
  $nuevo = if ($actual -match 'S:') { $actual -replace 'S:', "${permiso}S:" } else { $actual + $permiso }
  sc.exe sdset $Servicio $nuevo | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo dar el permiso sobre el servicio.' }
}

# 4. SSH: la llave solo vale desde vm-n8n, y la sesion queda atada al script.
"from=`"$Origen`",no-agent-forwarding,no-port-forwarding,no-pty $llave" | Set-Content $Llaves -Encoding ascii
icacls $Llaves /inheritance:r /grant '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null
if (-not (Select-String -Path $Config -Pattern "^Match User $Usuario" -Quiet)) {
  @"

# Integrador II: cuenta de n8n, atada a una sola accion (infra/vm-app-win/preparar-n8n-ops.ps1)
Match User $Usuario
       AuthorizedKeysFile __PROGRAMDATA__/ssh/n8n-ops_authorized_keys
       ForceCommand powershell -NoProfile -ExecutionPolicy Bypass -File $Carpeta\accion.ps1
       AllowTcpForwarding no
"@ | Add-Content $Config -Encoding ascii
  Restart-Service sshd
}

Write-Output "Cuenta $Usuario lista: llave aceptada solo desde $Origen."
Write-Output ("Administradora: " + [bool](Get-LocalGroupMember Administrators -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$Usuario" }))
