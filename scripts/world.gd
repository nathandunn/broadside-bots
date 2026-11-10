class_name World
extends RefCounted
## Static world data: the eastern Caribbean from 1675, with the recorded
## wars between the colonial powers driving who is friend and who is foe.

const VERSION := "0.2.1"
const START_YEAR := 1675

## Trade goods. base = pieces of eight per ton.
const GOODS := {
	"sugar":   {"name": "Sugar",          "base": 60},
	"tobacco": {"name": "Tobacco",        "base": 90},
	"rum":     {"name": "Rum",            "base": 70},
	"cloth":   {"name": "Cloth",          "base": 140},
	"timber":  {"name": "Timber",         "base": 30},
	"spices":  {"name": "Spices",         "base": 260},
	"silver":  {"name": "Pearls & plate", "base": 900},
}

## Ship's stores (also take hold space). price per ton.
const STORES := {
	"food":     {"name": "Provisions",    "price": 25},
	"water":    {"name": "Fresh water",   "price": 3},
	"powder":   {"name": "Powder & shot", "price": 120},
	"spares":   {"name": "Timber & cordage", "price": 40},
	"medicine": {"name": "Medicine chest", "price": 400},
}

const NATIONS := ["England", "France", "Dutch", "Spain", "Denmark"]
## The four powers you can serve or sail under. Denmark (St Thomas) stays neutral.
const POWERS := ["England", "France", "Dutch", "Spain"]
const ADJ := {"England": "English", "France": "French", "Dutch": "Dutch", "Spain": "Spanish", "Denmark": "Danish"}
const COLOUR := {
	"England": Color(0.80, 0.20, 0.20), "France": Color(0.25, 0.40, 0.90),
	"Dutch": Color(0.95, 0.55, 0.15), "Spain": Color(0.95, 0.85, 0.20),
	"Denmark": Color(0.85, 0.85, 0.85),
}

## Recorded wars touching the West Indies, as [a, b, from, to] in fractional
## years. Nations at war with a common enemy (and not with each other) count
## as allies. Peace treaties: Westminster 1674, Nijmegen 1678, Ratisbon 1684,
## Ryswick 1697, Utrecht 1713, Rastatt/Baden 1714, The Hague 1720.
const WARS := [
	["England", "Dutch", 1672.2, 1674.15],   # Third Anglo-Dutch War
	["France", "Dutch", 1672.3, 1678.6],     # Franco-Dutch War
	["France", "Spain", 1673.8, 1678.7],
	["France", "Spain", 1683.8, 1684.6],     # War of the Reunions
	["France", "Dutch", 1688.9, 1697.7],     # Nine Years' War
	["France", "England", 1689.4, 1697.7],
	["France", "Spain", 1689.3, 1697.7],
	["France", "England", 1702.4, 1713.3],   # War of the Spanish Succession
	["France", "Dutch", 1702.4, 1713.3],
	["Spain", "England", 1702.4, 1713.5],
	["Spain", "Dutch", 1702.4, 1714.5],
	["Spain", "England", 1718.95, 1720.1],   # War of the Quadruple Alliance
	["Spain", "France", 1719.0, 1720.1],
]

## Royal pardons on offer to pirates who surrender to a governor of that nation:
## James II's proclamation (1688) and George I's Act of Grace (1717–18).
const PARDONS := [["England", 1688.0, 1689.0], ["England", 1717.7, 1718.7]]

const PORTS := [
	{"id": "bridgetown",   "name": "Bridgetown, Barbados",      "nation": "England", "lat": 13.10, "lon": -59.62,
		"produces": ["sugar", "rum"], "wants": ["cloth", "timber"], "haven": false},
	{"id": "st_johns",     "name": "St John's, Antigua",        "nation": "England", "lat": 17.12, "lon": -61.85,
		"produces": ["sugar"], "wants": ["cloth", "spices"], "haven": false},
	{"id": "saint_pierre", "name": "Saint-Pierre, Martinique",  "nation": "France",  "lat": 14.74, "lon": -61.18,
		"produces": ["sugar", "tobacco"], "wants": ["cloth", "silver"], "haven": false},
	{"id": "basse_terre",  "name": "Basse-Terre, Guadeloupe",   "nation": "France",  "lat": 15.99, "lon": -61.73,
		"produces": ["tobacco", "timber"], "wants": ["cloth", "rum"], "haven": false},
	{"id": "oranjestad",   "name": "Oranjestad, St Eustatius",  "nation": "Dutch",   "lat": 17.48, "lon": -62.98,
		"produces": ["cloth", "spices"], "wants": ["sugar", "tobacco"], "haven": false},
	{"id": "willemstad",   "name": "Willemstad, Curaçao",       "nation": "Dutch",   "lat": 12.11, "lon": -68.93,
		"produces": ["cloth", "spices"], "wants": ["tobacco", "timber"], "haven": false},
	{"id": "port_of_spain","name": "Port of Spain, Trinidad",   "nation": "Spain",   "lat": 10.65, "lon": -61.51,
		"produces": ["tobacco", "timber"], "wants": ["cloth", "rum"], "haven": false},
	{"id": "la_asuncion",  "name": "La Asunción, Margarita",    "nation": "Spain",   "lat": 11.03, "lon": -63.86,
		"produces": ["silver"], "wants": ["cloth", "spices"], "haven": false},
	{"id": "st_thomas",    "name": "Charlotte Amalie, St Thomas","nation": "Denmark", "lat": 18.34, "lon": -64.93,
		"produces": [], "wants": ["silver", "spices"], "haven": true},
]

## The NE trade wind: steady from the ENE across the eastern Caribbean all
## year (bearing it blows FROM, degrees true).
const TRADE_WIND_FROM := 70.0

## Coarse coastlines inside the chart (lon, lat), from modern charts. The
## Spanish Main runs along the bottom; Hispaniola's east end sits top left.
const LAND := [
	# Tierra Firme: Venezuela from Coro to the Orinoco mouths (closed along the chart's foot)
	[Vector2(-70.0, 12.0), Vector2(-69.8, 11.9), Vector2(-69.9, 11.45), Vector2(-69.3, 11.5), Vector2(-68.4, 10.9),
	 Vector2(-68.0, 10.5), Vector2(-67.0, 10.6), Vector2(-66.1, 10.6), Vector2(-65.0, 10.1), Vector2(-64.2, 10.5),
	 Vector2(-63.5, 10.65), Vector2(-62.3, 10.7), Vector2(-61.85, 10.72), Vector2(-62.4, 10.5), Vector2(-62.6, 10.15),
	 Vector2(-62.0, 9.95), Vector2(-61.2, 9.75), Vector2(-60.6, 9.5), Vector2(-70.0, 9.5)],
	[Vector2(-61.93, 10.7), Vector2(-61.6, 10.75), Vector2(-60.95, 10.85), Vector2(-60.9, 10.15), Vector2(-61.0, 10.05),
	 Vector2(-61.9, 10.05), Vector2(-61.55, 10.25), Vector2(-61.45, 10.55)],                       # Trinidad
	[Vector2(-60.85, 11.15), Vector2(-60.5, 11.35), Vector2(-60.52, 11.25), Vector2(-60.8, 11.08)], # Tobago
	[Vector2(-64.4, 11.0), Vector2(-64.2, 11.15), Vector2(-63.8, 11.15), Vector2(-63.8, 10.92), Vector2(-64.1, 10.9)], # Margarita
	[Vector2(-69.16, 12.39), Vector2(-69.05, 12.38), Vector2(-68.73, 12.06), Vector2(-68.78, 12.02), Vector2(-69.0, 12.12),
	 Vector2(-69.17, 12.3)],                                                                         # Curaçao
	[Vector2(-68.42, 12.3), Vector2(-68.2, 12.25), Vector2(-68.2, 12.03), Vector2(-68.3, 12.05)],   # Bonaire
	[Vector2(-70.0, 12.62), Vector2(-69.87, 12.42), Vector2(-70.0, 12.45)],                          # Aruba (edge)
	[Vector2(-61.8, 12.0), Vector2(-61.6, 12.25), Vector2(-61.6, 12.05), Vector2(-61.75, 11.98)],   # Grenada
	[Vector2(-61.27, 13.38), Vector2(-61.12, 13.38), Vector2(-61.12, 13.15), Vector2(-61.25, 13.15)], # St Vincent
	[Vector2(-59.65, 13.33), Vector2(-59.43, 13.2), Vector2(-59.48, 13.05), Vector2(-59.63, 13.05)], # Barbados
	[Vector2(-61.0, 14.1), Vector2(-60.88, 14.1), Vector2(-60.88, 13.72), Vector2(-61.08, 13.78)],   # St Lucia
	[Vector2(-61.23, 14.88), Vector2(-60.95, 14.85), Vector2(-60.82, 14.6), Vector2(-60.85, 14.4), Vector2(-61.08, 14.45),
	 Vector2(-61.2, 14.6)],                                                                          # Martinique
	[Vector2(-61.48, 15.63), Vector2(-61.25, 15.58), Vector2(-61.25, 15.22), Vector2(-61.38, 15.2), Vector2(-61.48, 15.4)], # Dominica
	[Vector2(-61.8, 16.35), Vector2(-61.6, 16.3), Vector2(-61.55, 16.0), Vector2(-61.7, 15.95), Vector2(-61.8, 16.1)], # Guadeloupe, Basse-Terre
	[Vector2(-61.55, 16.5), Vector2(-61.2, 16.35), Vector2(-61.2, 16.25), Vector2(-61.55, 16.22)],  # Guadeloupe, Grande-Terre
	[Vector2(-62.24, 16.81), Vector2(-62.14, 16.78), Vector2(-62.15, 16.68), Vector2(-62.23, 16.7)], # Montserrat
	[Vector2(-61.9, 17.17), Vector2(-61.72, 17.17), Vector2(-61.67, 17.05), Vector2(-61.88, 17.0)], # Antigua
	[Vector2(-61.88, 17.72), Vector2(-61.75, 17.65), Vector2(-61.75, 17.55), Vector2(-61.86, 17.6)], # Barbuda
	[Vector2(-62.87, 17.42), Vector2(-62.7, 17.33), Vector2(-62.58, 17.1), Vector2(-62.66, 17.08), Vector2(-62.82, 17.28)], # St Kitts & Nevis
	[Vector2(-63.0, 17.53), Vector2(-62.94, 17.51), Vector2(-62.95, 17.45), Vector2(-63.0, 17.46)], # St Eustatius
	[Vector2(-63.15, 18.12), Vector2(-62.98, 18.1), Vector2(-63.0, 18.0), Vector2(-63.15, 18.03)],  # St Martin
	[Vector2(-63.17, 18.17), Vector2(-62.97, 18.27), Vector2(-62.97, 18.22), Vector2(-63.12, 18.14)], # Anguilla
	[Vector2(-65.05, 18.38), Vector2(-64.83, 18.38), Vector2(-64.83, 18.31), Vector2(-65.05, 18.31)], # St Thomas
	[Vector2(-64.8, 18.37), Vector2(-64.68, 18.36), Vector2(-64.68, 18.31), Vector2(-64.8, 18.31)], # St John
	[Vector2(-64.7, 18.45), Vector2(-64.55, 18.45), Vector2(-64.55, 18.4), Vector2(-64.7, 18.4)],   # Tortola
	[Vector2(-64.9, 17.78), Vector2(-64.57, 17.77), Vector2(-64.57, 17.68), Vector2(-64.9, 17.68)], # St Croix
	[Vector2(-67.27, 18.5), Vector2(-65.62, 18.38), Vector2(-65.6, 18.2), Vector2(-65.85, 18.0), Vector2(-66.5, 17.95),
	 Vector2(-67.2, 17.95), Vector2(-67.2, 18.15)],                                                  # Puerto Rico
	[Vector2(-65.58, 18.15), Vector2(-65.27, 18.13), Vector2(-65.27, 18.08), Vector2(-65.58, 18.1)], # Vieques
	[Vector2(-70.0, 19.0), Vector2(-68.9, 19.0), Vector2(-68.33, 18.6), Vector2(-68.7, 18.2), Vector2(-69.6, 18.4),
	 Vector2(-70.0, 18.25)],                                                                         # Hispaniola, east end
]

## Initial great-circle bearing from a to b, degrees true.
static func bearing_deg(a: Dictionary, b: Dictionary) -> float:
	var la1 := deg_to_rad(float(a["lat"]))
	var la2 := deg_to_rad(float(b["lat"]))
	var dlo := deg_to_rad(float(b["lon"]) - float(a["lon"]))
	var y := sin(dlo) * cos(la2)
	var x := cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dlo)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)

## Home port for each power.
const HOME := {"England": "bridgetown", "France": "saint_pierre", "Dutch": "oranjestad", "Spain": "port_of_spain"}

## Ship classes. knots = best speed (beam reach); rig "fore_aft" points ~45°
## off the wind, "square" only ~65° — so a sloop can claw to windward where a
## square-rigger can't follow. length in metres for the 3D view.
const SHIPS := {
	"sloop":       {"name": "Sloop",       "hull": 100, "guns": 8,  "crew_cap": 75,  "cargo": 40,  "speed": 1.15, "knots": 8.0, "rig": "fore_aft", "length": 18.0, "masts": 1, "price": 2500},
	"brigantine":  {"name": "Brigantine",  "hull": 140, "guns": 12, "crew_cap": 90,  "cargo": 90,  "speed": 1.05, "knots": 7.3, "rig": "fore_aft", "length": 24.0, "masts": 2, "price": 6000},
	"fluyt":       {"name": "Fluyt",       "hull": 120, "guns": 6,  "crew_cap": 24,  "cargo": 220, "speed": 0.90, "knots": 6.2, "rig": "square",   "length": 30.0, "masts": 3, "price": 4000},
	"merchantman": {"name": "Merchantman", "hull": 160, "guns": 10, "crew_cap": 40,  "cargo": 260, "speed": 0.85, "knots": 5.8, "rig": "square",   "length": 32.0, "masts": 3, "price": 7000},
	"frigate":     {"name": "Frigate",     "hull": 220, "guns": 24, "crew_cap": 160, "cargo": 120, "speed": 1.05, "knots": 7.6, "rig": "square",   "length": 40.0, "masts": 3, "price": 16000},
}

## Rival captain personalities (sim-core style traits, 0..1).
const PERSONALITIES := {
	"Cautious merchant":   {"aggression": 0.1, "caution": 0.9, "greed": 0.4, "honour": 0.7},
	"Stubborn merchant":   {"aggression": 0.4, "caution": 0.4, "greed": 0.6, "honour": 0.6},
	"Greedy pirate":       {"aggression": 0.6, "caution": 0.5, "greed": 0.9, "honour": 0.2},
	"Bloodthirsty pirate": {"aggression": 0.95,"caution": 0.15,"greed": 0.6, "honour": 0.1},
	"Dutiful navy":        {"aggression": 0.7, "caution": 0.3, "greed": 0.2, "honour": 0.9},
	"Bold privateer":      {"aggression": 0.75,"caution": 0.35,"greed": 0.8, "honour": 0.5},
}

## Names for the ship you start with.
const START_SHIPS := {
	"Trader":    {"England": "Good Hope", "France": "Bonne Espérance", "Dutch": "Goede Hoop", "Spain": "Buena Esperanza"},
	"Pirate":    {"England": "Revenge", "France": "Vengeance", "Dutch": "Wraak", "Spain": "Venganza"},
	"Privateer": {"England": "Bachelor's Delight", "France": "Hardi", "Dutch": "Vliegende Hert", "Spain": "San Rafael"},
	"Navy":      {"England": "HMS Swallow", "France": "L'Hirondelle", "Dutch": "Zwaluw", "Spain": "Golondrina"},
}

static func port_by_id(id: String) -> Dictionary:
	for p in PORTS:
		if p["id"] == id:
			return p
	return {}

static func year_of(day: int) -> float:
	return START_YEAR + day / 365.0

static func at_war(a: String, b: String, day: int) -> bool:
	if a == "" or b == "" or a == b:
		return false
	var y := year_of(day)
	for w in WARS:
		if ((w[0] == a and w[1] == b) or (w[0] == b and w[1] == a)) and y >= float(w[2]) and y < float(w[3]):
			return true
	return false

static func enemies_of(a: String, day: int) -> Array:
	var out := []
	for n in NATIONS:
		if at_war(a, n, day):
			out.append(n)
	return out

## Allies: at war with a common enemy, and not with each other.
static func allied(a: String, b: String, day: int) -> bool:
	if a == "" or b == "" or a == b or at_war(a, b, day):
		return false
	for e in enemies_of(a, day):
		if at_war(b, e, day):
			return true
	return false

## "war" | "ally" | "peace" | "self"
static func relation(a: String, b: String, day: int) -> String:
	if a == b:
		return "self"
	if at_war(a, b, day):
		return "war"
	if allied(a, b, day):
		return "ally"
	return "peace"

static func pardon_on_offer(nation: String, day: int) -> bool:
	var y := year_of(day)
	for p in PARDONS:
		if p[0] == nation and y >= float(p[1]) and y < float(p[2]):
			return true
	return false

static func standing(rep: int) -> String:
	if rep >= 60:
		return "Honoured"
	if rep >= 25:
		return "Friendly"
	if rep > -25:
		return "Neutral"
	if rep > -60:
		return "Hostile"
	return "Wanted"

## Great-circle distance in nautical miles.
static func distance_nm(a: Dictionary, b: Dictionary) -> float:
	var la1 := deg_to_rad(float(a["lat"]))
	var la2 := deg_to_rad(float(b["lat"]))
	var dla := la2 - la1
	var dlo := deg_to_rad(float(b["lon"]) - float(a["lon"]))
	var h := sin(dla / 2.0) ** 2 + cos(la1) * cos(la2) * sin(dlo / 2.0) ** 2
	return 2.0 * 3440.065 * asin(sqrt(h))
