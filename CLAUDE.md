# mojor-template

R package (`mojortemplate`) — a minimal, copy-this-to-start template for calling **Mojo** shared
libraries from **R** via the C ABI. Headline demo: an ALTREP-backed numeric vector whose base-R
`sum()` dispatches straight into SIMD Mojo code with zero copy ("Numba for R" shape).

## Ecosystem

Part of the **XYZ Homework** ecosystem (GitHub org `xyz-homework`; some repos under `XYZPatrick`).
- **Predecessor:** modernized successor to `sounkou-bioinfo/hellomojo` (archived Feb 2026). This repo
  pins Mojo `0.26.2` stable and fixes that project's import-path/ABI quirks.
- **Sibling consumer:** the XYZ Homework / *Mojo Math Platform* PHP bridge dlopens a library of this
  exact shape via the PHP FFI extension (`FFI::cdef` against `libmojortemplate.so`). The Mojo source
  + pixi build here are host-agnostic; only `src/mt_glue.c` and `R/api.R` are R-specific.
- **Specs / ADRs:** Mojo `0.26.2` ABI details live in the `symbolize` repo at
  `docs/adr/0006-mojo-0-26-2-abi-reference.md`. Cross-project specs & roadmaps: the `xyz-docs` repo.
- Topic family: Mojo/MAX ⇄ host-language FFI, SIMD kernels, ALTREP.

## Stack & prerequisites

- **R** (`release`; per CI `r-lib/actions/setup-r@v2`). Standard R toolchain + a C11 compiler.
- **C glue** — `src/mt_glue.c` against the R C API (`Rinternals.h`, `R_ext/Altrep.h`).
- **Mojo** `0.26.2.*` (stable) — only needed for the full build. Resolved via **pixi**
  (https://pixi.sh) from conda channels `https://conda.modular.com/max` + `conda-forge`.
- **pixi** manages the Mojo toolchain; `configure` auto-installs it if missing.
- Supported build platforms (`inst/mojo/mojortemplate/pixi.toml`): `linux-64`, `osx-arm64`,
  `linux-aarch64`. Per-target compilers: `clang >=21.1.4` (osx-arm64), `gcc 15.2.x` (linux-aarch64).
  **No Windows and no x86_64 macOS target** — `configure.win` does not exist.
- No databases, network services, or ports. This is a library, not a server.

## Setup

Fresh clone (an unknown machine with only R + a C compiler):

1. **Install without the Mojo backend** (fast; every `mt_*` call errors, `sum()` on a `mojo_vec`
   falls back to plain C) — good for smoke-testing the plumbing:
   ```sh
   R CMD INSTALL .
   ```
2. **Install with the full Mojo backend** (first run downloads pixi + Mojo `0.26.2`, needs network):
   ```sh
   MOJORTEMPLATE_BUILD=1 R CMD INSTALL .
   ```
   `configure` then: installs pixi if absent → `pixi install` in `inst/mojo/mojortemplate` →
   `mojo build … --emit shared-lib` into `inst/libs/` → writes `src/Makevars` from `src/Makevars.in`.

There is **no `.env`** in this project — no application secrets or config keys to fill in (see
**Secrets & config**). The only knob is the `MOJORTEMPLATE_BUILD` env flag above.

## Build

- Fallback (no Mojo): `R CMD INSTALL .`
- Full (with Mojo): `MOJORTEMPLATE_BUILD=1 R CMD INSTALL .`
- Build only the shared lib by hand (from `inst/mojo/mojortemplate/`):
  `pixi run build-so`  (Linux `.so`) or `pixi run build-dylib` (macOS `.dylib`) — see `[tasks]` in
  `pixi.toml`. Output lands in `inst/libs/`.

## Test

- Full check (what CI runs): `R CMD check .` (CI uses `rcmdcheck` via `r-lib/actions/check-r-package`).
- Quick, after installing: `Rscript -e 'testthat::test_local()'` (testthat edition 3; `tests/testthat/`).
- **The suite requires the Mojo backend to pass:** `test-mt.R` calls `mt_add`/`mt_convolve`/
  `mt_sum_simd`, which `Rf_error()` in `NO_BUILD` mode. Build with `MOJORTEMPLATE_BUILD=1` first.
- Benchmark (not a test): `Rscript bench/sum_bench.R` after a `MOJORTEMPLATE_BUILD=1` install —
  compares base R `sum()` vs `mt_sum_simd()` vs ALTREP `sum(mojo_vec)` over 1e5–1e8 doubles.

## Run / dev

No server or CLI entry point — you use it from an R session:
```r
library(mojortemplate)
x <- mojo_vec(1e7, start = 0, step = 1)  # ALTREP REALSXP backed by malloc'd doubles
length(x); x[1:5]; sum(x)                # sum() dispatches to Mojo SIMD, zero copy
mt_device_info()                         # Mojo prints CPU/SIMD info via Rprintf callback
```

## Architecture

Four layers, one shared library, one thin R surface:

- `inst/mojo/mojortemplate/mojortemplate.mojo` — the kernels. Four `@export fn` C-ABI patterns:
  1. **scalar** `mt_add` (ABI smoke test); 2. **zero-copy buffers** `mt_convolve` (operates on
  R's `REAL(x)` pointers directly, no allocation across the boundary); 3. **SIMD reduction**
  `mt_sum_simd` (`SIMD[..., simd_width_of[DType.float64]()]`); 4. **host callback** `mt_device_info`
  (`external_call["Rprintf", c_int]` — Mojo calls back into R's logging). Pure C-ABI, no MAX dep.
- `src/mt_glue.c` — host glue: `extern` decls for the Mojo symbols, `.Call` SEXP wrappers, and the
  `mojo_vec` **ALTREP class** (`R_make_altreal_class`). The `Sum_method` override
  (`mojo_vec_Sum` → `mt_sum_simd`) is the whole point: base R's `sum()` walks the ALTREP method
  table and finds the Mojo path. Registration in `R_init_mojortemplate` (search `init_mojo_vec_class`,
  `CallEntries`). Payload is an `EXTPTR` over `malloc`'d doubles with a C finalizer.
- `R/api.R` — user-facing wrappers (`mt_add`, `mt_convolve`, `mt_sum_simd`, `mt_device_info`,
  `mojo_vec`) that `.Call` the registered symbols. `R/mojortemplate-package.R` holds the
  `@useDynLib` roxygen block.
- `configure` (POSIX sh) — the gate between fallback and full build; templates `src/Makevars` from
  `src/Makevars.in` (`@MOJO_CFLAGS@` / `@MOJO_LIBS@`).
- Data flow: R vector → `.Call` → C wrapper (validates SEXP) → `REAL(x)` pointer → Mojo kernel →
  scalar/buffer back to R. No copy on the buffer paths.

## Conventions

- Standard R package layout; validate with `R CMD check .` before pushing.
- **Roxygen2** (markdown; `RoxygenNote 7.3.2`). `NAMESPACE` is currently hand-written and `man/` is
  empty — regenerate both with `devtools::document()` rather than editing `NAMESPACE` by hand.
- testthat **edition 3** (`Config/testthat/edition: 3`).
- Commit messages are conventional-ish (`docs: …`, `Initial commit: …`). Default branch `main`;
  CI runs on push to `main`, PRs, and manual dispatch (`.github/workflows/R-CMD-check.yaml`).
- License **MIT** (`LICENSE`).

## Secrets & config

This repo needs **no secrets and no `.env`** — there are no API keys, DB URLs, or service creds.
The single build-time switch is the **`MOJORTEMPLATE_BUILD`** environment variable (unset = fallback,
`1` = build Mojo backend). If secrets are ever introduced, they belong in a **gitignored** `.env`
(sourced from the team secrets manager) — only `*.example` / `*.template` files may be committed;
**never commit a real `.env*`**.

## Gotchas

- **A fresh clone has no compiled library.** `inst/libs/`, `inst/mojo/*/.pixi/`, and `pixi.lock` are
  all gitignored (`.gitignore`, and the nested `inst/mojo/mojortemplate/.gitignore`). Any
  `libmojortemplate.dylib` you see locally is an un-tracked build artifact — you must run the
  `MOJORTEMPLATE_BUILD=1` install to get a working backend.
- **Without `MOJORTEMPLATE_BUILD=1`, every `mt_*` errors** ("built without Mojo backend"); the C glue
  is compiled with `-DMOJORTEMPLATE_NO_BUILD`. Only `mojo_vec` degrades gracefully (plain C sum).
- **First full build needs network** to reach `conda.modular.com/max` for pixi/Mojo resolution.
- **Mojo 0.26.2 import-path quirks** (differ from older hellomojo): `std.ffi` not `sys.ffi`,
  `simd_width_of` not `simdwidthof`, `comptime` not `alias`, `UnsafePointer[T, origin=MutAnyOrigin]`.
  Keep these if you edit `mojortemplate.mojo`.
- **macOS linking:** host symbols like `Rprintf` are resolved by dyld at load time, so `configure`
  passes `-undefined dynamic_lookup` on Darwin. Don't "fix" the resulting unresolved-symbol warning.
- `R_useDynamicSymbols(dll, FALSE)` + `R_forceSymbols(dll, TRUE)` mean `.Call(mt_add, …)` uses the
  registered **symbol object**, not a string — additions must go in `CallEntries` and `NAMESPACE`.
- CI has two jobs: `no-mojo` (fallback install) and `with-mojo` (pixi builds the `.so`, then greps
  `nm -D` for exported `mt_*` symbols before `R CMD check`).
