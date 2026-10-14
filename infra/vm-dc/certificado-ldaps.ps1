# Instala en el controlador de dominio el certificado para LDAPS (IP2-81).
#
# Proxmox, Zabbix, Grafana y las VMs Linux validan las cuentas contra el dominio. Para
# que las contrasenas no viajen en claro, lo hacen por LDAPS (puerto 636), y para eso el
# controlador necesita un certificado. Lo firma la autoridad interna del laboratorio
# (infra/proxmox/ca-interna.sh --dc), en la que ya confian los demas equipos.
#
# Llega por la entrada estandar, en dos lineas: el certificado con su llave en PKCS#12
# (base64) y la contrasena de ese archivo. Se corre como Administrator:
#   ... | ssh Administrator@10.10.30.17 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\certificado-ldaps.ps1"
$ErrorActionPreference = 'Stop'

$pfx = [Console]::In.ReadLine()
$clave = [Console]::In.ReadLine()
if (-not $pfx -or -not $clave) { throw 'Faltan el certificado y su contrasena por la entrada estandar.' }

$archivo = Join-Path $env:TEMP 'ldaps.pfx'
[IO.File]::WriteAllBytes($archivo, [Convert]::FromBase64String($pfx))
try {
  $seguro = ConvertTo-SecureString $clave -AsPlainText -Force
  # La llave queda no exportable en el almacen del equipo.
  $cert = Import-PfxCertificate -FilePath $archivo -CertStoreLocation Cert:\LocalMachine\My -Password $seguro
} finally {
  Remove-Item $archivo -Force
}

# La autoridad interna, como raiz de confianza del propio controlador.
$cadena = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$cadena.Build($cert[0]) | Out-Null
foreach ($elemento in $cadena.ChainElements) {
  $c = $elemento.Certificate
  if ($c.Subject -eq $c.Issuer -and -not (Test-Path "Cert:\LocalMachine\Root\$($c.Thumbprint)")) {
    $tienda = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
    $tienda.Open('ReadWrite'); $tienda.Add($c); $tienda.Close()
  }
}

# Pide a Active Directory que tome el certificado nuevo sin reiniciar.
$dse = [ADSI]'LDAP://localhost/RootDSE'
$dse.Put('renewServerCertificate', 1)
$dse.SetInfo()
Start-Sleep -Seconds 5

Write-Output ("Certificado instalado: " + $cert[0].Subject + ", vence " + $cert[0].NotAfter.ToString('yyyy-MM-dd'))
Write-Output ("LDAPS (636) escuchando: " + (Test-NetConnection localhost -Port 636 -WarningAction SilentlyContinue).TcpTestSucceeded)
