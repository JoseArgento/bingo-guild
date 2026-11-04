local _, ns = ...

-- English is the fallback; Spanish for esES and esMX. Goal texts live in Goals.lua.
local L = {
	TITLE = "Guild Bingo",
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
	HELP = "/bingo opens the card. /bingo sync asks the guild for their cards again.",
	COMPARTMENT = "Click to open your card.",
}

local es = {
	TITLE = "Bingo de la Guild",
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
	HELP = "/bingo abre el cartón. /bingo sync le vuelve a pedir los cartones a la guild.",
	COMPARTMENT = "Clic para abrir tu cartón.",
}

local locale = GetLocale()
ns.spanish = locale == "esES" or locale == "esMX"
if ns.spanish then
	for k, v in pairs(es) do
		L[k] = v
	end
end
ns.L = L
