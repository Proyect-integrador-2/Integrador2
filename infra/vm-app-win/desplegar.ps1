# Despliega MS Motos en vm-app-win (10.10.30.16) como servicio de Windows (IP2-74).
#
# Instalacion nativa, sin contenedores: es el segundo ambiente que pidio el profesor
# (docs/diseno/windows-server.md). Que hace, en orden:
#   1. Baja e instala Node.js 22, el entorno de Visual C++, MySQL 8.4 y NSSM.
#   2. Crea C:\opt\msmotos\.env con secretos aleatorios (propios de esta instancia).
#   3. Inicializa MySQL, crea la base, el usuario de la aplicacion y el esquema.
#   4. Trae el codigo del repositorio, instala dependencias y compila el frontend.
#   5. Crea las cuentas iniciales y el cliente sintetico del RPA.
#   6. Registra el servicio MSMotos (Node en el puerto 80) y abre el cortafuegos.
#
# Se corre en la VM como Administrator. Se puede repetir: no regenera secretos, no
# vuelve a crear el esquema si la base ya tiene tablas, y actualiza el codigo.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ip2\desplegar.ps1
#
# Cada instalador se comprueba antes de ejecutarse: huella SHA publicada o firma
# digital del fabricante.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # la barra de progreso hace lentisimas las descargas
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Raiz      = 'C:\opt\msmotos'
$Descargas = 'C:\ip2\descargas'
$Nssm      = 'C:\opt\nssm\nssm.exe'
$Node      = 'C:\Program Files\nodejs'
$MySql     = 'C:\Program Files\MySQL\MySQL Server 8.4'
$MySqlDatos = 'C:\ProgramData\MySQL\MySQL Server 8.4'
$Servicio  = 'MSMotos'
$ServicioDb = 'MySQL84'

$UrlRepo   = 'https://github.com/Proyect-integrador-2/Integrador2/archive/refs/heads/main.zip'
$UrlNode   = 'https://nodejs.org/dist/latest-v22.x'
$UrlVc     = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
$UrlMySql  = 'https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.9-winx64.msi'
$UrlNssm   = 'https://nssm.cc/release/nssm-2.24.zip'
$Sha1Nssm  = 'be7b3577c6e3a280e5106a9e9db5b3775931cefc'   # la que publica nssm.cc/download

function Paso($titulo) { Write-Output ''; Write-Output "== $titulo ==" }

function Secreto($largo) {
  $letras = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()
  $bytes = New-Object byte[] $largo
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $letras[$_ % $letras.Length] })
}

function Bajar($url, $archivo) {
  $destino = Join-Path $Descargas $archivo
  if (-not (Test-Path $destino)) {
    # Write-Host y no Write-Output: lo que una funcion escribe con Write-Output pasa a
    # ser parte de lo que devuelve, y aqui se devuelve solo la ruta.
    Write-Host "  bajando $archivo"
    Invoke-WebRequest -Uri $url -OutFile "$destino.parcial" -UseBasicParsing
    Move-Item "$destino.parcial" $destino
  }
  $destino
}

# Corta si el instalador no trae una firma digital valida del fabricante esperado.
function Exigir-Firma($archivo, $fabricante) {
  $firma = Get-AuthenticodeSignature $archivo
  if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch $fabricante) {
    throw "Firma no valida en $archivo (se esperaba $fabricante)."
  }
}

function Instalar-Msi($archivo, $extra) {
  $p = Start-Process msiexec -ArgumentList "/i `"$archivo`" /qn /norestart $extra" -Wait -PassThru
  if ($p.ExitCode -notin 0, 3010) { throw "msiexec devolvio $($p.ExitCode) con $archivo" }
}

# Corre un programa y corta si falla.
function Correr($programa) {
  & $programa @args
  if ($LASTEXITCODE -ne 0) { throw "$programa $args termino con codigo $LASTEXITCODE" }
}

# Lee una variable del .env.
function Valor($nombre) {
  $linea = Get-Content "$Raiz\.env" | Where-Object { $_ -match "^$nombre=" } | Select-Object -First 1
  if ($linea) { $linea.Substring($nombre.Length + 1) }
}

New-Item -ItemType Directory -Force $Descargas, $Raiz, "$Raiz\logs", "$Raiz\secretos", (Split-Path $Nssm) | Out-Null

# ---------------------------------------------------------------------------
Paso '1. Node.js, Visual C++, MySQL y NSSM'

if (-not (Test-Path "$Node\node.exe")) {
  # El nombre y la huella del instalador vigente salen de la lista que publica nodejs.org.
  $lista = (Invoke-WebRequest -Uri "$UrlNode/SHASUMS256.txt" -UseBasicParsing).Content
  $linea = ($lista -split "`n") | Where-Object { $_ -match '-x64\.msi$' } | Select-Object -First 1
  $huella, $nombre = $linea.Trim() -split '\s+'
  $msi = Bajar "$UrlNode/$nombre" $nombre
  if ((Get-FileHash $msi -Algorithm SHA256).Hash -ne $huella) { throw "La huella de $nombre no coincide." }
  Instalar-Msi $msi ''
}
$env:Path = "$Node;$env:Path"
Write-Output "  Node $(& "$Node\node.exe" --version)"

# MySQL necesita el entorno de ejecucion de Visual C++ 2015-2022.
if (-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64')) {
  $vc = Bajar $UrlVc 'vc_redist.x64.exe'
  Exigir-Firma $vc 'Microsoft Corporation'
  $p = Start-Process $vc -ArgumentList '/install /quiet /norestart' -Wait -PassThru
  if ($p.ExitCode -notin 0, 3010) { throw "vc_redist devolvio $($p.ExitCode)" }
}

if (-not (Test-Path "$MySql\bin\mysqld.exe")) {
  $msi = Bajar $UrlMySql (Split-Path $UrlMySql -Leaf)
  Exigir-Firma $msi 'Oracle'
  Instalar-Msi $msi ''
}
Write-Output "  $(& "$MySql\bin\mysqld.exe" --version)"

if (-not (Test-Path $Nssm)) {
  $zip = Bajar $UrlNssm 'nssm-2.24.zip'
  if ((Get-FileHash $zip -Algorithm SHA1).Hash -ne $Sha1Nssm) { throw 'La huella de nssm-2.24.zip no coincide.' }
  Expand-Archive $zip "$Descargas\nssm" -Force
  Copy-Item "$Descargas\nssm\nssm-2.24\win64\nssm.exe" $Nssm
}
Write-Output '  NSSM 2.24'

# ---------------------------------------------------------------------------
Paso '2. Variables de entorno'
# Solo las leen los administradores y la cuenta del servicio (LOCAL SERVICE, S-1-5-19).
if (Test-Path "$Raiz\.env") {
  Write-Output "  $Raiz\.env ya existe: no se regeneran los secretos."
} else {
  @"
# Generado por desplegar.ps1. No se sube a Git.
NODE_ENV=production
PORT=80
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=proyecto_taller
DB_USER=taller_app
DB_PASSWORD=$(Secreto 32)
JWT_SECRET=$(Secreto 48)
JWT_EXPIRES_IN=8h
WEB_CONCURRENCY=2
DB_POOL_TOTAL=20
# Las tareas programadas corren solo en la instancia Linux, para que no se dupliquen.
DISABLE_CRON=1
# Sin servicio de correo, igual que en Linux.
RESEND_API_KEY=
SEED_ADMIN_EMAIL=admin@taller.com
SEED_ADMIN_PASSWORD=$(Secreto 20)
SEED_RECEP_EMAIL=recepcion@taller.com
SEED_RECEP_PASSWORD=$(Secreto 20)
SEED_RPA_EMAIL=rpa@taller.local
SEED_RPA_PASSWORD=$(Secreto 20)
SEED_CLIENTE_RPA_EMAIL=cliente.rpa@taller.local
SEED_CLIENTE_RPA_PASSWORD=$(Secreto 20)
"@ | Set-Content "$Raiz\.env" -Encoding ascii
  Write-Output "  creado $Raiz\.env con secretos aleatorios."
}
icacls "$Raiz\.env" /inheritance:r /grant '*S-1-5-32-544:F' '*S-1-5-18:F' '*S-1-5-19:R' | Out-Null
icacls "$Raiz\secretos" /inheritance:r /grant '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null

# ---------------------------------------------------------------------------
Paso '3. Base de datos'
$mysql = "$MySql\bin\mysql.exe"
$root = "$Raiz\secretos\mysql-root.cnf"
$nueva = -not (Get-Service $ServicioDb -ErrorAction SilentlyContinue)
if ($nueva) {
  New-Item -ItemType Directory -Force $MySqlDatos | Out-Null
  # Solo escucha en la propia VM: la base no se publica en la red.
  @"
[mysqld]
basedir=$($MySql -replace '\\', '/')
datadir=$($MySqlDatos -replace '\\', '/')/Data
port=3306
bind-address=127.0.0.1
mysqlx=0
character-set-server=utf8mb4
"@ | Set-Content "$MySqlDatos\my.ini" -Encoding ascii
  Correr "$MySql\bin\mysqld.exe" "--defaults-file=$MySqlDatos\my.ini" --initialize-insecure
  Correr "$MySql\bin\mysqld.exe" --install $ServicioDb "--defaults-file=$MySqlDatos\my.ini"
  Start-Service $ServicioDb

  # Recien inicializado, root no tiene contrasena: se le pone una y se guarda aparte.
  $claveRoot = Secreto 32
  $claveApp = Valor 'DB_PASSWORD'
  @"
ALTER USER 'root'@'localhost' IDENTIFIED BY '$claveRoot';
CREATE DATABASE IF NOT EXISTS proyecto_taller CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'taller_app'@'localhost' IDENTIFIED BY '$claveApp';
CREATE USER IF NOT EXISTS 'taller_app'@'127.0.0.1' IDENTIFIED BY '$claveApp';
GRANT ALL PRIVILEGES ON proyecto_taller.* TO 'taller_app'@'localhost', 'taller_app'@'127.0.0.1';
"@ | & $mysql -u root
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la base de datos.' }
  "[client]`nuser=root`npassword=$claveRoot" | Set-Content $root -Encoding ascii
  Write-Output '  MySQL inicializado; base y usuario de la aplicacion creados.'
}
Start-Service $ServicioDb
Write-Output "  servicio ${ServicioDb}: $((Get-Service $ServicioDb).Status)"

# ---------------------------------------------------------------------------
Paso '4. Codigo de la aplicacion'
$zip = "$Descargas\repositorio.zip"
Invoke-WebRequest -Uri $UrlRepo -OutFile $zip -UseBasicParsing
Remove-Item "$Descargas\repositorio" -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $zip "$Descargas\repositorio" -Force
$fuente = (Get-ChildItem "$Descargas\repositorio" -Directory | Select-Object -First 1).FullName + '\app'

# Con el servicio detenido, para que Node no tenga archivos abiertos.
if (Get-Service $Servicio -ErrorAction SilentlyContinue) { Stop-Service $Servicio }
foreach ($parte in 'backend', 'frontend') {
  # /MIR deja la carpeta igual a la del repositorio, sin tocar lo que se genera aqui.
  robocopy "$fuente\$parte" "$Raiz\$parte" /MIR /XD node_modules www .angular /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy fallo copiando $parte" }
}

Push-Location "$Raiz\backend"
Correr "$Node\npm.cmd" ci --omit=dev --no-audit --no-fund
Pop-Location

# El esquema se crea una sola vez: schema.sql empieza con DROP TABLE.
$tablas = & $mysql "--defaults-extra-file=$root" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'proyecto_taller'"
if ([int]$tablas -eq 0) {
  Correr $mysql "--defaults-extra-file=$root" --default-character-set=utf8mb4 proyecto_taller -e "source $($Raiz -replace '\\', '/')/backend/schema.sql"
  Write-Output '  esquema creado.'
} else {
  Write-Output "  la base ya tiene $tablas tablas: no se toca el esquema."
}

Push-Location "$Raiz\frontend"
Write-Output '  compilando el frontend (tarda varios minutos)...'
$env:NODE_OPTIONS = '--max-old-space-size=2048'
Correr "$Node\npm.cmd" ci --no-audit --no-fund
Correr "$Node\npx.cmd" ng build --configuration production
$env:NODE_OPTIONS = ''
Pop-Location
if (-not (Test-Path "$Raiz\frontend\www\index.html")) { throw 'El frontend no se compilo.' }
# Las dependencias de compilacion pesan mas de 1 GB y ya no hacen falta.
Remove-Item "$Raiz\frontend\node_modules", "$Raiz\frontend\.angular" -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
Paso '5. Cuentas iniciales'
Push-Location $Raiz
Correr "$Node\node.exe" backend\scripts\seed-usuarios.js
Correr "$Node\node.exe" backend\scripts\seed-cliente-rpa.js
Pop-Location

# ---------------------------------------------------------------------------
Paso '6. Servicio de Windows y cortafuegos'
# La cuenta del servicio solo lee la aplicacion y escribe sus registros.
icacls $Raiz /grant '*S-1-5-19:(OI)(CI)RX' | Out-Null
icacls "$Raiz\logs" /grant '*S-1-5-19:(OI)(CI)M' | Out-Null

if (-not (Get-Service $Servicio -ErrorAction SilentlyContinue)) {
  Correr $Nssm install $Servicio "$Node\node.exe" 'backend\src\cluster.js'
}
$ajustes = [ordered]@{
  AppDirectory     = $Raiz                        # dotenv lee el .env de esta carpeta
  DisplayName      = 'MS Motos (aplicacion)'
  Description      = 'Aplicacion MS Motos del Proyecto Integrador II: API y portal web en el puerto 80'
  Start            = 'SERVICE_AUTO_START'
  DependOnService  = $ServicioDb
  AppStdout        = "$Raiz\logs\msmotos.log"
  AppStderr        = "$Raiz\logs\msmotos.log"
  AppRotateFiles   = '1'
  AppRotateOnline  = '1'
  AppRotateSeconds = '604800'                     # rotacion semanal
}
foreach ($ajuste in $ajustes.Keys) { Correr $Nssm set $Servicio $ajuste $ajustes[$ajuste] | Out-Null }
Correr $Nssm set $Servicio ObjectName 'NT AUTHORITY\LocalService' '' | Out-Null
# Sin acciones de recuperacion de Windows: si alguien detiene el servicio, lo
# levanta n8n, y asi se mide el tiempo igual que en Linux.
Correr sc.exe failure $Servicio reset= 0 actions= '""' | Out-Null
Start-Service $Servicio

if (-not (Get-NetFirewallRule -Name 'IP2-MSMotos-HTTP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'IP2-MSMotos-HTTP' -DisplayName 'IP2: MS Motos (HTTP 80)' `
    -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow | Out-Null
}

# ---------------------------------------------------------------------------
Paso '7. Comprobacion'
$codigo = 0
foreach ($intento in 1..30) {
  try { $codigo = (Invoke-WebRequest 'http://127.0.0.1/api/health' -UseBasicParsing -TimeoutSec 5).StatusCode; break }
  catch { Start-Sleep -Seconds 2 }
}
Get-Service $ServicioDb, $Servicio | Format-Table Name, Status, StartType -AutoSize
Write-Output "  /api/health: HTTP $codigo"
if ($codigo -ne 200) { throw "La aplicacion no respondio. Ver $Raiz\logs\msmotos.log" }
Write-Output "Listo. MS Motos en http://10.10.30.16"
