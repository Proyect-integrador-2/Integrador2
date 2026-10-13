*** Settings ***
Documentation     Recorrido de consulta del cliente (RF-16): entra al portal, revisa su resumen,
...               el historial de su moto y sus citas, y sale. Se ejecuta cada 5 minutos.
Resource          ../recursos/portal.resource
Suite Setup       Abrir el navegador
Suite Teardown    Close Browser    ALL

*** Test Cases ***
Consulta del cliente
    Paso abrir
    Paso login
    Paso inicio
    Paso motos
    Paso citas
    Paso logout

*** Keywords ***
Paso inicio
    [Documentation]    El inicio saluda al cliente por su nombre y muestra su resumen.
    Cerrar la bienvenida
    Get Text    h1:has-text("Hola,") >> visible=true    contains    Cliente
    Wait For Elements State    css=.sg .st-n >> nth=0    visible

Paso motos
    [Documentation]    Abrir el garaje y el historial de la moto de prueba, con su servicio.
    Ir a la pestaña    motos
    Click    css=.mc:has-text("${MOTO}") >> visible=true
    Wait For Elements State    h1:has-text("${MOTO}") >> visible=true    visible
    Wait For Elements State    css=.tl-item >> nth=0    visible
    Click    ion-back-button >> visible=true

Paso citas
    [Documentation]    Abrir "Mis Citas" y encontrar el servicio completado de la moto.
    Ir a la pestaña    mis-citas
    Click    button.seg-btn:has-text("Completadas") >> visible=true
    Wait For Elements State    text=${MOTO} >> visible=true    visible
