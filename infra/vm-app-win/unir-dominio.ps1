# Une vm-app-win al dominio ip2.local (IP2-81).
#
# Se corre dos veces en la VM, como Administrator:
#   1. La primera une la VM al dominio y la reinicia. La contrasena del administrador del
#      dominio llega por la entrada estandar, para que no quede escrita en ningun comando.
#      Desde el servidor Proxmox, que es donde se guarda:
#        cat /root/secretos-ip2/windows-administrator.txt | ssh Administrator@10.10.30.16 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\unir-dominio.ps1"
#   2. La segunda, ya reiniciada, da acceso de administracion al grupo del dominio:
#        ssh Administrator@10.10.30.16 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\unir-dominio.ps1"
#
# La cuenta local Administrator sigue existiendo: es la cuenta de emergencia de esta VM
# si el controlador de dominio no responde (riesgo R-14).
$ErrorActionPreference = 'Stop'

$Dominio = 'ip2.local'
$Dc      = '10.10.30.17'
$Unidad  = 'OU=Equipos,OU=IP2,DC=ip2,DC=local'
$Grupo   = 'IP2\GG-IP2-Administradores'

if (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
  $texto = [Console]::In.ReadLine()
  if (-not $texto) { throw 'Falta la contrasena del administrador del dominio por la entrada estandar.' }
  $credencial = New-Object System.Management.Automation.PSCredential('IP2\Administrator',
    (ConvertTo-SecureString $texto -AsPlainText -Force))
  $texto = $null

  # El dominio se resuelve con el DNS del controlador. El de la universidad queda de
  # respaldo: si el controlador cae, la VM sigue resolviendo nombres de Internet.
  $tarjeta = Get-NetAdapter -Physical | Sort-Object ifIndex | Select-Object -First 1
  Set-DnsClientServerAddress -InterfaceIndex $tarjeta.ifIndex -ServerAddresses $Dc, '10.100.8.2'

  Add-Computer -DomainName $Dominio -OUPath $Unidad -Credential $credencial -Force -WarningAction SilentlyContinue
  Write-Output "Unida a $Dominio. Reiniciando; despues hay que correr este script otra vez."
  Restart-Computer -Force
  exit 0
}

# Ya unida: el grupo de administradores del dominio administra esta VM.
if (-not (Get-LocalGroupMember Administrators | Where-Object { $_.Name -eq $Grupo })) {
  Add-LocalGroupMember -Group Administrators -Member $Grupo
}
Write-Output ("Dominio: " + (Get-CimInstance Win32_ComputerSystem).Domain)
Write-Output 'Administradores locales:'
Get-LocalGroupMember Administrators | ForEach-Object { '  ' + $_.Name }
