# Broadside Bots

Pirates! + Mayflower + Oregon Trail, in Godot 4. One captain, any role, eastern Caribbean, 1675. Make your fortune, become governor of your own island, and retire alive. Or keep the island as a pirate base and carry on.

Part of the Precog app suite: `broadside-bots.apps.precogsoftwareservices.com`. Full spec lives in the project doc `claude/broadside-bots.md`.

## v0.2.1
- **Market basket:** +/- per good and store, a running quote (spend, take, chest after, hold after) and one Approve. It says "No room" or "No coin" when + is barred.
- **Profit per ton:** the price you paid is tracked per good (prize goods cost nothing). Each line shows what selling here makes on a ton, and every sale reports its profit or loss.
- **Pictures:** drawn icons for goods and stores, with green ▼ when cheap here and red ▲ when dear. Bars for hull, rig, crew, health, morale, food, water and hold.
- **A proper chart:** coastlines of the Lesser Antilles, Puerto Rico, Hispaniola's east end and the Spanish Main, at true shape. The chart sits beside the controls on a wide screen.
- **The trade wind:** steady from the ENE. Westward runs are quick and beating east is slow; a fore-and-aft rig beats better than a square one. Each port shows leagues, a range of days and the point of sail.

## v0.2
- **Four careers:** Trader, Pirate, Privateer and Navy, under any of England, France, the Dutch or Spain. You can switch: buy a letter of marque, take a commission, resign, buy a pardon (or the King's, in 1688 and 1717–18), or run up the black flag at sea.
- **Nations and the recorded wars** from 1672 to 1720 decide friend and foe. Allies are nations at war with a common enemy. Your standing with each nation (Hostile, Neutral, Friendly, Honoured) opens or closes its ports, decides whether its navy hunts you, and moves when you fight. Hitting a nation's enemies pleases it and its allies; hitting a friend is betrayal. Every encounter previews who will think what if you take her.
- **Pirates have nationalities.** Brethren of your own nation leave a pirate be, and a pirate in favour with a crown can use its ports.
- **Real-time battles in 3D.** Steady wind and points of sail matter: a fore-and-aft sloop points ~45° off the wind, a square-rigger ~65°. Broadsides only bear abeam; round, chain and grape behave differently; reload times depend on crew. You can ram, grapple and board, and repel boarders. Merchants run, and strike once a stronger ship runs them down. Change orders mid-fight, or play it back at 1–64×.
- **Voyages, Oregon Trail style** (unchanged from v0), plus a shipyard and Navy pay, victuals, prize money (3/8) and promotion.

## Layout
```
scripts/world.gd       static data: ports, goods, ships, wars, personalities
scripts/game_state.gd  one career's state
scripts/sim.gd         all rules (pure, headless-testable)
scripts/main.gd        UI (chart + controls), built in code
scripts/battle.gd      the sea fight (pure, headless-testable)
scripts/battle_view.gd 3D view of a fight, HUD, orders
scripts/good_icon.gd   drawn icons for goods and stores
scripts/gauge.gd       labelled bars
tests/run_tests.gd     unit checks + career sweep per role
tests/policy.gd        the simple captain the sweep uses
tests/ui_smoke.gd      drives the UI headless
```

## Run / test / export
```
godot --path .                                   # play
godot --headless --path . -s tests/run_tests.gd  # tests + sweep
godot --headless --path . -s tests/ui_smoke.gd
godot --headless --path . --export-release Web build/web/index.html   # needs 4.3 export templates
```
Serve `build/web/` as static files (no thread support needed, so no COOP/COEP headers).
