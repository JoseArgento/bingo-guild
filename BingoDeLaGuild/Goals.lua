local _, ns = ...

-- The goals a card is drawn from. Every player of a guild draws the same 24 for the week from this list, so
-- the list is part of the card: change it (add, remove, reorder) and bump POOL_VERSION, or two versions of
-- the addon would show different cards and compare marks that mean different things.
ns.POOL_VERSION = 2 -- 2: goals of WoW Forever (camping, blueprints, the new dungeons...)

-- count = the counter that marks it by itself (Events.lua), need = how many. No count: the player marks it.
ns.GOALS = {
	-- they mark themselves
	{ id = "die1", count = "die", need = 1, es = "Morir", en = "Die" },
	{ id = "die3", count = "die", need = 3, es = "Morir 3 veces", en = "Die 3 times" },
	{ id = "lvl1", count = "level", need = 1, es = "Subir un nivel", en = "Gain a level" },
	{ id = "lvl3", count = "level", need = 3, es = "Subir 3 niveles", en = "Gain 3 levels" },
	{ id = "boss", count = "boss", need = 1, es = "Matar a un jefe de mazmorra", en = "Kill a dungeon boss" },
	{ id = "q10", count = "quest", need = 10, es = "Entregar 10 misiones", en = "Turn in 10 quests" },
	{ id = "q25", count = "quest", need = 25, es = "Entregar 25 misiones", en = "Turn in 25 quests" },
	{ id = "shot", count = "groupshot", need = 1, es = "Sacar una captura en grupo", en = "Take a screenshot in a group" },
	{ id = "zone5", count = "zone", need = 5, es = "Pisar 5 zonas distintas", en = "Set foot in 5 different zones" },
	{ id = "duel", count = "duel", need = 1, es = "Batirse a duelo", en = "Fight a duel" },
	{ id = "mail", count = "mail", need = 1, es = "Mandar una carta", en = "Send a letter" },
	{ id = "taxi", count = "taxi", need = 1, es = "Viajar en un vuelo", en = "Take a flight" },
	{ id = "gparty", count = "guildgroup", need = 1, es = "Hacer grupo con alguien de la guild", en = "Group up with a guildmate" },
	{ id = "blue", count = "blueloot", need = 1, es = "Conseguir un ítem azul o mejor", en = "Get a blue item or better" },
	{ id = "rare", count = "rare", need = 1, es = "Encontrar un PNJ raro", en = "Find a rare NPC" },
	{ id = "days3", count = "day", need = 3, es = "Jugar 3 días distintos", en = "Play on 3 different days" },
	{ id = "ah", count = "auction", need = 1, es = "Pasar por la casa de subastas", en = "Visit the auction house" },
	-- the player marks them
	{ id = "fall", es = "Morir de una caída", en = "Die from a fall" },
	{ id = "guard", es = "Que te mate un guardia", en = "Get killed by a guard" },
	{ id = "lost", es = "Perderte en una cueva", en = "Get lost in a cave" },
	{ id = "dance", es = "Bailar en una taberna", en = "Dance in a tavern" },
	{ id = "fishjunk", es = "Pescar algo que no sea un pescado", en = "Fish up something that is not a fish" },
	{ id = "helplow", es = "Ayudar a alguien de nivel más bajo", en = "Help someone of a lower level" },
	{ id = "five", es = "Juntarse 5 de la guild en un mismo lugar", en = "Get 5 guildmates in one place" },
	{ id = "photo", es = "Foto grupal en una capital", en = "Group photo in a capital city" },
	{ id = "ghost", es = "Correr como fantasma más de 2 minutos", en = "Run as a ghost for over 2 minutes" },
	{ id = "bags", es = "Quedarte sin lugar en las bolsas", en = "Run out of bag space" },
	{ id = "escort", es = "Terminar una misión de escolta", en = "Finish an escort quest" },
	{ id = "notank", es = "Entrar a una mazmorra sin tanque", en = "Enter a dungeon without a tank" },
	{ id = "cook", es = "Cocinar algo para el grupo", en = "Cook something for the group" },
	{ id = "stranger", es = "Que te salude alguien que no conocés", en = "Get waved at by a stranger" },
	{ id = "wipe", es = "Que muera todo el grupo", en = "The whole group dies" },
	{ id = "repair", es = "Que se te rompa la armadura", en = "Get your armor broken" },
	{ id = "wrongway", es = "Ir a la zona equivocada", en = "Go to the wrong zone" },
	{ id = "gift", es = "Regalarle algo a alguien de la guild", en = "Give a guildmate a gift" },
	{ id = "joke", es = "Hacer reír a la guild en el chat", en = "Make the guild laugh in chat" },
	-- things that are new in Forever
	{ id = "camp", es = "Armar un campamento", en = "Set up a campsite" },
	{ id = "fire", es = "Descansar junto a una fogata con alguien", en = "Rest by a campfire with someone" },
	{ id = "blueprint", es = "Conseguir un plano", en = "Get a blueprint" },
	{ id = "wellfed", es = "Comer algo cocinado antes de pelear", en = "Eat something cooked before a fight" },
	{ id = "transmog", es = "Transfigurar algo", en = "Transmog something" },
	{ id = "newdungeon", es = "Hacer una de las mazmorras nuevas", en = "Run one of the new dungeons" },
	{ id = "skyborne", es = "Agrupar con alguien Skyborne", en = "Group with a Skyborne" },
}

ns.GOAL = {}
for i, g in ipairs(ns.GOALS) do
	g.index = i
	g.need = g.need or 1
	ns.GOAL[g.id] = g
end

function ns.GoalText(g)
	return ns.spanish and g.es or g.en
end

-- A goal by id: one of the list, or one an officer wrote for this week's card ("c1", "c2"...).
function ns.Goal(id)
	if ns.GOAL[id] then
		return ns.GOAL[id]
	end
	local i = type(id) == "string" and tonumber(id:match("^c(%d+)$"))
	local card = i and ns.OfficerCard and ns.OfficerCard()
	local text = card and card.goals[i]
	if text then
		return { id = id, es = text, en = text, need = 1, custom = true }
	end
end

-- An officer's goal as it may travel and be shown: no "|" (the message separator, and the game's escape
-- character for colors and links), no control characters, at most 50 bytes without cutting a letter.
function ns.CleanGoal(text)
	if type(text) ~= "string" then
		return nil
	end
	text = strtrim((text:gsub("|", ""):gsub("%c", " ")))
	local out, n = {}, 0
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		if n + #ch > 50 then
			break
		end
		out[#out + 1] = ch
		n = n + #ch
	end
	text = table.concat(out)
	return text ~= "" and text or nil
end
