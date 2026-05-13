# Draft: comment for the MojoR forum thread

**Thread:** `forum.modular.com/t/mojor-a-numba-for-r/`
**Posture:** complementary, not competitive. MojoR is a JIT compiler;
this is the FFI scaffold a JIT needs to land into. Offer it as
infrastructure, not as a rival project.

---

## Suggested reply

Love the direction here, Seyoon — the R world has been stuck without a
real "Numba" story for years, and this benchmark is the first one that
actually shows the gap closing.

While we wait for MojoR to land, I put together a small companion
template that might be useful as scaffolding (or as something to
copy/throw away once your JIT lands):
**[xyz-homework/mojor-template](https://github.com/xyz-homework/mojor-template)**

It's a modernized successor to
[`sounkou-bioinfo/hellomojo`](https://github.com/sounkou-bioinfo/hellomojo)
(archived a few months ago). Pinned to Mojo 0.26.2 stable, with:

- Four `@export fn` patterns (scalar / zero-copy buffer / SIMD
  reduction / host callback via `external_call["Rprintf"]`).
- An **ALTREP-backed numeric vector** whose `sum()` dispatches into
  Mojo SIMD code with zero copy — so existing R code that calls
  `sum(x)` on a `mojo_vec` gets the speedup without changing.
- A `MOJORTEMPLATE_BUILD` env-flag fallback so the package installs
  on machines without a Mojo toolchain (degrades gracefully — useful
  for CRAN-style distribution where reviewers can't necessarily run
  pixi).
- The set of Mojo 0.26.2 import-path quirks the hellomojo source
  doesn't handle (`std.ffi` not `sys.ffi`, `simd_width_of` not
  `simdwidthof`, `comptime` over `alias`, `UnsafePointer[T, origin=…]`,
  macOS dynamic-lookup linker flags for host callbacks).

If anything in there is useful for the MojoR runtime layer — host
callbacks, the ALTREP `Sum_method` override pattern, the pixi build
glue — please feel free to lift it. MIT licensed. And if your design
goes a different direction (real-time JIT vs ahead-of-time shared
lib), I'd love to compare notes.

Either way: when MojoR drops, please post — there are a lot of us
who've been waiting.
