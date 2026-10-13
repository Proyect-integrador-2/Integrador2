# Instala el agente 2 de Zabbix en una VM Windows Server del laboratorio (IP2-75, IP2-82).
#
# Se corre en la VM como Administrator, indicando el nombre con que el host existe en Zabbix:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\instalar-agente-windows.ps1 -Nombre vm-app-win
#
# Se puede repetir. El instalador se comprueba por su firma digital antes de ejecutarlo.
param(
  [Parameter(Mandatory = $true)] [string]$Nombre
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Servidor = '10.10.30.12'
$Version  = '7.0.31'       # la misma del agente de las VM Linux
$Url      = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/$Version/zabbix_agent2-$Version-windows-amd64-openssl.msi"
$Msi      = "C:\ip2\descargas\zabbix_agent2-$Version.msi"

if (-not (Get-Service 'Zabbix Agent 2' -ErrorAction SilentlyContinue)) {
  New-Item -ItemType Directory -Force (Split-Path $Msi) | Out-Null
  if (-not (Test-Path $Msi)) { Invoke-WebRequest -Uri $Url -OutFile $Msi -UseBasicParsing }
  $firma = Get-AuthenticodeSignature $Msi
  if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch 'Zabbix') {
    throw "Firma no valida en $Msi."
  }
  $opciones = "/i `"$Msi`" /qn /norestart SERVER=$Servidor SERVERACTIVE=$Servidor HOSTNAME=$Nombre"
  $p = Start-Process msiexec -ArgumentList $opciones -Wait -PassThru
  if ($p.ExitCode -notin 0, 3010) { throw "msiexec devolvio $($p.ExitCode)" }
}

# Solo el servidor de Zabbix puede consultar al agente.
if (-not (Get-NetFirewallRule -Name 'IP2-Zabbix-Agente' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'IP2-Zabbix-Agente' -DisplayName 'IP2: agente de Zabbix (10050)' `
    -Direction Inbound -Protocol TCP -LocalPort 10050 -RemoteAddress $Servidor -Action Allow | Out-Null
}
Start-Service 'Zabbix Agent 2'
Get-Service 'Zabbix Agent 2' | Format-Table Name, Status, StartType -AutoSize
