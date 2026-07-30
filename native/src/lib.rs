//! GDExtension exposing the tiltak Tak engine to Attak.
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
//! tiltak is GPL-3.0-or-later. See LICENSE-THIRD-PARTY.md at the repository root.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use board_game_traits::Position as _;
use godot::prelude::*;
use pgn_traits::PgnPosition as _;
use tiltak::position::{Komi, Position};
use tiltak::search::{self, MctsSetting, MonteCarloTree};

struct AttakTiltak;

#[gdextension]
unsafe impl ExtensionLibrary for AttakTiltak {}

/// Board sizes tiltak actually implements. Other sizes have zobrist keys but no
/// evaluation or policy parameters, and searching them panics inside tiltak
/// (`unimplemented!("Unsupported size")`), so they are rejected up front.
const SUPPORTED_SIZES: [i32; 3] = [4, 5, 6];

#[derive(Default)]
struct SearchState {
    /// PTN of the finished search, or `None` if it failed.
    result: Mutex<Option<String>>,
    done: AtomicBool,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
struct TiltakEngine {
    #[init(val = 5)]
    size: i32,
    #[init(val = 0)]
    half_komi: i32,
    #[init(val = None)]
    search: Option<Arc<SearchState>>,
}

#[godot_api]
impl TiltakEngine {
    /// Board sizes this engine can play.
    #[func]
    fn supported_sizes(&self) -> PackedInt32Array {
        PackedInt32Array::from(&SUPPORTED_SIZES[..])
    }

    #[func]
    fn supports_size(&self, size: i32) -> bool {
        SUPPORTED_SIZES.contains(&size)
    }

    /// Configures the engine for a new game. Returns false for a board size or
    /// komi tiltak cannot handle, so the caller can fall back to another engine.
    #[func]
    fn new_game(&mut self, size: i32, half_komi: i32) -> bool {
        if !SUPPORTED_SIZES.contains(&size) {
            godot_warn!("tiltak does not support {size}x{size}");
            return false;
        }
        if komi_from(half_komi).is_none() {
            godot_warn!("tiltak rejected half-komi {half_komi}");
            return false;
        }
        self.size = size;
        self.half_komi = half_komi;
        self.search = None;
        true
    }

    /// Every legal move in `tps`, as PTN. Exists so Attak's own GDScript move
    /// generator can be differentially tested against a known-correct one.
    #[func]
    fn legal_moves(&self, tps: GString) -> PackedStringArray {
        let moves = match self.size {
            4 => legal_moves_sized::<4>(self.half_komi, &tps.to_string()),
            5 => legal_moves_sized::<5>(self.half_komi, &tps.to_string()),
            6 => legal_moves_sized::<6>(self.half_komi, &tps.to_string()),
            _ => None,
        };
        match moves {
            Some(moves) => PackedStringArray::from_iter(moves.iter().map(|m| GString::from(m.as_str()))),
            None => PackedStringArray::new(),
        }
    }

    /// Starts a search on a background thread. Returns false if the position
    /// could not be parsed, in which case nothing is running.
    ///
    /// Exactly one budget applies: `nodes` when positive, otherwise `millis`. A
    /// node budget is reproducible, which is what the weaker difficulties and the
    /// tests want; a time budget scales with the device, which is what the
    /// strongest difficulty wants.
    #[func]
    fn start_search(&mut self, tps: GString, nodes: i64, millis: i64) -> bool {
        let tps = tps.to_string();
        let size = self.size;
        let half_komi = self.half_komi;

        // Parse here so an unusable position is reported synchronously rather
        // than as a silently empty result later.
        if !position_parses(size, half_komi, &tps) {
            return false;
        }

        let state = Arc::new(SearchState::default());
        self.search = Some(state.clone());

        std::thread::spawn(move || {
            let found = search_position(size, half_komi, &tps, nodes, millis);
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
        let found = search_position(self.size, self.half_komi, &tps.to_string(), nodes, 0);
        GString::from(found.unwrap_or_default().as_str())
    }
}

fn komi_from(half_komi: i32) -> Option<Komi> {
    i8::try_from(half_komi).ok().and_then(Komi::from_half_komi)
}

fn parse<const S: usize>(half_komi: i32, tps: &str) -> Option<Position<S>> {
    let komi = komi_from(half_komi)?;
    if tps.is_empty() || tps == "startpos" {
        return Some(Position::start_position_with_komi(komi));
    }
    Position::from_fen_with_komi(tps, komi).ok()
}

fn position_parses(size: i32, half_komi: i32, tps: &str) -> bool {
    match size {
        4 => parse::<4>(half_komi, tps).is_some(),
        5 => parse::<5>(half_komi, tps).is_some(),
        6 => parse::<6>(half_komi, tps).is_some(),
        _ => false,
    }
}

fn legal_moves_sized<const S: usize>(half_komi: i32, tps: &str) -> Option<Vec<String>> {
    let position = parse::<S>(half_komi, tps)?;
    let mut moves = Vec::new();
    position.generate_moves(&mut moves);
    Some(moves.iter().map(|mv| position.move_to_san(mv)).collect())
}

fn search_position(
    size: i32,
    half_komi: i32,
    tps: &str,
    nodes: i64,
    millis: i64,
) -> Option<String> {
    match size {
        4 => search_sized::<4>(half_komi, tps, nodes, millis),
        5 => search_sized::<5>(half_komi, tps, nodes, millis),
        6 => search_sized::<6>(half_komi, tps, nodes, millis),
        _ => None,
    }
}

fn search_sized<const S: usize>(
    half_komi: i32,
    tps: &str,
    nodes: i64,
    millis: i64,
) -> Option<String> {
    let position = parse::<S>(half_komi, tps)?;

    // MctsSetting::default() leaves value/policy params unset, which tiltak then
    // resolves per komi from the position itself, so there is nothing to wire up.
    let (mv, _score) = if nodes > 0 {
        search::mcts::<S>(position.clone(), nodes as u64)
    } else {
        let budget = Duration::from_millis(millis.max(1) as u64);
        let mut tree = MonteCarloTree::new(position.clone(), MctsSetting::<S>::default());
        tree.search_for_time(budget, |_| {});
        tree.best_move()?
    };

    Some(position.move_to_san(&mv))
}
