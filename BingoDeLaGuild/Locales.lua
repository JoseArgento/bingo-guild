local _, ns = ...

-- English is the fallback; Spanish for esES and esMX. Goal texts live in Goals.lua.
local L = {
	BINDING_TOGGLE = "Open / close",
	TITLE = "Guild Bingo",
	TAB_CARTON = "Card",
	TAB_LIGA = "League",
	TAB_OFICIALES = "Officers",
	TAB_CARTON_TIP = "This week's card and how your guild is doing.",
	TAB_LIGA_TIP = "Points of the last weeks: one per square, five more per line.",
	TAB_OFICIALES_TIP = "Write this week's goals, review the guild's suggestions, export or import the list.",
	CARD_HINT = "Click a square when it happens; the ones that mark themselves say so in their tooltip. A row, a column or a diagonal is a BINGO.",
	NO_GUILD_HINT = "You can still play: the squares are yours to mark. Join a guild and the card becomes everyone's.",
	NOBODY_HINT = "Whoever installs it gets the same card and sees yours.",
	LEAGUE_HINT = "Only guildmates with the addon count; weeks older than five weeks are forgotten.",
	OFFICERS_HEAD = "Officers' card",
	OFFICERS_HINT = "Write up to 24 goals for the week and publish: the whole guild gets them, filled up with goals from the list.",
	NO_DRAFTS = "No goals written yet. The guild plays the list's card.",
	DRAFTS_RIGHT_CLICK = "Right-click a goal to clear the list.",
	LANG_SET = "Language: %s. Reload the interface for the chat texts to follow (/reload).",
	LANG_HELP = "/bingo idioma es | en | auto",
	WEEK_UNTIL = "Card for the week, until %s",
	MARKED = "%d of 25",
	BINGO = "BINGO!",
	BINGO_LINES = "BINGO! (%d lines)",
	GUILD = "Your guild",
	NO_GUILD = "You are not in a guild: this card is just yours.",
	TRIAL = "Trial accounts cannot send addon messages: you see your guildmates' cards, they do not see yours.",
	NOBODY = "Nobody else has the addon yet. Tell your guild!",
	ANNOUNCE = "Announce in guild",
	ANNOUNCE_TEXT = "I got a BINGO on this week's guild card! (%d of 25)",
	FREE = "Free square",
	AUTO = "Marks itself.",
	MANUAL = "Click it when it happens. Click again to unmark.",
	AUTO_TOO = "It marks itself; you can also click it.",
	PROGRESS = "Progress: %d of %d",
	HAVE_IT = "Also done by: %s",
	SOMEONE_BINGO = "%s called BINGO on the guild card!",
	YOU_BINGO = "BINGO! Line complete.",
	OTHER_VERSION = "%s has another version of the addon: their card is different.",
	RESYNC = "Asked the guild for their cards.",
	CANT_SEND = "Could not send your card right now; it will try again.",
	HELP = "/bingo opens the card. /bingo sync asks the guild for their cards again. /bingo liga shows the league. /bingo sugerir <text> proposes a goal to the officers. Officers: /bingo meta <text>, /bingo metas, /bingo borrar, /bingo publicar, /bingo sugerencias, /bingo exportar. /bingo idioma es|en|auto picks the language.",
	COMPARTMENT = "Click to open your card.",
	LEAGUE = "League",
	LEAGUE_HEAD = "League (last weeks)",
	POINTS = "%d pts",
	POINTS_1 = "1 pt",
	ADD_GOAL = "Add a goal",
	GOAL_PROMPT = "A goal for this week's guild card (up to 50 letters):",
	PUBLISH = "Publish card (%d)",
	OFFICER_CARD = "%s published this week's guild card.",
	CARD_BY = "card by %s",
	NEW_CARD = "New week, new card! /bingo to see it.",
	NOT_OFFICER = "Only officers can publish the guild's card.",
	DRAFTS = "Goals for the card (%d): %s",
	SUGGEST = "Suggest a goal",
	SUGGEST_PROMPT = "Suggest a goal to the officers (up to 50 letters):",
	SUGGESTED = "Suggestion sent to the officers.",
	REVIEW_BTN = "Suggestions (%d)",
	REVIEW = "%s suggests: %s",
	SUGGESTIONS = "Suggestions from the guild (%d):",
	EXCHANGE = "Export / import goals",
	EXCHANGE_HINT = "Copy this text to keep the goal list, or paste one and press Import: it replaces the goals, up to 24.",
	IMPORT = "Import",
	IMPORTED = "%d goals imported.",
	IMPORTED_1 = "1 goal imported.",
	NOT_AN_EXPORT = "That is not an exported goal list (it starts with BINGO1:).",
}

local es = {
	BINDING_TOGGLE = "Abrir / cerrar",
	TITLE = "Bingo de la Guild",
	TAB_CARTON = "Cartón",
	TAB_LIGA = "Liga",
	TAB_OFICIALES = "Oficiales",
	TAB_CARTON_TIP = "El cartón de esta semana y cómo viene tu guild.",
	TAB_LIGA_TIP = "Puntos de las últimas semanas: uno por casilla, cinco más por línea.",
	TAB_OFICIALES_TIP = "Escribir las metas de la semana, revisar las sugerencias de la guild, exportar o importar la lista.",
	CARD_HINT = "Hacé clic en una casilla cuando pase; las que se marcan solas lo dicen en su tooltip. Una fila, una columna o una diagonal es BINGO.",
	NO_GUILD_HINT = "Igual podés jugar: las casillas son tuyas. Cuando entres a una guild, el cartón pasa a ser el de todos.",
	NOBODY_HINT = "El que lo instale recibe el mismo cartón y ve el tuyo.",
	LEAGUE_HINT = "Cuentan solo los de la guild con el addon; las semanas de hace más de cinco se olvidan.",
	OFFICERS_HEAD = "Cartón de los oficiales",
	OFFICERS_HINT = "Escribí hasta 24 metas para la semana y publicá: toda la guild las recibe, completadas con metas de la lista.",
	NO_DRAFTS = "Todavía no hay metas escritas. La guild juega el cartón de la lista.",
	DRAFTS_RIGHT_CLICK = "Clic derecho en una meta para vaciar la lista.",
	LANG_SET = "Idioma: %s. Recargá la interfaz para que los textos del chat lo sigan (/reload).",
	LANG_HELP = "/bingo idioma es | en | auto",
	WEEK_UNTIL = "Cartón de la semana, hasta el %s",
	MARKED = "%d de 25",
	BINGO = "¡BINGO!",
	BINGO_LINES = "¡BINGO! (%d líneas)",
	GUILD = "Tu guild",
	NO_GUILD = "No estás en una guild: este cartón es solo tuyo.",
	TRIAL = "Las cuentas de prueba no pueden mandar mensajes de addon: ves los cartones de tu guild, pero ellos no ven el tuyo.",
	NOBODY = "Nadie más tiene el addon todavía. ¡Pasáselo a la guild!",
	ANNOUNCE = "Anunciar en la guild",
	ANNOUNCE_TEXT = "¡Canté BINGO en el cartón de la guild de esta semana! (%d de 25)",
	FREE = "Casilla libre",
	AUTO = "Se marca sola.",
	MANUAL = "Hacé clic cuando pase. Otro clic la desmarca.",
	AUTO_TOO = "Se marca sola; también podés hacer clic.",
	PROGRESS = "Progreso: %d de %d",
	HAVE_IT = "También la tienen: %s",
	SOMEONE_BINGO = "¡%s cantó BINGO en el cartón de la guild!",
	YOU_BINGO = "¡BINGO! Línea completa.",
	OTHER_VERSION = "%s tiene otra versión del addon: su cartón es distinto.",
	RESYNC = "Le pedí a la guild sus cartones.",
	CANT_SEND = "No pude mandar tu cartón ahora; lo vuelve a intentar.",
	HELP = "/bingo abre el cartón. /bingo sync le vuelve a pedir los cartones a la guild. /bingo liga muestra la liga. /bingo sugerir <texto> le propone una meta a los oficiales. Oficiales: /bingo meta <texto>, /bingo metas, /bingo borrar, /bingo publicar, /bingo sugerencias, /bingo exportar.",
	COMPARTMENT = "Clic para abrir tu cartón.",
	LEAGUE = "Liga",
	LEAGUE_HEAD = "Liga (últimas semanas)",
	POINTS = "%d pts",
	POINTS_1 = "1 pt",
	ADD_GOAL = "Agregar meta",
	GOAL_PROMPT = "Una meta para el cartón de la guild de esta semana (hasta 50 letras):",
	PUBLISH = "Publicar cartón (%d)",
	OFFICER_CARD = "%s publicó el cartón de la guild de esta semana.",
	CARD_BY = "cartón de %s",
	NEW_CARD = "¡Semana nueva, cartón nuevo! /bingo para verlo.",
	NOT_OFFICER = "Solo los oficiales pueden publicar el cartón de la guild.",
	DRAFTS = "Metas para el cartón (%d): %s",
	SUGGEST = "Sugerir meta",
	SUGGEST_PROMPT = "Sugerile una meta a los oficiales (hasta 50 letras):",
	SUGGESTED = "Sugerencia mandada a los oficiales.",
	REVIEW_BTN = "Sugerencias (%d)",
	REVIEW = "%s sugiere: %s",
	SUGGESTIONS = "Sugerencias de la guild (%d):",
	EXCHANGE = "Exportar / importar metas",
	EXCHANGE_HINT = "Copiá este texto para guardar la lista de metas, o pegá una y apretá Importar: reemplaza las metas, hasta 24.",
	IMPORT = "Importar",
	IMPORTED = "%d metas importadas.",
	IMPORTED_1 = "1 meta importada.",
	NOT_AN_EXPORT = "Eso no es una lista exportada (empieza con BINGO1:).",
}

-- L is one table for the whole addon: SetLanguage rewrites it in place (every file keeps its local L), so the
-- language can follow the client (auto) or what the player chose in the settings, even on an English client.
local en = {}
for k, v in pairs(L) do
	en[k] = v
end
ns.L = L

function ns.SetLanguage(lang)
	if lang ~= "es" and lang ~= "en" then
		lang = "auto"
	end
	local locale = GetLocale()
	ns.lang = lang
	ns.spanish = lang == "es" or (lang == "auto" and (locale == "esES" or locale == "esMX"))
	for k, v in pairs(en) do
		L[k] = v
	end
	if ns.spanish then
		for k, v in pairs(es) do
			L[k] = v
		end
	end
	if ns.Fire then
		ns.Fire("language")
	end
end
ns.SetLanguage("auto")
