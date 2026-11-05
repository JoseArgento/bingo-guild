# Changelog

## 0.2.0 (unreleased)

- **Its own errors, kept** (Pergamino 5): a Lua error in a handler no longer reaches the player as a popup; it is kept in `BingoDeLaGuildDB.errors` (last 10), said once in the chat, and `/bingo errores` opens an "Errores" bookmark to copy it into a GitHub issue. The bookmark only shows while there is something kept.
- **Minimap button** of our own (Pergamino 2): left click opens the card, right click the league, drag it around the minimap; `/bingo minimapa on|off`. Pergamino 2 also brings wider bookmarks (the labels fit on one line) and scroll bars only when the page overflows.
- Without a guild (or with nobody else on the addon yet) the note sits right under "Your guild" instead of at the bottom of an empty list; "1 pt" and "1 goal imported" in the singular; clicking the book brings it over any other open book.
- Fixed: `Bindings.xml` is no longer listed in the TOC (the game reads it by name; listed, it logged XML warnings), and `UnitName("player")` keeps to one value.
- **The window is an open book** (the shared Pergamino skin, vendored in `Libs/Pergamino`): the card stamped on the left page, bookmarks for the card, the league and the officers' tools (the last one only for officers), the exchange as a parchment card, inviting empty states and tooltips on the bookmarks. No Blizzard frame templates left.
- **Language option**: `/bingo idioma es|en|auto`, kept in the settings, so the addon can speak Spanish on an English client.
- Own icon in the addon compartment and a key binding to open the window (Key Bindings → AddOns).
- **Goals v3** (`POOL_VERSION` 3, 60 goals): each of Forever's nine new dungeons by name (they mark themselves from `GetInstanceInfo()` on an English client), one or three different new dungeons, a Legacy point (from `ACHIEVEMENT_EARNED` + `C_Traits.GetTraitCurrencyForAchievement`), a Skyborne at level 10, and manual ones: ping the group, sit at someone else's campfire, play with a gamepad, hide your second name, look at the game's damage meter. Players on 0.1.0 see a different card until they update.
- **Suggestions**: anyone proposes a goal (`/bingo sugerir`, or the button); officers collect them (50 at most, deduped per sender, same rate limits) and review them one by one.
- **Export / import** of the officers' goal list as text (`BINGO1:` header, one goal per line), validated like received goals.

## 0.1.0 (unreleased)

First version, for WoW Forever 1.60.1.

- A weekly 5x5 card, the same for the whole guild, drawn from 43 goals (17 mark themselves, seven are new to Forever: camping, blueprints, transmog, the new dungeons...).
- Cards shared over validated, rate-limited addon messages; marks only compared between players with the same card.
- Officers can write their own goals for the week and publish them; everyone's card gets them.
- League over the last weeks, bingo alerts, an "announce in guild" button (only on click), a new-week notice.
- Trial accounts listen without sending; throttled sends are retried.
