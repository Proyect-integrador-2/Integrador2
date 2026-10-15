*** Settings ***
Documentation     Toma capturas de Zabbix con un navegador sin interfaz (IP2-42): hosts, problemas,
...               monitoreo web y los últimos datos de un host por cada capa.
...
...               Entra con la cuenta local de solo lectura que usa Grafana. Usuario y contraseña
...               llegan por las variables de entorno ZBX_USER y ZBX_PASS (se pasan desde el .env
...               de vm-zabbix por una tubería). Se corre en vm-rpa sin guardar el registro de
...               Robot Framework:
...
...               /opt/rpa/venv/bin/robot --log NONE --report NONE --output NONE
...               --outputdir /tmp/capturas-zabbix capturas.robot
Library           Browser

*** Variables ***
${ZABBIX}         http://10.10.30.12
${GRUPO}          22
${ESPERA}         6s
# Un host por capa de la guía: servidor, VM, contenedores y servicio, aplicación, red,
# Windows, dominio y automatización.
&{HOSTS}          proxmox=10690    vm-app=10683    msmotos-web=10691    sw1=10689    r1=10688
...               vm-app-win=10694    vm-dc=10695    automatizacion=10693

*** Test Cases ***
Capturar Zabbix
    New Browser    chromium    headless=True
    New Context    viewport={'width': 1600, 'height': 1300}    locale=es-CR
    New Page    ${ZABBIX}/index.php
    Fill Text    id=name    %{ZBX_USER}
    Fill Secret    id=password    %ZBX_PASS
    Click    id=enter
    Wait For Elements State    css=.sidebar    visible    timeout=20s
    Capturar    zabbix-hosts    zabbix.php?action=host.view&groupids[]=${GRUPO}&filter_set=1
    Capturar    zabbix-problemas-24h
    ...    zabbix.php?action=problem.view&show=2&from=now-24h&to=now&groupids[]=${GRUPO}&filter_set=1
    Capturar    zabbix-web    zabbix.php?action=web.view&groupids[]=${GRUPO}&filter_set=1
    FOR    ${host}    ${id}    IN    &{HOSTS}
        # Solo lo que cabe en pantalla: el switch tiene más de 240 ítems.
        Capturar    zabbix-datos-${host}    zabbix.php?action=latest.view&hostids[]=${id}&filter_set=1    completa=False
    END

*** Keywords ***
Capturar
    [Arguments]    ${nombre}    ${ruta}    ${completa}=True
    Go To    ${ZABBIX}/${ruta}
    Sleep    ${ESPERA}
    Take Screenshot    filename=${OUTPUT DIR}/${nombre}    fullPage=${completa}
