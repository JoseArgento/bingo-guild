# Bingo de la Guild

Un cartón de bingo por semana para jugar con tu guild en **WoW Forever**. Son 24 metas chicas y medio absurdas ("morir de una caída", "encontrar un PNJ raro", "foto grupal en una capital"), con una casilla libre en el medio. Toda la guild tiene el mismo cartón, cada uno lo va llenando jugando, y en la ventana ves cómo vienen los demás.

[Read in English](README.en.md)

**Contenido**

- [Cómo se juega](#cómo-se-juega)
- [Instalar](#instalar)
- [Qué manda y qué recibe](#qué-manda-y-qué-recibe)
- [Cómo se probó](#cómo-se-probó)
- [Desarrollo](#desarrollo)
- [Apoyar](#apoyar)

## Cómo se juega

- Se abre con `/bingo`, desde el botón de addons junto al minimapa o con un atajo de teclado. **La ventana es un libro abierto**: el cartón va sellado en la página izquierda (las casillas marcadas quedan doradas con un tilde, la línea completa en carmesí, la libre con un sello de lacre) y los marcadores de tela del borde pasan de página: **Cartón** (tu guild esta semana), **Liga** y, solo para oficiales, **Oficiales**. Es la piel [Pergamino](https://github.com/JoseArgento/pergamino), la misma de Bitácora y los demás addons de la familia; las fuentes (Alegreya y Cinzel, licencia OFL) viajan dentro del addon.
- **Idioma:** sigue al del cliente, o lo elegís con `/bingo idioma es` / `en` / `auto` (sirve para jugar en castellano con el cliente en inglés). Los textos de la ventana cambian al instante; los del chat, después de un `/reload`.
- **Metas que se marcan solas** (30): morir, subir de nivel, matar un jefe, entregar misiones, pisar zonas nuevas, un duelo, mandar una carta, un vuelo, hacer grupo con alguien de la guild, un ítem azul o mejor, un PNJ raro, jugar varios días, pasar por la subasta, una captura en grupo; y de Forever: **cada una de las 9 mazmorras nuevas por nombre** (Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran, The Drowned City, Krol'dok Stronghold, Alcaz Island Prison, Blackmaw Hold, Shaper's Terrace), una o tres mazmorras nuevas distintas, **ganar un punto del Legado** y **subir un Skyborne a nivel 10**.
- **Metas que marcás vos** (30), entre ellas las de Forever que el juego no puede saber: armar un campamento, sentarte en la fogata de otro, conseguir un plano, transfigurar algo, marcar algo al grupo con un ping, jugar con control, esconder tu segundo nombre, mirar el medidor de daño del juego… y las de siempre, como "que te mate un guardia" o "bailar en una taberna". Clic para marcar, otro clic para desmarcar. Es un juego entre amigos: va de palabra.
- **Bingo:** una fila, una columna o una diagonal completa. Te avisa en el centro de la pantalla, y aparece un botón para anunciarlo en el chat de la guild (solo si lo apretás).
- **El cartón cambia con el reinicio semanal**, a la misma hora para todo el reino.
- Pasando el mouse por una casilla ves quiénes de la guild ya la tienen.
- `/bingo sync` le vuelve a pedir los cartones a la guild.
- **Liga:** el marcador "Liga" (o `/bingo liga`) suma los puntos de las últimas semanas: uno por casilla y 5 más por línea.
- **Cartón de los oficiales:** un oficial puede escribir metas propias para la semana (marcador "Oficiales", botón "Agregar meta" o `/bingo meta <texto>`, hasta 24 de 50 letras) y publicarlas ("Publicar cartón" o `/bingo publicar`). El cartón de toda la guild pasa a tener esas metas, completado con metas de la lista. Solo se acepta de quien en el roster de la guild tiene el rango del líder o el de abajo.
- **Sugerir una meta:** cualquiera de la guild propone una ("Sugerir meta" o `/bingo sugerir <texto>`); les llega solo a los oficiales, que las revisan de a una ("Sugerencias (n)" o `/bingo sugerencias`) y las agregan al cartón o las descartan.
- **Exportar e importar la lista de metas** (oficiales, "Exportar / importar metas" o `/bingo exportar`): un texto con una meta por línea, para guardarla o pasársela a otro oficial. Al importar reemplaza las metas, hasta 24, limpias como las que llegan por mensaje.
- Cuando arranca una semana nueva, te avisa en el chat.

Sin guild también anda: el cartón es solo tuyo.

## Instalar

Copiá la carpeta `BingoDeLaGuild` (con su `Libs\Pergamino` adentro) a `Interface\AddOns\`, dentro de la carpeta de Forever del juego. Para ver los cartones de los demás, ellos también tienen que tenerlo.

## Qué manda y qué recibe

- **Manda** por el canal de la guild, y nada más, un texto corto así: `C|3|1762300800|3fa9c1|0000011111001000000000000` (versión, semana, qué cartón es, y un 1 por cada casilla marcada). Las marcas solo se comparan entre quienes tienen el mismo cartón. Los oficiales mandan además su cartón: una línea por meta. Una sugerencia es `S|3|<semana>|<texto>`. Lo manda al entrar, un ratito después de que marcás algo y cuando alguien de la guild lo pide.
- **Recibe** solo de la guild. Lo que llega se lee con patrones y se guarda como texto: el addon nunca ejecuta nada de lo que recibe. Descarta mensajes de otro canal, mal formados, de otra semana, demasiado largos o tuyos, acepta como mucho 5 mensajes cada 10 segundos por persona (40 por minuto para el cartón de un oficial) y guarda hasta 1000 cartones (el tope de una guild). Las sugerencias solo las guardan los oficiales: hasta 50, sin repetidas de la misma persona. Las metas de los oficiales se guardan sin el carácter `|` (el que usa el juego para colores y links) ni caracteres de control, y cortadas a 50 letras.
- **Nunca escribe en el chat por su cuenta.** El anuncio de bingo sale solo cuando apretás el botón.
- **Cuentas de prueba:** Forever no las deja mandar mensajes de addon. El addon se da cuenta, no intenta mandar y te avisa: vos ves los cartones de la guild, ellos no ven el tuyo.
- Si el juego frena los mensajes (por cantidad, o porque en ese momento restringe el chat), lo vuelve a intentar más tarde.

## Cómo se probó

**Probado:**
- ✅ **Cada función, evento y template existe en Forever 1.60.1**, revisado con `tools/check_api.py` contra los dumps de [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) y el código de la UI de [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), rama `forever`. Por ejemplo: en Forever no existe `SendChatMessage` suelto, es `C_ChatInfo.SendChatMessage`; `CHAT_MSG_ADDON` no trae valores secretos; `C_ChatInfo.InChatMessagingLockdown` existe.
- ✅ [forever-lint](https://github.com/JoseArgento/forever-lint): solo notas que el addon ya maneja: FL012 (cuentas de prueba) y FL013 (`PLAYER_DEAD` doble y la zona vieja al viajar). [Addon Sentry](https://github.com/JoseArgento/addon-sentry): "Sin señales de riesgo".
- ✅ **95 tests** en Lua 5.1 (el Lua de WoW) con un reemplazo chico del cliente. Corren **dos o más clientes a la vez** y se pasan los mensajes, así que la sincronización se prueba de punta a punta: cartón igual para toda la guild, cartón nuevo cada semana, cada meta automática, bingo por filas, columnas y diagonales, un recién llegado que pide los cartones, muchas preguntas con una sola respuesta, el cartón de un oficial (que solo valga si el roster dice que es oficial, que no se use a medias, que uno viejo no pise uno nuevo, que el que llega tarde lo reciba), la liga, las sugerencias (solo las guardan los oficiales, tope, repetidas, inundación, agregar o descartar), exportar e importar la lista, las metas de Forever (punto del Legado, Skyborne a 10, mazmorras nuevas por nombre), mensajes malos o con código adentro, inundación de mensajes, tope de 1000, cuenta de prueba, sin guild, reintento cuando el juego frena los mensajes, guardar y cargar, y el libro (texturas y fuentes propias, marcadores que pasan de página, sellos de las casillas, pestaña de oficiales solo para oficiales, idioma elegible, estados vacíos).

**Sin probar ⏳** (no tengo el cliente de Forever):
- Las mazmorras nuevas se marcan solas por el nombre que da `GetInstanceInfo()`, en inglés: en un cliente en castellano los nombres pueden venir traducidos y esas casillas se marcan a mano.
- Que `UnitRace("player")` diga "Skyborne" (el nombre o el token de raza) en el cliente.
- Cómo se ve el libro de verdad: las texturas TGA, las fuentes TTF que carga `SetFont`, los marcadores sobre el borde de la tapa.
- Que `C_DateAndTime.GetSecondsUntilWeeklyReset` dé el reinicio de Forever. Si no da nada, el addon usa semanas de lunes a lunes (UTC).
- Que los eventos de las metas automáticas salten como en el resto de los clientes (`ENCOUNTER_END` en las mazmorras de Forever, `PLAYER_CONTROL_LOST` al tomar un vuelo).
- Que `GetGuildRosterInfo` devuelva el índice de rango en tercer lugar, como en el resto de los clientes (la UI de Forever no lo usa, así que no lo pude ver en su código).
- Que el botón de anunciar pueda escribir en la guild (`C_ChatInfo.SendChatMessage` tiene restricciones; se llama solo desde el clic).

## Desarrollo

```bash
pip install pytest lupa
pytest
python tools/check_api.py --bir ../BlizzardInterfaceResources --ui ../wow-ui-source --scanner ../addon-sentry/src
```

Si cambiás la lista de metas (`Goals.lua`), subí `POOL_VERSION`: el cartón sale de esa lista, y dos versiones distintas mostrarían cartones distintos. Un test te frena si te olvidás.

Un tag `v*` empaqueta el addon con el packager de BigWigs (`.github/workflows/release.yml`).

## Apoyar

Todo esto es gratis y de código abierto, y va a seguir así: no hay funciones pagas ni nada antes para quien aporta. Si te sirvió y querés bancar el tiempo de mantenerlo (con cada parche de Blizzard hay que actualizar los datos y arreglar lo que se rompe), podés hacerlo en [Patreon](https://www.patreon.com/cw/DoblePupi). Gracias ♥

Sin relación con Blizzard Entertainment. World of Warcraft es marca registrada de Blizzard Entertainment, Inc. Licencia MIT.
