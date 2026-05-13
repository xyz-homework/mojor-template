# mojortemplate.mojo
# ------------------
# Minimal Mojo<->R bridge demonstrating four export patterns:
#
#   1. mt_add           — scalar in, scalar out (smoke test)
#   2. mt_convolve      — host-allocated buffers, zero copy
#   3. mt_sum_simd      — Mojo SIMD reduction (Phase 1 ALTREP backing)
#   4. mt_device_info   — host callback via external_call["Rprintf"]
#
# Verified against Mojo 0.26.2 stable (conda.modular.com/max).
# Pure C-ABI; no MAX dependency. Builds as a plain shared library that R,
# PHP-FFI, Python-ctypes, or Go-cgo can all dlopen.

from std.ffi import c_char, c_int, external_call
from std.sys import (
    CompilationTarget,
    simd_width_of,
    num_logical_cores,
    num_physical_cores,
)
from std.memory import UnsafePointer

comptime SIMD_WIDTH = simd_width_of[DType.float64]()

# Buffers come from R-allocated memory; from Mojo's perspective they're
# externally owned, so we use MutAnyOrigin (lifetime-agnostic) and let the
# host guarantee the buffer is alive across the call.
comptime HostPtr = UnsafePointer[Float64, origin=MutAnyOrigin]
comptime HostStr = UnsafePointer[c_char, origin=MutAnyOrigin]


# ---- 1. scalar smoke test ----
@export
fn mt_add(a: Float64, b: Float64) -> Float64:
    return a + b


# ---- 2. zero-copy buffer demo (1D convolution) ----
@export
fn mt_convolve(
    signal: HostPtr, n_signal: Int,
    kernel: HostPtr, n_kernel: Int,
    output: HostPtr,
):
    var i: Int = 0
    while i < n_signal - n_kernel + 1:
        var acc: Float64 = 0.0
        var j: Int = 0
        while j < n_kernel:
            acc = acc + (signal + i + j)[] * (kernel + j)[]
            j = j + 1
        (output + i)[] = acc
        i = i + 1


# ---- 3. SIMD reduction (Phase 1: feeds ALTREP Sum_method) ----
# This is the "Numba for R" core: R's sum() on an ALTREP vector dispatches
# here, hitting SIMD-vectorized Mojo without ever copying the R buffer.
@export
fn mt_sum_simd(data: HostPtr, n: Int) -> Float64:
    var lanes = SIMD[DType.float64, SIMD_WIDTH](0.0)
    var i: Int = 0
    var end_chunked: Int = (n // SIMD_WIDTH) * SIMD_WIDTH

    # Vectorized body
    while i < end_chunked:
        lanes += data.load[width=SIMD_WIDTH](i)
        i = i + SIMD_WIDTH

    # Horizontal reduce
    var total: Float64 = 0.0
    var k: Int = 0
    while k < SIMD_WIDTH:
        total += lanes[k]
        k = k + 1

    # Scalar tail
    while i < n:
        total += (data + i)[]
        i = i + 1

    return total


# ---- 4. host callback (Rprintf) ----
@export
fn mt_device_info():
    _ = external_call["Rprintf", c_int](
        String("=== mojortemplate device info ===\n").unsafe_ptr()
    )

    var os_name = String("unix")
    if CompilationTarget.is_linux():
        os_name = String("linux")
    elif CompilationTarget.is_macos():
        os_name = String("macOS")

    var msg = String("  OS             : ") + os_name + "\n"
    _ = external_call["Rprintf", c_int](msg.unsafe_ptr())

    var phys = String("  Physical Cores : ") + String(num_physical_cores()) + "\n"
    _ = external_call["Rprintf", c_int](phys.unsafe_ptr())

    var logical = String("  Logical Cores  : ") + String(num_logical_cores()) + "\n"
    _ = external_call["Rprintf", c_int](logical.unsafe_ptr())

    var simd_msg = String("  SIMD width f64 : ") + String(SIMD_WIDTH) + "\n"
    _ = external_call["Rprintf", c_int](simd_msg.unsafe_ptr())

    var feats = String()
    if CompilationTarget.has_avx2():     feats += " avx2"
    if CompilationTarget.has_avx512f():  feats += " avx512f"
    if CompilationTarget.has_neon():     feats += " neon"
    if CompilationTarget.is_apple_silicon(): feats += " apple_silicon"
    var feats_msg = String("  CPU Features   :") + feats + "\n"
    _ = external_call["Rprintf", c_int](feats_msg.unsafe_ptr())
