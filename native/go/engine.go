// C bindings for the Taktician Tak engine, built as a c-archive and linked into
// the GDExtension in ../src/lib.rs.
//
// The surface is deliberately tiny: positions go in as TPS and moves come back as
// PTN, which is the vocabulary Attak already speaks (GameState.getTPS() and
// Ply.fromPTN()). No Tak rules are reimplemented on either side of the boundary.
//
// Only Taktician's ai, ptn, tak, bitboard and symmetry packages are used, and
// those depend on nothing but the standard library -- no grpc, no sqlite, no C
// libraries -- which is what keeps the Android cross-compile a plain
// CC=<ndk clang> build.
//
// Every exported function recovers from panics. A panic unwinding into C would
// abort the whole process, and Taktician does panic on genuinely out-of-range
// input (ai.MakeEvaluator indexes a per-size weights table). Returning NULL lets
// the caller fall back to the built-in bot instead of taking the app down.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"strings"
	"time"
	"unsafe"

	"github.com/nelhage/taktician/ai"
	"github.com/nelhage/taktician/ptn"
	"github.com/nelhage/taktician/tak"
)

// Sizes Taktician can actually play. tak.New indexes its default piece and
// capstone tables by size (tak/game.go), and ai.MakeEvaluator indexes
// ai.DefaultWeights, both of which run 0..8 -- so 3..8 is the usable range, and
// it happens to be exactly the range Attak offers.
const minSize, maxSize = 3, 8

// Transposition table size per search, in bytes.
//
// ai.NewMinimax defaults to 100 MB when TableMem is zero, which is not a
// reasonable allocation on a phone for a single bot move. 16 MB still holds
// hundreds of thousands of entries, far more than these search budgets visit.
const tableMem = 16 << 20

//export taktician_supports_size
func taktician_supports_size(size C.int) C.int {
	if size >= minSize && size <= maxSize {
		return 1
	}
	return 0
}

// taktician_position_ok reports whether tps parses as a position of the given
// size. It lets the caller reject a position synchronously, before handing a
// search to a background thread where the only way to report failure would be an
// empty result much later.
//
//export taktician_position_ok
func taktician_position_ok(tps *C.char, size C.int) (ok C.int) {
	defer func() {
		if recover() != nil {
			ok = 0
		}
	}()

	if parse(C.GoString(tps), int(size)) == nil {
		return 0
	}
	return 1
}

// taktician_best_move searches tps and returns the chosen move as PTN, or NULL if
// the position could not be used.
//
// depth and maxEvals bound the search reproducibly, which is what the weaker
// difficulty and the tests want; millis lets iterative deepening run until the
// clock stops it, which is what the strongest difficulty wants. Taktician weighs
// these between depths -- it declines to start one it cannot finish -- and returns
// the best move from the last depth that completed, so a budget never costs a
// legal answer.
//
// The caller owns the returned string and must release it with taktician_free.
//
//export taktician_best_move
func taktician_best_move(tps *C.char, size C.int, depth C.int, millis C.int, maxEvals C.int) (result *C.char) {
	defer func() {
		if recover() != nil {
			result = nil
		}
	}()

	p := parse(C.GoString(tps), int(size))
	if p == nil {
		return nil
	}

	cfg := ai.MinimaxConfig{
		Size:     p.Size(),
		Depth:    int(depth),
		TableMem: tableMem,
	}
	if maxEvals > 0 {
		cfg.MaxEvals = uint64(maxEvals)
	}

	ctx := context.Background()
	if millis > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, time.Duration(millis)*time.Millisecond)
		defer cancel()
	}

	move := ai.NewMinimax(cfg).GetMove(ctx, p)
	return C.CString(ptn.FormatMove(move))
}

// taktician_legal_moves returns every legal move in tps as newline-separated PTN,
// or NULL if the position could not be used. An empty (but non-NULL) string means
// a valid position with no moves.
//
// This exists so Attak's own GDScript move generator can be differentially tested
// against an independently written one -- see tools/takticianTest.gd.
//
// The caller owns the returned string and must release it with taktician_free.
//
//export taktician_legal_moves
func taktician_legal_moves(tps *C.char, size C.int) (result *C.char) {
	defer func() {
		if recover() != nil {
			result = nil
		}
	}()

	p := parse(C.GoString(tps), int(size))
	if p == nil {
		return nil
	}

	// AllMoves is pseudo-legal: it enumerates every slide shape that fits on the
	// board without checking whether a wall or capstone blocks the path, and
	// leaves Taktician's search to discard those when Move rejects them. Playing
	// each one is what turns the list into the legal moves the caller asked for.
	moves := p.AllMoves(nil)
	out := make([]string, 0, len(moves))
	for _, move := range moves {
		if _, err := p.Move(move); err != nil {
			continue
		}
		out = append(out, ptn.FormatMove(move))
	}
	return C.CString(strings.Join(out, "\n"))
}

//export taktician_free
func taktician_free(s *C.char) {
	C.free(unsafe.Pointer(s))
}

// parse turns TPS into a position, rejecting anything the caller did not ask for.
// The size is checked rather than trusted: ai.Analyze panics outright when its
// configured size disagrees with the position it is handed.
func parse(tps string, size int) *tak.Position {
	if size < minSize || size > maxSize {
		return nil
	}
	p, err := ptn.ParseTPS(tps)
	if err != nil || p == nil || p.Size() != size {
		return nil
	}
	return p
}

func main() {}
