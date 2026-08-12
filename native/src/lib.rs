//! GDExtension exposing the syntaks Tak engine to Attak.
//!
//! The surface is deliberately tiny: positions go in as TPS and moves come back
//! as PTN, which is the vocabulary Attak already speaks (`GameState.getTPS()` and
//! `Ply.fromPTN()`). No Tak rules are reimplemented on either side of the
//! boundary.
//!
//! Searching is asynchronous by polling rather than blocking: `start_search`
//! hands the work to a plain `std::thread` and GDScript polls `is_searching()`
//! from its existing coroutine loop. Nothing from the search thread ever touches
//! Godot's object graph, so no deferred calls or threaded-extension features are
//! needed.
//!
//! syntaks is MIT licensed. See LICENSE-THIRD-PARTY.md at the repository root.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use godot::prelude::*;
use syntaks::board::Position;
use syntaks::limit::Limits;
use syntaks::movegen;
use syntaks::search::{MAX_DEPTH, Searcher};
use syntaks::tei::TeiOptions;

struct AttakSyntaks;

#[gdextension]
unsafe impl ExtensionLibrary for AttakSyntaks {}

/// syntaks implements 6x6 and nothing else -- it answers `Only 6x6 supported` to
/// any other `teinewgame`. Attak offers 3-8, so every other size falls back to
/// the built-in GDScript bot.
const SUPPORTED_SIZES: [i32; 1] = [6];

/// syntaks is built around a fixed komi of 2 (`HalfKomi ... min 4 max 4`), so a
/// game it plays has to use that komi for its evaluation to mean anything.
const REQUIRED_HALF_KOMI: i32 = 4;

#[derive(Default)]
struct SearchState {
    /// PTN of the finished search, or `None` if it failed.
    result: Mutex<Option<String>>,
    done: AtomicBool,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
struct SyntaksEngine {
    #[init(val = None)]
    search: Option<Arc<SearchState>>,
}

#[godot_api]
impl SyntaksEngine {
    /// Board sizes this engine can play.
    #[func]
    fn supported_sizes(&self) -> PackedInt32Array {
        PackedInt32Array::from(&SUPPORTED_SIZES[..])
    }

    #[func]
    fn supports_size(&self, size: i32) -> bool {
        SUPPORTED_SIZES.contains(&size)
    }

    /// The komi a game must use for this engine to be worth asking. Attak reads
    /// this rather than hard-coding it, so the two cannot drift apart.
    #[func]
    fn required_half_komi(&self) -> i32 {
        REQUIRED_HALF_KOMI
    }

    /// Configures the engine for a new game. Returns false for anything syntaks
    /// cannot play, so the caller can fall back to another engine.
    #[func]
    fn new_game(&mut self, size: i32, half_komi: i32) -> bool {
        if !SUPPORTED_SIZES.contains(&size) {
            godot_warn!("syntaks only plays 6x6, not {size}x{size}");
            return false;
        }
        if half_komi != REQUIRED_HALF_KOMI {
            godot_warn!("syntaks requires half-komi {REQUIRED_HALF_KOMI}, got {half_komi}");
            return false;
        }
        self.search = None;
        true
    }

    /// Every legal move in `tps`, as PTN. Exists so Attak's own GDScript move
    /// generator can be differentially tested against an independent one.
    #[func]
    fn legal_moves(&self, tps: GString) -> PackedStringArray {
        let Some(position) = parse(&tps.to_string()) else {
            return PackedStringArray::new();
        };

        let mut moves = Vec::new();
        movegen::generate_moves(&mut moves, &position);

        PackedStringArray::from_iter(moves.iter().map(|mv| GString::from(mv.to_string().as_str())))
    }

    /// Starts a search on a background thread. Returns false if the position
    /// could not be parsed, in which case nothing is running.
    ///
    /// Exactly one budget applies: `nodes` when positive, otherwise `millis`. A
    /// node budget is reproducible, which is what the weaker difficulty and the
    /// tests want; a time budget scales with the device, which is what the
    /// stronger one wants.
    #[func]
    fn start_search(&mut self, tps: GString, nodes: i64, millis: i64) -> bool {
        let tps = tps.to_string();

        // Parse here so an unusable position is reported synchronously rather
        // than as a silently empty result later.
        if parse(&tps).is_none() {
            return false;
        }

        let state = Arc::new(SearchState::default());
        self.search = Some(state.clone());

        std::thread::spawn(move || {
            let found = search_position(&tps, nodes, millis);
            *state.result.lock().unwrap() = found;
            state.done.store(true, Ordering::Release);
        });

        true
    }

    #[func]
    fn is_searching(&self) -> bool {
        self.search
            .as_ref()
            .is_some_and(|state| !state.done.load(Ordering::Acquire))
    }

    /// The finished search's move as PTN. Empty if the search is still running,
    /// was never started, or failed.
    #[func]
    fn take_result(&mut self) -> GString {
        let Some(state) = self.search.take() else {
            return GString::new();
        };
        if !state.done.load(Ordering::Acquire) {
            self.search = Some(state); // still running -- keep waiting on it
            return GString::new();
        }
        let found = state.result.lock().unwrap().take();
        GString::from(found.unwrap_or_default().as_str())
    }

    /// Searches to completion on the calling thread. For tests only: this blocks,
    /// which is precisely what the polling API exists to avoid.
    #[func]
    fn search_blocking(&self, tps: GString, nodes: i64) -> GString {
        let found = search_position(&tps.to_string(), nodes, 0);
        GString::from(found.unwrap_or_default().as_str())
    }
}

/// syntaks parses TPS from whitespace-separated parts, the same way its TEI
/// `position tps ...` handler receives them.
fn parse(tps: &str) -> Option<Position> {
    let trimmed = tps.trim();
    if trimmed.is_empty() || trimmed == "startpos" {
        return Some(Position::startpos());
    }

    let parts: Vec<&str> = trimmed.split_whitespace().collect();
    Position::from_tps_parts(&parts).ok()
}

fn search_position(tps: &str, nodes: i64, millis: i64) -> Option<String> {
    let position = parse(tps)?;

    let mut searcher = Searcher::new();
    let start = Instant::now();
    let mut limits = Limits::new(start);

    let accepted = if nodes > 0 {
        limits.set_nodes(nodes as usize)
    } else {
        // Limits takes seconds; the caller thinks in milliseconds.
        limits.set_movetime(millis.max(1) as f64 / 1000.0)
    };

    if !accepted {
        return None;
    }

    searcher.start_search(
        &position,
        &[],
        start,
        limits,
        MAX_DEPTH,
        &[],
        &TeiOptions::default(),
    );
    searcher.wait();

    searcher.best_move().map(|mv| mv.to_string())
}
