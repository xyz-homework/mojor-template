# sum_bench.R — head-to-head: Mojo SIMD vs base R sum vs Rcpp scalar sum.
#
# Run after installing the package with MOJORTEMPLATE_BUILD=1.
#
#   $ MOJORTEMPLATE_BUILD=1 R CMD INSTALL .
#   $ Rscript bench/sum_bench.R
#
# Expected ballpark on Apple Silicon (NEON, 2-lane f64 SIMD):
#   - 5-10x speedup vs base R sum() on 1e8 doubles.
# On AVX-512 servers (8-lane f64): 20-30x is plausible.
# The point isn't the headline number — it's that base R `sum(x)` on a
# `mojo_vec` dispatches to SIMD Mojo with zero copy via ALTREP, no .Call
# at the user site.

suppressPackageStartupMessages({
  library(mojortemplate)
  library(bench)
})

sizes <- c(1e5, 1e6, 1e7, 1e8)

run_size <- function(n) {
  cat(sprintf("\n--- n = %g ---\n", n))

  # Plain R numeric (allocates ~8*n bytes)
  x_base <- as.numeric(seq_len(n)) - 1

  # ALTREP-backed mojo vector (allocates a parallel buffer in C; same size)
  x_mojo <- mojo_vec(n, start = 0, step = 1)

  stopifnot(isTRUE(all.equal(sum(x_base), sum(x_mojo))))

  bm <- bench::mark(
    base_sum         = sum(x_base),
    mt_sum_simd_call = mt_sum_simd(x_base),
    altrep_sum       = sum(x_mojo),
    iterations = 20,
    check = FALSE
  )
  print(bm[, c("expression", "min", "median", "itr/sec", "mem_alloc")])
  invisible(bm)
}

mt_device_info()
for (n in sizes) run_size(n)
