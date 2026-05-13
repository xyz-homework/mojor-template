# mojortemplate

> A minimal, copy-this-to-start template for calling **Mojo** shared libraries from **R** via the C ABI. Includes a working ALTREP demo where `sum()` on a Mojo-backed vector dispatches to SIMD Mojo code with zero copy.

This is a modernized successor to [`sounkou-bioinfo/hellomojo`](https://github.com/sounkou-bioinfo/hellomojo) (archived Feb 2026). Pinned to Mojo `26.2.*` on the stable channel.

## What's in here

| File | Purpose |
| --- | --- |
| `inst/mojo/mojortemplate/mojortemplate.mojo` | Mojo source with four `@export fn` patterns |
| `inst/mojo/mojortemplate/pixi.toml` | Pins Mojo + toolchain |
| `src/mt_glue.c` | R C API glue + ALTREP class definition |
| `src/Makevars.in` | Template populated by `configure` |
| `configure` | Builds the Mojo shared lib if `MOJORTEMPLATE_BUILD=1` |
| `R/api.R` | User-facing R wrappers |
| `tests/testthat/` | testthat suite that exercises every export |
| `.github/workflows/R-CMD-check.yaml` | CI: builds both with-Mojo and without-Mojo |

## Four export patterns

1. **Scalar in/out** — `mt_add(a, b)`. Smoke test for the C ABI plumbing.
2. **Zero-copy buffers** — `mt_convolve(signal, kernel)`. Passes `REAL(x)` pointers directly into Mojo; no allocation across the boundary.
3. **SIMD reduction** — `mt_sum_simd(x)`. Uses Mojo's `vectorize[..., SIMD_WIDTH]` over `simdwidthof[Float64]()`.
4. **Host callbacks** — `mt_device_info()`. Mojo calls back into R via `external_call["Rprintf", c_int]`. Lets Mojo errors flow into the host's existing logging system rather than a separate stream.

## The Phase 1 demo: ALTREP + Mojo SIMD `sum()`

```r
x <- mojo_vec(1e7, start = 0, step = 1)

length(x)   # 1e7 — ALTREP Length_method
x[1:5]      # 0 1 2 3 4 — falls back to Dataptr/Elt
sum(x)      # dispatches via ALTREAL Sum_method to mt_sum_simd
```

The object **is** a numeric vector to R; base `sum()` walks the ALTREP method table and finds our Mojo override. No `mt_*` call at the user site — that's the point. This is the "Numba for R" shape: ergonomic R idioms with bare-metal kernels underneath.

See `src/mt_glue.c` — search for `init_mojo_vec_class` for the ALTREP setup, `mojo_vec_Sum` for the dispatch site.

## Build / install

### Without Mojo (fallback — package installs, exports `Rf_error()`)
```sh
R CMD INSTALL .
```

### With Mojo (full functionality)
```sh
MOJORTEMPLATE_BUILD=1 R CMD INSTALL .
```

`configure` will:
1. Install [pixi](https://pixi.sh) if missing.
2. Resolve Mojo `26.2.*` from `https://conda.modular.com/max`.
3. Build `libmojortemplate.{so,dylib,dll}` into `inst/libs/`.
4. Generate `src/Makevars` linking the C glue against the fresh library.

## Reusing this for non-R hosts

The Mojo source and the `pixi`/build steps are host-agnostic. Only `src/mt_glue.c` and `R/api.R` are R-specific. To target another host, replace the glue layer:

| Host | Glue replacement |
| --- | --- |
| **PHP (FFI extension)** | `FFI::cdef(...)` against `libmojortemplate.so` — no C compilation needed |
| **PHP (C ext)** | Zend API analog of `mt_glue.c` |
| **Python** | `ctypes.CDLL("libmojortemplate.so")` or cffi |
| **Go** | cgo with `extern` declarations matching the Mojo `@export` signatures |

The XYZ Homework / Mojo Math Platform PHP bridge uses the FFI-extension path against this exact library shape.

## Mojo version notes

Verified against Mojo `0.26.2` (stable, `https://conda.modular.com/max`). ABI quirks documented in `symbolize/docs/adr/0006-mojo-0-26-2-abi-reference.md`.

## License

MIT. See `LICENSE`.
