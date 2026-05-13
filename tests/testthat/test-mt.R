test_that("mt_add returns the sum", {
  expect_equal(mt_add(2, 3), 5)
  expect_equal(mt_add(-1.5, 1.5), 0)
})

test_that("mt_convolve matches base R stats::convolve(..., type='filter')", {
  s <- as.numeric(1:10)
  k <- c(1, 0, -1)
  out <- mt_convolve(s, k)
  ref <- stats::convolve(s, rev(k), type = "filter")
  expect_equal(out, as.numeric(ref))
})

test_that("mt_sum_simd matches sum() on a plain vector", {
  x <- runif(10000)
  expect_equal(mt_sum_simd(x), sum(x), tolerance = 1e-9)
})

test_that("mojo_vec is length-correct and sums via Mojo SIMD", {
  x <- mojo_vec(1000, start = 0, step = 1)
  expect_equal(length(x), 1000L)
  # 0 + 1 + ... + 999 = 999*1000/2 = 499500
  expect_equal(sum(x), 499500)
  expect_equal(x[1], 0)
  expect_equal(x[1000], 999)
})

test_that("mojo_vec sum() vs base sum on plain numeric agree", {
  n <- 1e5
  v <- mojo_vec(n, start = 0, step = 1)
  expect_equal(sum(v), sum(seq(0, n - 1)))
})
