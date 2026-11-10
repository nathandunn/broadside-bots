class_name GameState
extends RefCounted
## Everything about one captain's career. Pure data; rules live in Sim.

var rng := RandomNumberGenerator.new()

# Captain
var role := "Trader"          # Trader | Pirate (v0)
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

# Ship and crew
var ship := {}
var crew := 0
var health := 90.0            # crew average 0..100
var morale := 70.0            # 0..100
var pay_owed := 0.0
var days_since_fresh := 0
var days_since_plunder := 0
var stores := {}              # store id -> tons
var cargo := {}               # good id -> tons

# Position
var location := ""            # port id, or "" at sea
var voyage := {}              # {from, to, total_nm, done_nm}
var pace := "steady"          # easy | steady | crowd
var rations := "full"         # full | half | short
var rum_ration := true

# World
var markets := {}             # port id -> {good -> stock}
var journal: Array[String] = []

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
