/* mt_glue.c — host-side glue for mojortemplate
 *
 * Layers:
 *   - extern declarations for Mojo @export symbols
 *   - .Call wrappers (R SEXP marshalling)
 *   - ALTREP class definition for a Mojo-summable numeric vector
 *   - R_init_mojortemplate registration
 *
 * If MOJORTEMPLATE_NO_BUILD is defined at compile time, all wrappers
 * Rf_error() instead — this keeps the package installable on systems
 * without a working Mojo toolchain (CI fallback).
 */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Altrep.h>
#include <R_ext/Rdynload.h>
#include <stdlib.h>
#include <string.h>

#ifndef MOJORTEMPLATE_NO_BUILD
extern double mt_add(double a, double b);
extern void   mt_convolve(const double *signal, int n_signal,
                          const double *kernel, int n_kernel,
                          double *output);
extern double mt_sum_simd(const double *data, int n);
extern void   mt_device_info(void);
#endif

/* ============================================================
 * .Call wrappers
 * ============================================================ */

SEXP mt_add_call(SEXP a, SEXP b) {
#ifndef MOJORTEMPLATE_NO_BUILD
    if (!isReal(a) && !isInteger(a)) Rf_error("a must be numeric");
    if (!isReal(b) && !isInteger(b)) Rf_error("b must be numeric");
    return ScalarReal(mt_add(asReal(a), asReal(b)));
#else
    Rf_error("mojortemplate built without Mojo backend");
#endif
}

SEXP mt_convolve_call(SEXP signal, SEXP kernel) {
#ifndef MOJORTEMPLATE_NO_BUILD
    if (!isReal(signal) || !isReal(kernel))
        Rf_error("signal and kernel must be numeric vectors");
    R_xlen_t ns = XLENGTH(signal), nk = XLENGTH(kernel);
    if (ns < nk) Rf_error("signal length must be >= kernel length");
    SEXP out = PROTECT(allocVector(REALSXP, ns - nk + 1));
    mt_convolve(REAL(signal), (int)ns, REAL(kernel), (int)nk, REAL(out));
    UNPROTECT(1);
    return out;
#else
    Rf_error("mojortemplate built without Mojo backend");
#endif
}

SEXP mt_sum_simd_call(SEXP x) {
#ifndef MOJORTEMPLATE_NO_BUILD
    if (!isReal(x)) Rf_error("x must be a numeric vector");
    return ScalarReal(mt_sum_simd(REAL(x), (int)XLENGTH(x)));
#else
    Rf_error("mojortemplate built without Mojo backend");
#endif
}

SEXP mt_device_info_call(void) {
#ifndef MOJORTEMPLATE_NO_BUILD
    mt_device_info();
    return R_NilValue;
#else
    Rf_error("mojortemplate built without Mojo backend");
#endif
}

/* ============================================================
 * Phase 1: ALTREP-backed numeric vector with Mojo SIMD Sum
 *
 * A "mojo vector" is a REALSXP-shaped ALTREP whose data1 slot holds an
 * R EXTPTR pointing at malloc()'d doubles. Methods provided:
 *
 *   Length      — vector length (cheap)
 *   Dataptr     — pointer to the underlying buffer (so REAL(x)[i] works)
 *   Elt         — random access (fallback)
 *   Sum         — overridden to call mt_sum_simd directly (the win)
 *
 * The point: base R's sum(x) on a mojo_vec dispatches to mt_sum_simd
 * with zero copy. Same trick generalizes to mean/cumsum/etc.
 * ============================================================ */

static R_altrep_class_t mojo_vec_class;

typedef struct {
    double *data;
    R_xlen_t n;
} mojo_vec_payload;

static void mojo_vec_finalize(SEXP eptr) {
    mojo_vec_payload *p = (mojo_vec_payload *)R_ExternalPtrAddr(eptr);
    if (p) {
        free(p->data);
        free(p);
        R_ClearExternalPtr(eptr);
    }
}

static SEXP mojo_vec_new(R_xlen_t n) {
    mojo_vec_payload *p = (mojo_vec_payload *)malloc(sizeof(*p));
    if (!p) Rf_error("mojo_vec: out of memory");
    p->n = n;
    p->data = (double *)calloc((size_t)n, sizeof(double));
    if (!p->data) { free(p); Rf_error("mojo_vec: out of memory (buffer)"); }

    SEXP eptr = PROTECT(R_MakeExternalPtr(p, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(eptr, mojo_vec_finalize, TRUE);

    SEXP out = PROTECT(R_new_altrep(mojo_vec_class, eptr, R_NilValue));
    UNPROTECT(2);
    return out;
}

static mojo_vec_payload *mojo_vec_get(SEXP x) {
    SEXP eptr = R_altrep_data1(x);
    return (mojo_vec_payload *)R_ExternalPtrAddr(eptr);
}

/* ALTREP method: length */
static R_xlen_t mojo_vec_Length(SEXP x) {
    return mojo_vec_get(x)->n;
}

/* ALTVEC method: dataptr (read/write) */
static void *mojo_vec_Dataptr(SEXP x, Rboolean writeable) {
    (void)writeable;
    return (void *)mojo_vec_get(x)->data;
}

static const void *mojo_vec_Dataptr_or_null(SEXP x) {
    return (const void *)mojo_vec_get(x)->data;
}

/* ALTREAL method: random access */
static double mojo_vec_Elt(SEXP x, R_xlen_t i) {
    return mojo_vec_get(x)->data[i];
}

/* ALTREAL method: Sum — the headline override.
 * Returns a length-1 REALSXP (per ALTREAL Sum_method contract).
 * na.rm is ignored in this demo; production code should branch.
 */
static SEXP mojo_vec_Sum(SEXP x, Rboolean na_rm) {
    (void)na_rm;
#ifndef MOJORTEMPLATE_NO_BUILD
    mojo_vec_payload *p = mojo_vec_get(x);
    return ScalarReal(mt_sum_simd(p->data, (int)p->n));
#else
    /* fallback: regular R sum so package still loads */
    mojo_vec_payload *p = mojo_vec_get(x);
    double acc = 0.0;
    for (R_xlen_t i = 0; i < p->n; i++) acc += p->data[i];
    return ScalarReal(acc);
#endif
}

/* ALTREP method: Inspect (R's `.Internal(inspect(x))` output) */
static Rboolean mojo_vec_Inspect(SEXP x, int pre, int deep, int pvec,
                                 void (*inspect_sub)(SEXP, int, int, int)) {
    (void)pre; (void)deep; (void)pvec; (void)inspect_sub;
    mojo_vec_payload *p = mojo_vec_get(x);
    Rprintf("mojo_vec (n=%lld, Mojo-SIMD Sum)\n", (long long)p->n);
    return TRUE;
}

/* Constructor exposed to R */
SEXP mt_mojo_vec_new(SEXP n_sexp) {
    if (!isInteger(n_sexp) && !isReal(n_sexp))
        Rf_error("n must be numeric");
    R_xlen_t n = (R_xlen_t)asReal(n_sexp);
    if (n < 0) Rf_error("n must be non-negative");
    return mojo_vec_new(n);
}

/* Fill helper so demos don't need to write through Dataptr from R */
SEXP mt_mojo_vec_fill_seq(SEXP x, SEXP start_sexp, SEXP step_sexp) {
    mojo_vec_payload *p = mojo_vec_get(x);
    double v = asReal(start_sexp), s = asReal(step_sexp);
    for (R_xlen_t i = 0; i < p->n; i++, v += s) p->data[i] = v;
    return x;
}

/* ============================================================
 * Init
 * ============================================================ */

static void init_mojo_vec_class(DllInfo *dll) {
    R_altrep_class_t cls = R_make_altreal_class("mojo_vec", "mojortemplate", dll);
    /* ALTREP */
    R_set_altrep_Length_method(cls, mojo_vec_Length);
    R_set_altrep_Inspect_method(cls, mojo_vec_Inspect);
    /* ALTVEC */
    R_set_altvec_Dataptr_method(cls, mojo_vec_Dataptr);
    R_set_altvec_Dataptr_or_null_method(cls, mojo_vec_Dataptr_or_null);
    /* ALTREAL */
    R_set_altreal_Elt_method(cls, mojo_vec_Elt);
    R_set_altreal_Sum_method(cls, mojo_vec_Sum);
    mojo_vec_class = cls;
}

static const R_CallMethodDef CallEntries[] = {
    {"mt_add",               (DL_FUNC) &mt_add_call,            2},
    {"mt_convolve",          (DL_FUNC) &mt_convolve_call,       2},
    {"mt_sum_simd",          (DL_FUNC) &mt_sum_simd_call,       1},
    {"mt_device_info",       (DL_FUNC) &mt_device_info_call,    0},
    {"mt_mojo_vec_new",      (DL_FUNC) &mt_mojo_vec_new,        1},
    {"mt_mojo_vec_fill_seq", (DL_FUNC) &mt_mojo_vec_fill_seq,   3},
    {NULL, NULL, 0}
};

void R_init_mojortemplate(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
    init_mojo_vec_class(dll);
}
