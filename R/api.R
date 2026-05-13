#' Add two numbers via Mojo (smoke test).
#' @param a,b numeric scalars
#' @return numeric scalar
#' @export
mt_add <- function(a, b) .Call(mt_add, as.numeric(a), as.numeric(b))

#' 1D convolution via Mojo (zero-copy buffer demo).
#' @param signal,kernel numeric vectors, length(signal) >= length(kernel)
#' @return numeric vector of length `length(signal) - length(kernel) + 1`
#' @export
mt_convolve <- function(signal, kernel) {
  .Call(mt_convolve, as.numeric(signal), as.numeric(kernel))
}

#' SIMD-vectorized sum via Mojo on a regular R numeric vector.
#' For ALTREP-aware `sum()` dispatch, see [mojo_vec()].
#' @param x numeric vector
#' @return numeric scalar
#' @export
mt_sum_simd <- function(x) .Call(mt_sum_simd, as.numeric(x))

#' Print Mojo-detected CPU info (uses Rprintf callback from Mojo side).
#' @export
mt_device_info <- function() invisible(.Call(mt_device_info))

#' Create a Mojo-backed ALTREP numeric vector.
#'
#' The returned object behaves like a `numeric` vector — `length()`,
#' `[i]`, and (critically) `sum()` all work. `sum()` dispatches to
#' Mojo SIMD code via the ALTREP `Sum_method` override; no buffer copy.
#'
#' @param n integer length
#' @param start,step numeric — initial fill values, x[i] = start + (i-1)*step
#' @return ALTREP REALSXP of class `mojo_vec`
#' @examples
#' \dontrun{
#'   x <- mojo_vec(1e7, start = 0, step = 1)
#'   sum(x)        # dispatches to Mojo mt_sum_simd, zero copy
#'   length(x)     # 1e7
#'   x[1:5]        # 0 1 2 3 4
#' }
#' @export
mojo_vec <- function(n, start = 0, step = 1) {
  x <- .Call(mt_mojo_vec_new, as.numeric(n))
  .Call(mt_mojo_vec_fill_seq, x, as.numeric(start), as.numeric(step))
}
