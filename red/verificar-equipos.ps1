# Verificacion de los controles de endurecimiento de R1 y SW1 (IP2-88).
#
# Entra por SSH a cada equipo con tu usuario, corre solo comandos "show" (no cambia nada
# en los equipos) y guarda la salida en tu carpeta temporal:
#   %TEMP%\ip2-sw1.txt y %TEMP%\ip2-r1.txt
# Ningun comando muestra contrasenas ni la comunidad SNMP (no se usa show running-config).
#
# Uso, desde la laptop con Tailscale o desde PC-ADMIN (te pide la contrasena de cada equipo):
#   powershell -ExecutionPolicy Bypass -File red\verificar-equipos.ps1
#   powershell -ExecutionPolicy Bypass -File red\verificar-equipos.ps1 -Usuario admin -Solo sw1
param(
    [string]$Usuario = 'admin',
    [ValidateSet('ambos', 'sw1', 'r1')][string]$Solo = 'ambos'
)

$equipos = [ordered]@{
    sw1 = @{
        Ip       = '10.10.99.2'
        # El 2960 solo ofrece algoritmos antiguos de SSH.
        Opciones = @('-o', 'KexAlgorithms=+diffie-hellman-group1-sha1', '-o', 'HostKeyAlgorithms=+ssh-rsa',
                     '-o', 'Ciphers=+aes128-cbc', '-o', 'MACs=+hmac-sha1')
        Comandos = @(
            'terminal length 0',
            'show version | include IOS|uptime',
            'show login',
            'show ip ssh',
            'show ip dhcp snooping',
            'show ip arp inspection vlan 20',
            'show storm-control',
            'show port-security',
            'show access-lists',
            'show ip http server status',
            'show errdisable recovery',
            'show interfaces status',
            'show vlan brief',
            'show spanning-tree summary',
            'show cdp',
            'show users',
            'exit'
        )
    }
    r1 = @{
        Ip       = '10.10.30.1'
        Opciones = @()
        Comandos = @(
            'terminal length 0',
            'show version | include IOS|uptime',
            'show login',
            'show ip ssh',
            'show access-lists',
            'show ip interface brief',
            'show ip http server status',
            'show ip nat statistics',
            'show ip dhcp pool',
            'show cdp',
            'show users',
            'exit'
        )
    }
}

foreach ($nombre in $equipos.Keys) {
    if ($Solo -ne 'ambos' -and $Solo -ne $nombre) { continue }
    $e = $equipos[$nombre]
    $salida = Join-Path $env:TEMP "ip2-$nombre.txt"
    Write-Host ""
    Write-Host "== $nombre ($($e.Ip)) ==  escribe la contrasena de $Usuario cuando la pida" -ForegroundColor Cyan
    $argumentos = @('-tt') + $e.Opciones + @('-o', 'StrictHostKeyChecking=accept-new', "$Usuario@$($e.Ip)")
    ($e.Comandos -join "`n") + "`n" | & ssh @argumentos 2>&1 | Out-File -FilePath $salida -Encoding utf8
    $lineas = (Get-Content $salida | Measure-Object -Line).Lines
    Write-Host "Guardado en $salida ($lineas lineas)" -ForegroundColor Green
}
Write-Host ""
Write-Host "Listo. Avisa a Claude: el lee los archivos de %TEMP%, no hace falta pegar nada." -ForegroundColor Yellow
