*** Settings ***
Documentation     Palabras clave comunes de los recorridos del cliente sintético en el portal
...               de MS Motos (IP2-56). Cada paso del recorrido es una palabra clave llamada
...               "Paso <nombre>": ejecutar.py mide su duración y la envía a Zabbix con ese nombre.
Library           Browser    timeout=10s    run_on_failure=Take Screenshot \ fallo-{index}

*** Variables ***
# Los tres valores llegan por variables de entorno desde ejecutar.py; nunca van en Git.
${URL}            %{RPA_URL=https://10.10.30.11}
${CORREO}         %{RPA_CORREO}
${MOTO}           Honda CB190R
# El portal está pensado para el celular: se mide con el tamaño de pantalla de un teléfono.
&{PANTALLA}       width=412    height=915

*** Keywords ***
Abrir el navegador
    [Documentation]    Navegador nuevo y sin datos guardados en cada ejecución, como un cliente
    ...                que entra por primera vez. No cuenta como paso: no es parte de la experiencia.
    New Browser    chromium    headless=True
    New Context    viewport=${PANTALLA}    locale=es-CR
    New Page    about:blank

Paso abrir
    [Documentation]    Cargar la pantalla de ingreso del portal.
    Go To    ${URL}/portal/login
    Wait For Elements State    input[type=email] >> visible=true    visible

Paso login
    [Documentation]    Ingresar con el correo y la contraseña del cliente sintético.
    Fill Text    input[type=email] >> visible=true    ${CORREO}
    Fill Secret    input[type=password] >> visible=true    %RPA_CLAVE
    Click    ion-button:has-text("Ingresar") >> visible=true
    Wait For Elements State    h1:has-text("Hola,") >> visible=true    visible

Cerrar la bienvenida
    [Documentation]    La primera vez que un cliente entra, el portal muestra un recorrido de
    ...                bienvenida que tapa la pantalla. El navegador del robot siempre es nuevo.
    ${hay}=    Run Keyword And Return Status
    ...    Wait For Elements State    css=.ob-skip    visible    timeout=3s
    IF    ${hay}    Click    css=.ob-skip
    Wait For Elements State    css=.ob-skip    detached    timeout=3s

Ir a la pestaña
    [Arguments]    ${pestana}
    Click    ion-tab-button[tab="${pestana}"] >> visible=true

Paso logout
    [Documentation]    Cerrar la sesión desde el perfil y volver a la pantalla de ingreso.
    Click    ion-button[title="Mi perfil"] >> visible=true
    Click    button:has-text("Cerrar sesión") >> visible=true
    Wait For Elements State    input[type=email] >> visible=true    visible
