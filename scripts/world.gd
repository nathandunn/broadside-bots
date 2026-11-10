class_name World
extends RefCounted
## Static world data for v0: the eastern Caribbean, c. 1675.

const VERSION := "0.1.0"
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

## Nations and who is at war in 1675 (Franco-Dutch War; Spain allied to the Dutch).
const NATIONS := ["England", "France", "Dutch", "Spain", "Denmark"]
const WARS := [["France", "Dutch"], ["France", "Spain"]]

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

## Ship classes. speed is a multiplier on daily distance.
const SHIPS := {
	"sloop":    {"name": "Sloop",    "hull": 100, "guns": 8,  "crew_cap": 75,  "cargo": 40,  "speed": 1.15, "price": 2500},
	"fluyt":    {"name": "Fluyt",    "hull": 120, "guns": 6,  "crew_cap": 24,  "cargo": 220, "speed": 0.90, "price": 4000},
	"brigantine":{"name": "Brigantine","hull": 140,"guns": 12, "crew_cap": 90,  "cargo": 90,  "speed": 1.05, "price": 6000},
	"merchantman":{"name": "Merchantman","hull": 160,"guns": 10,"crew_cap": 40, "cargo": 260, "speed": 0.85, "price": 7000},
	"frigate":  {"name": "Frigate",  "hull": 220, "guns": 24, "crew_cap": 160, "cargo": 120, "speed": 1.05, "price": 16000},
}

## Rival captain personalities (sim-core style traits, 0..1).
const PERSONALITIES := {
	"Cautious merchant":   {"aggression": 0.1, "caution": 0.9, "greed": 0.4, "honour": 0.7},
	"Stubborn merchant":   {"aggression": 0.4, "caution": 0.4, "greed": 0.6, "honour": 0.6},
	"Greedy pirate":       {"aggression": 0.6, "caution": 0.5, "greed": 0.9, "honour": 0.2},
	"Bloodthirsty pirate": {"aggression": 0.95,"caution": 0.15,"greed": 0.6, "honour": 0.1},
	"Dutiful navy":        {"aggression": 0.7, "caution": 0.3, "greed": 0.2, "honour": 0.9},
}

static func port_by_id(id: String) -> Dictionary:
	for p in PORTS:
		if p["id"] == id:
			return p
	return {}

static func at_war(a: String, b: String) -> bool:
	for w in WARS:
		if (w[0] == a and w[1] == b) or (w[0] == b and w[1] == a):
			return true
	return false

## Great-circle distance in nautical miles.
static func distance_nm(a: Dictionary, b: Dictionary) -> float:
	var la1 := deg_to_rad(float(a["lat"]))
	var la2 := deg_to_rad(float(b["lat"]))
	var dla := la2 - la1
	var dlo := deg_to_rad(float(b["lon"]) - float(a["lon"]))
	var h := sin(dla / 2.0) ** 2 + cos(la1) * cos(la2) * sin(dlo / 2.0) ** 2
	return 2.0 * 3440.065 * asin(sqrt(h))
