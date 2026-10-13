# Promueve vm-dc a controlador del dominio ip2.local (IP2-79).
#
# Instala los roles AD DS y DNS y crea el bosque. Al terminar, Windows se reinicia solo.
# Despues se corre configurar-dominio.ps1.
#
# La contrasena del modo de restauracion del directorio (DSRM) llega por la entrada
# estandar, para que no quede escrita en ningun comando ni en el historial. Desde el
# servidor Proxmox, que es donde se guarda:
#
#   cat /root/secretos-ip2/dsrm-dc01.txt | ssh Administrator@10.10.30.17 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\promover-dominio.ps1"
$ErrorActionPreference = 'Stop'

$Dominio = 'ip2.local'
$NetBios = 'IP2'

# DomainRole 4 y 5 son controladores de dominio.
if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {
  Write-Output 'Esta VM ya es controlador de dominio: no se hace nada.'
  exit 0
}

$texto = [Console]::In.ReadLine()
if (-not $texto -or $texto.Length -lt 12) {
  throw 'Falta la contrasena DSRM por la entrada estandar (12 caracteres o mas).'
}
$clave = ConvertTo-SecureString $texto -AsPlainText -Force
$texto = $null

Write-Output 'Instalando los roles AD DS y DNS...'
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null

Write-Output "Creando el bosque $Dominio (la VM se reinicia al terminar)..."
Import-Module ADDSDeployment
# WinThreshold es el nivel funcional Windows Server 2016, el del diseno.
Install-ADDSForest -DomainName $Dominio -DomainNetbiosName $NetBios `
  -ForestMode WinThreshold -DomainMode WinThreshold -InstallDns `
  -SafeModeAdministratorPassword $clave -Force -WarningAction SilentlyContinue | Out-Null
