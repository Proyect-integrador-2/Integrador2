# Correo de MS Motos por Brevo en vm-app-win (la instancia Windows).
#
# Pide la clave de API de Brevo sin mostrarla y el remitente (una direccion ya verificada
# en Brevo), los guarda en C:\opt\msmotos\.env (solo administradores y el servicio),
# reinicia el servicio MSMotos y manda un correo de prueba al propio remitente.
#
# Se corre de forma interactiva, como Administrator:
#   ssh -t Administrator@10.10.30.16 "powershell -ExecutionPolicy Bypass -File C:\opt\msmotos\configurar-correo.ps1"
# (el script y el mailer.js nuevo se copian a la VM con scp; la VM no tiene el repositorio).
$ErrorActionPreference = 'Stop'
$Raiz = 'C:\opt\msmotos'
$Archivo = "$Raiz\.env"
$Node = 'C:\Program Files\nodejs\node.exe'
if (-not (Test-Path $Archivo)) { throw "No existe ${Archivo}: primero desplegar.ps1" }

$segura = Read-Host 'Clave de API de Brevo (no se muestra)' -AsSecureString
$clave = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura))
if (-not $clave.StartsWith('xkeysib-')) { throw 'La clave de API de Brevo empieza con xkeysib-. No se cambio nada.' }
$correo = Read-Host 'Correo remitente, verificado en Brevo'
if ($correo -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'Correo no valido. No se cambio nada.' }

$lineas = Get-Content $Archivo | Where-Object { $_ -notmatch '^(BREVO_API_KEY|MAIL_FROM)=' }
$lineas += "BREVO_API_KEY=$clave"
$lineas += "MAIL_FROM=`"MS Motos <$correo>`""
$lineas | Set-Content $Archivo -Encoding ascii
Remove-Variable clave, segura

Restart-Service MSMotos
Write-Host 'Servicio MSMotos reiniciado; esperando a que responda...'
for ($i = 0; $i -lt 20; $i++) {
    try { if ((Invoke-WebRequest -UseBasicParsing http://127.0.0.1/api/health -TimeoutSec 3).StatusCode -eq 200) { break } } catch { }
    Start-Sleep 3
}

Write-Host "Correo de prueba a ${correo}:"
Push-Location "$Raiz\backend"
& $Node -e @"
require('dotenv').config({ path: 'C:/opt/msmotos/.env', quiet: true });
require('./src/services/mailer').enviarCorreo({ to: process.argv[1], subject: 'MS Motos (Windows): prueba de correo',
  html: '<p>Si lees esto, la instancia Windows ya puede enviar los codigos a los clientes.</p>' })
  .then(ok => { console.log(ok ? 'ENVIADO: revisa la bandeja (y el spam).' : 'NO SE ENVIO: mira el motivo arriba.'); process.exit(ok ? 0 : 1); })
"@ $correo
Pop-Location
