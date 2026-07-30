class_name MoveGen

# Legal move generation. GameState can apply a Ply and detect a win, but nothing
# in the game logic enumerates the moves available in a position -- which any
# local bot needs. Everything here is static and non-mutating: candidate plies
# are only ever realised through GameState.apply(), which duplicates the board
# via nextState() rather than touching the position it was given.
#
# The rules encoded here are the same ones BoardLogic enforces interactively and
# GameState.apply() asserts, so if this file and those disagree, this file is
# wrong. In particular note that GameState's asserts are compiled out of release
# export templates, so an illegal ply corrupts the board silently in an exported
# build while crashing in the editor. Test generator changes in the editor.


# Whose turn it is. Distinct from placedColor() during the swap opening.
static func moverColor(state: GameState) -> int:
	return state.ply % 2


# The colour of the piece that a placement puts on the board. For the first two
# plies of the swap opening each player places their *opponent's* flat, which is
# what GameState.apply() computes at gameState.gd:208 and what BoardLogic gates
# reserve clicks on at BoardLogic.gd:174. Reserve availability must be checked
# against this, not against moverColor().
static func placedColor(state: GameState) -> int:
	var mover := state.ply % 2
	return (1 - mover) if state.ply < 2 else mover


static func legalPlies(state: GameState) -> Array[Ply]:
	var out: Array[Ply] = []
	appendPlacements(state, out)
	appendSpreads(state, out)
	return out


static func appendPlacements(state: GameState, out: Array[Ply]) -> void:
	var color := placedColor(state)
	var hasFlats: bool = state.reserves.flats[color] > 0
	var hasCaps: bool = state.reserves.caps[color] > 0

	# GameState.apply() asserts `ply.piece == FLAT or self.ply >= 2`, so the
	# opening admits flats only.
	var opening := state.ply < 2

	for x in state.size:
		for y in state.size:
			if not state.board[x][y].is_empty(): continue
			var tile := Vector2i(x, y)
			if hasFlats:
				out.append(Place.new(tile, Place.TYPE.FLAT))
				if not opening:
					out.append(Place.new(tile, Place.TYPE.WALL))
			if hasCaps and not opening:
				out.append(Place.new(tile, Place.TYPE.CAP))


static func appendSpreads(state: GameState, out: Array[Ply]) -> void:
	# No stack may be moved during the two swap-opening plies, even though a
	# player's own flat is already on the board by ply 1. BoardLogic enforces the
	# same thing by refusing pile selection while currentPly() < 2.
	if state.ply < 2: return

	var mover := moverColor(state)
	for x in state.size:
		for y in state.size:
			var pile: GameState.Pile = state.board[x][y]
			# You may move a stack only if you control its top piece.
			if pile.is_empty() or pile.pieces[-1] % 2 != mover: continue

			# Carry limit is the board size, matching BoardLogic.selectPile's
			# `pile.pieces.slice(-size)`. GameState enforces nothing here, so
			# this is the only place the limit lives.
			var maxCarry: int = mini(pile.size(), state.size)
			var tile := Vector2i(x, y)
			for dir in Spread.dirToVec:
				for carry in range(1, maxCarry + 1):
					var drops: Array[int] = []
					_walk(state, tile, dir, 1, carry, pile.type, drops, out)


# Enumerates every legal drop sequence that carries `remaining` pieces from
# `origin` in direction `dir`, `step` squares out and beyond.
#
# `carryType` is the *source pile's* type, which is also the carried stack's
# type: Pile.take() copies it, and Pile.drop() peels pieces off the bottom of
# the carried stack, so the type-bearing top piece is always the last one down.
static func _walk(state: GameState, origin: Vector2i, dir: int, step: int,
		remaining: int, carryType: int, drops: Array[int], out: Array[Ply]) -> void:
	var dest: Vector2i = origin + Spread.dirToVec[dir] * step

	# GameState.apply() indexes the board directly and would error rather than
	# assert, so bounds are checked here.
	if dest.x < 0 or dest.y < 0 or dest.x >= state.size or dest.y >= state.size:
		return

	var destPile: GameState.Pile = state.getPile(dest)

	# Nothing may be stacked onto a capstone.
	if destPile.type == GameState.CAP:
		return

	if destPile.type == GameState.WALL:
		# A wall can only be flattened, and only by a lone capstone -- the same
		# condition Pile.drop() asserts and BoardLogic marks "SMASH CONDITION".
		if remaining == 1 and carryType == GameState.CAP:
			out.append(Spread.new(origin, dir, _appended(drops, 1), true))
		return

	# Empty square or a flat on top: drop any number and either stop or carry on.
	for n in range(1, remaining + 1):
		var next := _appended(drops, n)
		if n == remaining:
			out.append(Spread.new(origin, dir, next, false))
		else:
			_walk(state, origin, dir, step + 1, remaining - n, carryType, next, out)


# Spread._init takes a typed Array[int], and `a + b` on typed arrays yields an
# untyped Array in GDScript, which the typed parameter rejects. Copy-and-append
# keeps the element type.
static func _appended(drops: Array[int], n: int) -> Array[int]:
	var next: Array[int] = drops.duplicate()
	next.append(n)
	return next


# Samples a single legal ply without enumerating the whole position. Drop
# sequences grow as 2^(carry-1), so full enumeration on a large board with tall
# stacks is expensive; this picks a source and direction first and only expands
# that one bucket.
static func randomPly(state: GameState, rng: RandomNumberGenerator) -> Ply:
	var color := placedColor(state)
	var mover := moverColor(state)

	# Collect the cheap-to-find options: empty squares, and movable stacks.
	var empties: Array[Vector2i] = []
	var stacks: Array[Vector2i] = []
	for x in state.size:
		for y in state.size:
			var pile: GameState.Pile = state.board[x][y]
			if pile.is_empty():
				empties.append(Vector2i(x, y))
			elif pile.pieces[-1] % 2 == mover:
				stacks.append(Vector2i(x, y))

	var canPlace: bool = not empties.is_empty() \
		and (state.reserves.flats[color] > 0 or (state.ply >= 2 and state.reserves.caps[color] > 0))
	var canSpread: bool = not stacks.is_empty() and state.ply >= 2

	# Prefer placing while reserves last; it keeps early play from degenerating
	# into stack shuffling, and the opening admits nothing else.
	if canPlace and (not canSpread or rng.randf() < 0.6):
		var tile: Vector2i = empties[rng.randi() % empties.size()]
		var kinds: Array[int] = []
		if state.reserves.flats[color] > 0:
			kinds.append(Place.TYPE.FLAT)
			if state.ply >= 2: kinds.append(Place.TYPE.WALL)
		if state.reserves.caps[color] > 0 and state.ply >= 2:
			kinds.append(Place.TYPE.CAP)
		return Place.new(tile, kinds[rng.randi() % kinds.size()])

	if not canSpread:
		return null

	# Expand one (source, direction) bucket and pick from it. Shuffled so a
	# blocked direction doesn't bias the choice.
	var order: Array[Vector2i] = stacks.duplicate()
	order.shuffle()
	for tile in order:
		var pile: GameState.Pile = state.getPile(tile)
		var maxCarry: int = mini(pile.size(), state.size)
		var dirs: Array = Spread.dirToVec.keys()
		dirs.shuffle()
		for dir in dirs:
			var bucket: Array[Ply] = []
			var drops: Array[int] = []
			_walk(state, tile, dir, 1, maxCarry, pile.type, drops, bucket)
			# Shorter carries are legal too, and often the only legal option
			# when the run is blocked early.
			for carry in range(1, maxCarry):
				_walk(state, tile, dir, 1, carry, pile.type, [] as Array[int], bucket)
			if not bucket.is_empty():
				return bucket[rng.randi() % bucket.size()]

	return null
