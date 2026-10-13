*** Settings ***
Documentation     Recorrido de agendamiento (RF-17): el cliente reserva el próximo espacio libre,
...               comprueba que la cita quedó registrada y la cancela. Se ejecuta cada 30 minutos.
...               La cita se cancela en el mismo recorrido para no ocupar la agenda del taller;
...               si el recorrido falla a medias, ejecutar.py cancela lo que haya quedado abierto.
Resource          ../recursos/portal.resource
Library           DateTime
Suite Setup       Abrir el navegador
Suite Teardown    Close Browser    ALL

*** Test Cases ***
Agendar y cancelar una cita
    Paso abrir
    Paso login
    Paso elegir
    Paso reservar
    Paso verificar
    Paso cancelar
    Paso logout

*** Keywords ***
Campo
    [Documentation]    Selector del control que está bajo la etiqueta indicada.
    [Arguments]    ${etiqueta}    ${control}=select
    RETURN    css=.fg:has(label:has-text("${etiqueta}")) ${control} >> visible=true

Paso elegir
    [Documentation]    Abrir "Agendar" y elegir sucursal, moto y servicio.
    Cerrar la bienvenida
    Ir a la pestaña    agendar
    ${sucursal}=    Campo    Sucursal
    ${moto}=    Campo    Seleccionar moto
    ${servicio}=    Campo    Tipo de servicio
    # El índice 0 de cada lista es el texto de ayuda ("Elegí..."): se toma la primera opción real.
    Select Options By    ${sucursal}    index    1
    Select Options By    ${moto}    index    1
    Wait For Elements State    ${servicio} >> option >> nth=1    attached
    Select Options By    ${servicio}    index    1

Paso reservar
    [Documentation]    Reservar la primera hora libre a partir de tres días adelante.
    ...                No se usa "Sugerir próximo horario libre": propone el espacio más cercano,
    ...                y la aplicación no deja cancelar una cita con menos de dos horas de
    ...                anticipación. Con tres días de margen el robot siempre puede cancelarla.
    ${fecha}=    Campo    Fecha    input
    FOR    ${dias}    IN RANGE    3    10
        ${dia}=    Get Current Date    increment=${dias} days    result_format=%Y-%m-%d
        Fill Text    ${fecha}    ${dia}
        ${hay_hora}=    Run Keyword And Return Status
        ...    Wait For Elements State    css=.tg .ts:not(.full) >> visible=true >> nth=0    visible    timeout=3s
        IF    ${hay_hora}    BREAK
    END
    Click    css=.tg .ts:not(.full) >> visible=true >> nth=0
    Wait For Elements State    css=.tg .ts.sel >> visible=true    visible
    Click    button.cta:has-text("Agendar cita") >> visible=true
    Wait For Elements State    button.seg-btn:has-text("Pendientes") >> visible=true    visible

Paso verificar
    [Documentation]    La cita recién creada aparece entre las pendientes.
    Wait For Elements State    css=.cita-card:has-text("${MOTO}") >> visible=true >> nth=0    visible

Paso cancelar
    [Documentation]    Cancelar la cita desde su detalle y volver a la lista.
    Click    css=.cita-card:has-text("${MOTO}") >> visible=true >> nth=0 >> button.ver-detalle
    Click    button.btn-cancelar >> visible=true
    Click    button:has-text("Sí, cancelar") >> visible=true
    Wait For Elements State    css=.cancel-card >> visible=true    visible
    Click    ion-back-button >> visible=true
    Wait For Elements State    button.seg-btn:has-text("Pendientes") >> visible=true    visible
