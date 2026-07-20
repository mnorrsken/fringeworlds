extends Node
## Sim — authoritative game state and the fixed-tick loop.
##
## Simulation is pure data + logic, fully separate from rendering. State lives in
## plain arrays/dictionaries so it is headlessly testable and trivially
## serializable. Rendering reads this state; it never writes game rules back.
##
## Milestone 0: only the tick loop exists. Map, buildings, stockpile, and
## economy arrive in later milestones.

## Simulation ticks per real second at 1x speed.
const TICKS_PER_SECOND := 4.0

## Speed multiplier: 0.0 = paused, 1.0 = normal, 3.0 = fast.
var speed: float = 1.0

## Monotonic simulation tick counter.
var tick: int = 0

var _accumulator: float = 0.0

func _process(delta: float) -> void:
	if speed <= 0.0:
		return
	_accumulator += delta * speed
	var step := 1.0 / TICKS_PER_SECOND
	while _accumulator >= step:
		_accumulator -= step
		_advance_tick()

func _advance_tick() -> void:
	tick += 1
	# Later milestones: producers/consumers, power balance, prospecting, colonists.
	Events.ticked.emit(tick)

func set_paused(paused: bool) -> void:
	speed = 0.0 if paused else 1.0
