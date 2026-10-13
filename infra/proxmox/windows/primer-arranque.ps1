# Primer arranque de una VM Windows Server del laboratorio (IP2-73, IP2-79).
#
# Lo lanza el instalador en la primera sesión (ver autounattend.xml). Deja la VM
# administrable sin consola: IP fija, ping, escritorio remoto y SSH con llave.
# Se puede repetir. Lo que hace queda escrito en C:\ip2\primer-arranque.log.
param(
  [Parameter(Mandatory = $true)] [string]$Ip
)

$Gateway = '10.10.30.1'
# Los DNS de la universidad y 1.1.1.1 de respaldo (8.8.8.8 pierde consultas desde esta red).
$Dns = @('10.100.8.2', '10.100.8.3', '1.1.1.1')
# Solo se administra desde la VLAN de servidores y la de administración.
$RedesAdmin = @('10.10.30.0/24', '10.10.40.0/24')

New-Item -ItemType Directory -Force C:\ip2 | Out-Null
Start-Transcript -Path C:\ip2\primer-arranque.log -Append

# 1. Red: IP fija en la VLAN 30.
$tarjeta = Get-NetAdapter -Physical | Sort-Object ifIndex | Select-Object -First 1
if (-not (Get-NetIPAddress -IPAddress $Ip -ErrorAction SilentlyContinue)) {
  New-NetIPAddress -InterfaceIndex $tarjeta.ifIndex -IPAddress $Ip -PrefixLength 24 -DefaultGateway $Gateway
}
Set-DnsClientServerAddress -InterfaceIndex $tarjeta.ifIndex -ServerAddresses $Dns

# 2. Ping y escritorio remoto.
if (-not (Get-NetFirewallRule -Name 'IP2-Ping' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'IP2-Ping' -DisplayName 'IP2: responder ping' -Direction Inbound `
    -Protocol ICMPv4 -IcmpType 8 -Action Allow | Out-Null
}
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Set-NetFirewallRule -RemoteAddress $RedesAdmin

# La contraseña de Administrator no vence: es un laboratorio que dura un cuatrimestre.
Set-LocalUser -Name Administrator -PasswordNeverExpires $true

# 3. Servidor SSH. Es un componente de Windows que se baja de Windows Update:
#    recién puesta la IP puede fallar, por eso se reintenta.
$instalado = $false
foreach ($intento in 1..10) {
  try {
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction Stop | Out-Null
    $instalado = $true
    break
  } catch {
    Write-Output ('OpenSSH, intento {0}: {1}' -f $intento, $_.Exception.Message)
    Start-Sleep -Seconds 30
  }
}

if ($instalado) {
  Set-Service sshd -StartupType Automatic
  # El primer arranque del servicio crea las llaves del servidor y sshd_config.
  Start-Service sshd

  # Se entra solo con llave, y la sesión abre PowerShell.
  $config = 'C:\ProgramData\ssh\sshd_config'
  (Get-Content $config) -replace '^#?PasswordAuthentication .*', 'PasswordAuthentication no' |
    Set-Content $config -Encoding ascii
  New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -PropertyType String -Force `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' | Out-Null

  # Llaves públicas de quienes administran. OpenSSH exige que el archivo sea solo
  # de Administrators y SYSTEM (se indican por SID).
  $llaves = 'C:\ProgramData\ssh\administrators_authorized_keys'
  Copy-Item (Join-Path $PSScriptRoot 'authorized_keys') $llaves -Force
  icacls $llaves /inheritance:r /grant '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null

  if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
      -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
  }
  Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any -RemoteAddress $RedesAdmin
  Restart-Service sshd
  Set-Content C:\ip2\listo.txt (Get-Date -Format s)
} else {
  Write-Output 'No se pudo instalar OpenSSH. La VM queda con escritorio remoto; repetir este script.'
}

Stop-Transcript
