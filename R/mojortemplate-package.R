#' mojortemplate: Mojo <-> R FFI Template
#'
#' Minimal, copy-this-to-start-yours template for calling Mojo
#' shared libraries from R via the C ABI. Demonstrates four patterns:
#' scalar in/out, zero-copy buffers, SIMD reduction, and host callbacks.
#'
#' Also ships an ALTREP-backed numeric vector whose `sum()` dispatches
#' directly to Mojo SIMD code without copying — the "Numba for R via
#' Mojo" demonstration.
#'
#' @useDynLib mojortemplate, .registration = TRUE
#' @keywords internal
"_PACKAGE"
