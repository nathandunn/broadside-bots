# Broadside Bots

Pirates! + Mayflower + Oregon Trail, in Godot 4. One captain, any role, eastern Caribbean, 1675. Make your fortune, become governor of your own island, and retire alive. Or keep the island as a pirate base and carry on.

Part of the Precog app suite: `broadside-bots.apps.precogsoftwareservices.com`. Full spec lives in the project doc `claude/broadside-bots.md`.

## v0 (this release)
- **Roles:** Trader (fluyt, wages, honest ports) and Pirate (sloop, shares, St Thomas as haven). A trader who fires on a ship of a nation at peace turns pirate on the spot.
- **Voyage, Oregon Trail style:** daily ticks with pace (easy / steady / crowd sail), rations (full / half / short) and a rum ration. Food, water, powder, spares and medicine are tracked. Scurvy sets in after 6 weeks without fresh food; hurricane season runs June–November. Becalmings, fevers, desertion and mutiny all occur.
- **Ports:** nine ports with supply/demand markets that recover daily, plus shipwright, tavern, wages, bank/purse and resting ashore (with careening). Pirates fence at St Thomas and share out by the articles: captain 2 shares, common fund kept back first.
- **Cruising:** put out to hunt the sea lanes and come back, with "Make for port" to cut it short.
- **Encounters:** merchants, navies and pirates, each captained by a personality (aggression, caution, greed, honour). You can sail on, flee, trade, attack or strike colours.
- **Combat (auto-resolved, standing orders):** you choose range (close/long), shot (round/chain/grape), board and ram. Ramming hurts you too and locks hulls for boarding. Prizes give coin, cargo, stores and volunteers.
- **Retire** in any port. The epilogue is set by your net worth.

Coming next: v1 adds the 3D sea battle, Navy and Privateer roles, and role switching (marques, pardons, desertion). v2 adds the Atlantic crossing and Colonists, fleets, and your island as governor and home base. v3 adds the all-AI sim mode with stats.

## Layout
```
scripts/world.gd       static data: ports, goods, ships, wars, personalities
scripts/game_state.gd  one career's state
scripts/sim.gd         all rules (pure, headless-testable)
scripts/main.gd        UI (chart + controls), built in code
tests/run_tests.gd     unit checks + 100-career sweep per role
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
