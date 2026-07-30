//! GDExtension exposing the Taktician Tak engine to Attak.
//!
//! The surface is deliberately tiny: positions go in as TPS and moves come back
//! as PTN, which is the vocabulary Attak already speaks (`GameState.getTPS()` and
//! `Ply.fromPTN()`). No Tak rules are reimplemented on either side of the
//! boundary.
//!
//! The engine itself is Go. `build.rs` compiles `native/go` into a c-archive and
//! links it in statically, so this file is only the shim between Godot's object
//! model and five C functions. Taktician is pinned to an exact commit in
//! `native/go/go.mod`; it is MIT licensed, as is this crate.
//!
//! Searching is asynchronous by polling rather than blocking: `start_search`
//! hands the work to a plain `std::thread` and GDScript polls `is_searching()`
//! from its existing coroutine loop. Nothing from the search thread ever touches
//! Godot's object graph, so no deferred calls or threaded-extension features are
//! needed.

use std::ffi::{c_char, c_int, CStr, CString};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use godot::prelude::*;

struct AttakTaktician;

#[gdextension]
unsafe impl ExtensionLibrary for AttakTaktician {}

/// Board sizes Taktician implements -- which is every size Attak offers.
const SUPPORTED_SIZES: [i32; 6] = [3, 4, 5, 6, 7, 8];

extern "C" {
    fn taktician_supports_size(size: c_int) -> c_int;
    fn taktician_position_ok(tps: *const c_char, size: c_int) -> c_int;
    fn taktician_best_move(
        tps: *const c_char,
        size: c_int,
        depth: c_int,
        millis: c_int,
        max_evals: c_int,
    ) -> *mut c_char;
    fn taktician_legal_moves(tps: *const c_char, size: c_int) -> *mut c_char;
    fn taktician_free(s: *mut c_char);
}

#[derive(Default)]
struct SearchState {
    /// PTN of the finished search, or `None` if it failed.
    result: Mutex<Option<String>>,
    done: AtomicBool,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
struct TakticianEngine {
    #[init(val = 5)]
    size: i32,
    #[init(val = None)]
    search: Option<Arc<SearchState>>,
}

#[godot_api]
impl TakticianEngine {
    /// Board sizes this engine can play.
    #[func]
    fn supported_sizes(&self) -> PackedInt32Array {
        PackedInt32Array::from(&SUPPORTED_SIZES[..])
    }

    #[func]
    fn supports_size(&self, size: i32) -> bool {
        // Asked of the engine rather than read off SUPPORTED_SIZES, so the
        // constant cannot quietly disagree with what Go will actually accept.
        unsafe { taktician_supports_size(size as c_int) != 0 }
    }

    /// Configures the engine for a new game. Returns false for a board size or
    /// komi Taktician cannot handle, so the caller can fall back to another bot.
    #[func]
    fn new_game(&mut self, size: i32, half_komi: i32) -> bool {
        if !self.supports_size(size) {
            godot_warn!("Taktician does not support {size}x{size}");
            return false;
        }
        // Taktician has no komi, only a "black wins ties" flag, so it cannot play
        // a komi game faithfully. Attak's bot games are all komi 0; refuse rather
        // than play a different game to the one on the board.
        if half_komi != 0 {
            godot_warn!("Taktician cannot play with komi (half-komi {half_komi})");
            return false;
        }
        self.size = size;
        self.search = None;
        true
    }

    /// Every legal move in `tps`, as PTN. Exists so Attak's own GDScript move
    /// generator can be differentially tested against a known-correct one.
    #[func]
    fn legal_moves(&self, tps: GString) -> PackedStringArray {
        let joined = call_string(&tps, |raw| unsafe {
            taktician_legal_moves(raw, self.size as c_int)
        });
        match joined {
            Some(joined) if !joined.is_empty() => {
                PackedStringArray::from_iter(joined.split('\n').map(GString::from))
            }
            _ => PackedStringArray::new(),
        }
    }

    /// Starts a search on a background thread. Returns false if the position
    /// could not be parsed, in which case nothing is running.
    ///
    /// `depth` and `max_evals` bound the search reproducibly, which is what the
    /// weaker difficulty and the tests want; `millis` instead lets it deepen
    /// until the clock stops it, which scales with the device and is what the
    /// strongest difficulty wants. Whichever applies, the move returned is the
    /// best from the last depth that finished -- a budget never costs a legal
    /// answer.
    #[func]
    fn start_search(&mut self, tps: GString, depth: i64, millis: i64, max_evals: i64) -> bool {
        // Check here so an unusable position is reported synchronously rather
        // than as a silently empty result much later.
        let usable = with_cstr(&tps, |raw| unsafe {
            taktician_position_ok(raw, self.size as c_int) != 0
        });
        if usable != Some(true) {
            return false;
        }

        let state = Arc::new(SearchState::default());
        self.search = Some(state.clone());

        let tps = tps.to_string();
        let size = self.size;
        std::thread::spawn(move || {
            let found = search(size, &tps, depth, millis, max_evals);
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
    fn search_blocking(&self, tps: GString, depth: i64) -> GString {
        let found = search(self.size, &tps.to_string(), depth, 0, 0);
        GString::from(found.unwrap_or_default().as_str())
    }
}

fn search(size: i32, tps: &str, depth: i64, millis: i64, max_evals: i64) -> Option<String> {
    let tps = CString::new(tps).ok()?;
    take_string(unsafe {
        taktician_best_move(
            tps.as_ptr(),
            size as c_int,
            clamp(depth),
            clamp(millis),
            clamp(max_evals),
        )
    })
}

/// Calls a Go function that returns an owned C string, and takes ownership of the
/// result. `None` covers a NULL return -- the position was unusable -- as well as
/// a TPS string that could not cross as C at all, which an interior NUL would do.
fn call_string(tps: &GString, f: impl FnOnce(*const c_char) -> *mut c_char) -> Option<String> {
    with_cstr(tps, |raw| take_string(f(raw))).flatten()
}

fn with_cstr<T>(tps: &GString, f: impl FnOnce(*const c_char) -> T) -> Option<T> {
    let tps = CString::new(tps.to_string()).ok()?;
    Some(f(tps.as_ptr()))
}

/// Copies a string Go allocated and releases the original. Every Go export that
/// returns a string hands over ownership, so nothing else may free it.
fn take_string(ptr: *mut c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let out = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { taktician_free(ptr) };
    Some(out)
}

/// GDScript ints are 64-bit and the C API takes 32-bit. Saturate rather than
/// wrap: an absurdly large budget should mean "as much as possible", not a
/// negative one that turns the limit off.
fn clamp(value: i64) -> c_int {
    value.clamp(0, c_int::MAX as i64) as c_int
}
