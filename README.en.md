# Bingo de la Guild

A weekly bingo card to play with your guild in **WoW Forever**: 24 small, slightly silly goals ("die from a fall", "find a rare NPC", "group photo in a capital city") around a free center square. The whole guild gets the same card, everyone fills theirs while playing, and the window shows how the others are doing.

- Open it with `/bingo` or from the addon compartment by the minimap. `/bingo sync` asks the guild for their cards again.
- **17 goals mark themselves** (deaths, levels, a dungeon boss, quests, new zones, a duel, a letter, a flight, grouping with a guildmate, a blue item, a rare NPC, days played, the auction house, a group screenshot). **19 you mark yourself**, the ones the game cannot know about. It is a game among friends: honor system.
- **Bingo** is a full row, column or diagonal. You get a center-screen alert and a button to announce it in guild chat (only when you press it).
- **A new card every weekly reset**, at the same moment for the whole realm. Hover a square to see which guildmates already have it. Without a guild the card is just yours.

**What it sends**: only on the GUILD channel, a short text like `C|1|1762300800|0000011111001000000000000` (version, week, one digit per square). What arrives is parsed with patterns and stored as text, never run. Messages from other channels, malformed, from another week, too long or from yourself are dropped; at most 5 messages per 10 seconds per sender; at most 1000 cards (a guild's maximum). It never writes in chat by itself. Trial accounts cannot send addon messages in Forever: the addon notices, does not try, and tells you.

**Tested**: every API it uses was checked against Forever 1.60.1's dumps and UI source (`tools/check_api.py`); forever-lint only shows the FL012 note (trial accounts), which is handled; Addon Sentry finds no risk signals; 57 tests run two or more clients side by side in Lua 5.1 and pass messages between them. **Not tested in the game** (no Forever client here): how the window looks, that `C_DateAndTime.GetSecondsUntilWeeklyReset` gives Forever's reset (otherwise it falls back to Monday-to-Monday UTC weeks), that the goal events fire as in other clients, and that the announce button can post in guild chat.

Not affiliated with Blizzard Entertainment. MIT license.
