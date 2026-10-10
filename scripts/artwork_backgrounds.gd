extends RefCounted
## Stable background IDs are stored with artwork so its setting survives editing.
const TEXTURES := {
	"paper": null,
	"country_road": preload("res://assets/backgrounds/country-road.svg"),
	"star_platform": preload("res://assets/backgrounds/star-platform.svg"),
	"bamboo_mountains": preload("res://assets/backgrounds/bamboo-mountains.svg"),
	"tea_cottage": preload("res://assets/backgrounds/tea-cottage.svg"),
}

static func texture_for(id: String) -> Texture2D:
	return TEXTURES.get(id)

static func is_valid(id: String) -> bool:
	return TEXTURES.has(id)
