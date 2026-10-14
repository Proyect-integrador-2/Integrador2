*** Settings ***
Documentation     Toma una captura de cada tablero de Grafana con un navegador sin interfaz (IP2-48).
...
...               Entra con un token de solo lectura que llega por la variable de entorno
...               GRAFANA_TOKEN (lo crea infra/vm-grafana/token-capturas.py). Se corre en vm-rpa,
...               sin guardar el registro de Robot Framework, que dejaría el token escrito:
...
...               GRAFANA_TOKEN=$(cat ~/grafana.token) /opt/rpa/venv/bin/robot --log NONE
...               --report NONE --output NONE --outputdir /tmp/capturas capturas.robot
Library           Browser

*** Variables ***
${GRAFANA}        http://10.10.30.13
${ESPERA}         15s
@{TABLEROS}       ip2-general    ip2-tecnico    ip2-red    ip2-experiencia    ip2-automatizacion

*** Test Cases ***
Capturar los tableros
    New Browser    chromium    headless=True
    ${cabeceras}=    Create Dictionary    Authorization=Bearer %{GRAFANA_TOKEN}
    # Ventana alta: Grafana solo dibuja los paneles que caben en pantalla.
    New Context    viewport={'width': 1600, 'height': 2300}    extraHTTPHeaders=${cabeceras}
    FOR    ${tablero}    IN    @{TABLEROS}
        New Page    ${GRAFANA}/d/${tablero}?kiosk&theme=light
        Sleep    ${ESPERA}
        Take Screenshot    filename=${OUTPUT DIR}/${tablero}
        Close Page
    END
