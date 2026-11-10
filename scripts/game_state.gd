class_name GameState
extends RefCounted
## Everything about one captain's career. Pure data; rules live in Sim.

var rng := RandomNumberGenerator.new()

# Captain
var role := "Trader"          # Trader | Pirate | Privateer | Navy
var nation := "England"       # nationality; the flag you fly unless you're a pirate
var patron := ""              # Privateer: the power whose letter of marque you carry
var navy_rank := ""           # Navy: Lieutenant | Commander | Captain
var captain_name := "Captain Twist"
var age := 25.0
var day := 0                  # days since 1 Jan START_YEAR
var chest := 0.0              # ship's working money (pieces of eight)
var purse := 0.0              # captain's banked / shared-out personal wealth
var bounty := 0.0
var infamy := 0.0
var reputation := {}          # nation -> -100..100
var prizes_taken := 0
var ships_sunk := 0
var pirates_taken := 0
var days_since_prize := 0     # Navy: the Admiralty expects results
var last_pay_day := 0

# Ship and crew
var ship := {}
var owns_ship := true         # false while you command a ship of the Crown
var crew := 0
var health := 90.0            # crew average 0..100
var morale := 70.0            # 0..100
var pay_owed := 0.0
var days_since_fresh := 0
var days_since_plunder := 0
var stores := {}              # store id -> tons
var cargo := {}               # good id -> tons
var basis := {}               # good id -> average price paid per ton (prize goods cost nothing)

# Position
var location := ""            # port id, or "" at sea
var voyage := {}              # {from, to, total_nm, done_nm}
var pace := "steady"          # easy | steady | crowd
var rations := "full"         # full | half | short
var rum_ration := true

# World
var markets := {}             # port id -> {good -> stock}
var journal: Array[String] = []
var war_note := ""            # last war/peace headline seen

# End state
var alive := true
var ended := false
var end_reason := ""

# Current encounter, empty when none
var encounter := {}

func say(msg: String) -> void:
	journal.append("%s — %s" % [Sim.date_string(self), msg])
	if journal.size() > 200:
		journal.pop_front()

func cargo_used() -> float:
	var t := 0.0
	for k in stores:
		t += float(stores[k])
	for k in cargo:
		t += float(cargo[k])
	return t

func cargo_free() -> float:
	return float(ship["cargo"]) - cargo_used()

func at_sea() -> bool:
	return location == ""

func year() -> int:
	return World.START_YEAR + int(day / 365)

func rep(n: String) -> int:
	return int(reputation.get(n, 0))

func add_rep(n: String, d: int) -> void:
	if reputation.has(n):
		reputation[n] = clamp(int(reputation[n]) + d, -100, 100)

## The flag other ships judge you by: your patron's for a privateer,
## your nation's for a trader or naval officer, none for a pirate.
func flag() -> String:
	match role:
		"Pirate":
			return ""
		"Privateer":
			return patron
		_:
			return nation
