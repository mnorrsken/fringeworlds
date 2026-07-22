class_name Palette
extends RefCounted
## The one shared colour palette for the whole procedural art pass (Milestone 8).
## A warm "regolith" family — dusty browns and ochre with amber highlights, cool
## cyan/violet reserved for the special ice and crystal terrains. Every renderer
## (terrain, buildings, minimap) pulls its colours from here so the art reads as
## one coherent 90s-isometric look. Static constants only; never instantiated.

# Shared structural tones.
const EDGE := Color("2a1d15")          # warm near-black outline between tiles
const RIM_LIGHT := Color("d8b276")     # amber bevel highlight on raised edges

# Flat regolith — the buildable dusty ground.
const REGOLITH := Color("6b5744")
const REGOLITH_HI := Color("83694f")
const REGOLITH_LO := Color("53422f")
const REGOLITH_FLECK := Color("9c8261")
const REGOLITH_FLECK_DK := Color("41321f")

# Rocky highlands — greyer, mauve-tinged rock.
const HIGHLANDS := Color("665a62")
const HIGHLANDS_HI := Color("7e7079")
const HIGHLANDS_LO := Color("4a414c")
const HIGHLANDS_FLECK := Color("938593")
const HIGHLANDS_FLECK_DK := Color("38303a")

# Ice fields — cool cyan with a bright animated sparkle.
const ICE := Color("8ebcc4")
const ICE_HI := Color("bfe1e7")
const ICE_LO := Color("6c96a0")
const ICE_SPARKLE := Color("eafaff")

# Crystal formations — violet facets with an animated shimmer.
const CRYSTAL := Color("7c4f99")
const CRYSTAL_HI := Color("a774c6")
const CRYSTAL_LO := Color("593671")
const CRYSTAL_SPARKLE := Color("dcb6ef")

# Canyon / void — near-black pits with faint "stars".
const VOID := Color("140d12")
const VOID_HI := Color("221a22")
const VOID_STAR := Color("5b5570")

# Building detailing.
const LIGHT_ON := Color("ffd97a")      # lit indicator lamp
const LIGHT_OFF := Color("5c4633")     # unlit / shut-down lamp
const SMOKE := Color("b9a68f")         # exhaust puff
