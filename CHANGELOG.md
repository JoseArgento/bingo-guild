# Changelog

## 0.2.0 (unreleased)

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
