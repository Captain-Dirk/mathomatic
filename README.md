# Mathomatic

**A small, portable computer algebra system in plain C — and the rare one
that hands you its solutions as compilable C code.**

Mathomatic was written by George Gesslein II between 1987 and 2012 and
released under the GNU LGPL. After the author's death the project site
vanished; his final release (16.0.5) is preserved unchanged in a read-only
[archive repository](https://github.com/mfillpot/mathomatic), which
recommends forking — this repository is such a fork, and it aims beyond
conservation at a new version. The symbolic math engine remains his work;
on top of it this fork modernizes the sources (ANSI C prototypes, C++ and
MSVC/MinGW compatibility, a shared-library build), extends the library API
so that a host program can capture Mathomatic's output — in particular the
generated C code — and improves the code generator so that the emitted C
compiles as-is and matches the engine's semantics exactly (modulus modes,
`sqrt`/`cbrt` and real roots of negative numbers, absolute values,
factorials, expanded small powers).

## Why Mathomatic

Most computer algebra systems are big: a Lisp image (Maxima), a Python stack
(SymPy), or a C++ library with bignum dependencies (GiNaC, SymEngine).
Mathomatic is a single small C library with no dependencies beyond `libc`
and `libm`, LGPL-licensed so it can be linked into closed-source software,
and driven entirely by text strings: you pass in `"solve x"`, you get back
the solution as a string.

Its distinguishing feature is the `code` command: any solved equation can be
emitted as a ready-to-compile **C** (or Java or Python) statement. That
turns Mathomatic into a formula compiler — derive a solution symbolically,
generate the C expression, paste (or generate) it into your program:

```
1-> v = 4/3*pi*r^3
1-> solve r

         3*v   1
#1: r = ------^-
        (4*pi) 3

1-> code c
r = cbrt((3.0*v/(4.0*M_PI)));
1-> variables c
double          v;
double          r;
```

## A five-minute tour

Solving a general quadratic, with verification of all solutions:

```
1-> y = a*x^2 + b*x + c
1-> solve verify x
Equation is a degree 2 polynomial equation in x.
Equation was solved with the quadratic formula.

                                 1
        ((((b^2 + (4*a*(y - c)))^-)*sign) - b)
                                 2
#1: x = --------------------------------------
                        (2*a)

All solutions verified.
1-> code c
x = (((sqrt(((b*b) + (4.0*a*(y - c))))*sign) - b)/(2.0*a));
```

`sign` is Mathomatic's explicit "±": both roots in one expression, and one
`double sign = 1.0;` (or `-1.0`) away from compiling. Constants like `pi`
map to `M_PI`; roots and powers map to `sqrt`/`cbrt`, plain multiplication,
or `pow()`, whichever is fastest and most exact; with `code integer`,
expressions are emitted using integer arithmetic instead.

Simplification and calculus:

```
1-> h = (t^2+2*t+1)/(t+1)
1-> simplify

#1: h = 1 + t

1-> derivative t

#2: h' = 1
```

Type `help examples` at the prompt, or read the
[command reference](doc/am.html) and [manual](doc/manual.html).

## Capabilities

- **Algebra** — `simplify` (with selectable aggressiveness), `factor`,
  `unfactor` (expand), `fraction` (combine over a common denominator),
  full symbolic complex-number arithmetic (`i` is built in).
- **Equation solving** — `solve` isolates any variable that can be reached
  by transposition, and applies the quadratic formula to quadratic and
  biquadratic (any-degree `x^2n/x^n`) polynomial equations. `solve verify`
  checks every returned root by substitution.
- **Calculus** — `derivative` of any expression; `integrate` and `laplace`
  (and inverse) for polynomials; `taylor` series expansion; `nintegrate`
  for numerical definite integrals (Simpson's rule).
- **Code generation** — `code c | java | python | integer` emits solved
  equations as source code; `optimize` splits common subexpressions into
  separate assignments (CSE); `variables c` generates the declarations.
- **Workspace** — 200 independent equation spaces that commands can operate
  across, substitute between, and compare (`compare`, `eliminate`, ...).
- **Extras** — the `primes/` directory builds `matho-primes`,
  `matho-mult`, `matho-sum` and friends for quick number-theory work.

## Limitations — read before choosing

Mathomatic is deliberately small. Know what it does *not* do:

- **Floating-point, not exact, arithmetic.** All numeric coefficients are
  IEEE doubles with epsilon-based rounding — not arbitrary-precision
  rationals. Results can carry round-off; it is not a bignum CAS.
- **No transcendental functions in the engine.** There is no `log`, and no
  native `sin`/`cos`/... . The interactive `rmath` wrapper preprocesses
  trig functions into complex exponentials with m4 macros (`m4/`), but that
  expansion is **not** available through the library API — a library caller
  must expand such input itself.
- **Solving is transposition + quadratic formula.** No cubic/quartic
  radical formulas and no polynomial root radicals beyond biquadratic.
  There is no one-shot simultaneous-equation solver; systems are reduced
  step by step with the `eliminate` command (solve-and-substitute).
- **Polynomial-only symbolic integration** (`integrate`, `laplace`).
- **Not reentrant, not thread-safe.** Nearly all state is global. One
  engine per process; serialize access with a mutex if threads are involved.
- **Fixed capacities.** 200 equation spaces; expression size is bounded
  (~60,000 tokens by default, tunable at compile time).

## How it compares

| | Mathomatic | GiNaC | SymEngine | SymPy | Maxima |
|---|---|---|---|---|---|
| Language / embedding | C, links anywhere | C++ | C++ (C API) | Python | Lisp (subprocess) |
| License | LGPL | GPL | MIT | BSD | GPL |
| Arithmetic | double + epsilon | exact (CLN) | exact (GMP) | exact | exact |
| Solve for a variable | transposition + quadratic | linear systems only | limited | extensive | extensive |
| Emit compilable C | yes (`code c`) | yes (csrc printing) | yes (ccode) | yes (`ccode`/codegen) | via `fortran` etc. |
| Footprint / deps | tiny, none | moderate + CLN | moderate + GMP | large Python stack | large |

Pick Mathomatic when you want the *smallest* embeddable engine that can
take `"solve this for x"` at runtime and give back one line of C — and your
math is algebraic, single-equation, and fine in double precision. Pick one
of the others when you need exact arithmetic, transcendental functions, or
heavier symbolic machinery.

## The symbolic math library

The library API (`lib/`) wraps the whole engine behind a handful of
string-in/string-out calls, documented in section-3 man pages:

| Function | Purpose |
|---|---|
| `matho_init()` | one-time engine initialization — [matho_init(3)](lib/matho_init.3) |
| `matho_parse(input, &output)` | enter an expression/equation into an equation space — [matho_parse(3)](lib/matho_parse.3) |
| `matho_process(input, &output)` | run any command or input, as if typed at the prompt — [matho_process(3)](lib/matho_process.3) |
| `matho_clear()` | erase all equation spaces (fast restart) — [matho_clear(3)](lib/matho_clear.3) |
| `matho_outfile(fp)` | redirect side-channel output, returns previous stream — [matho_outfile(3)](lib/matho_outfile.3) |
| `matho_current_eqn()` / `matho_result_eqn()` / `matho_warning()` | accessors for `cur_equation`, `result_en`, `warning_str` when using the shared library |
| `free_mem()` | release everything (engine unusable until `matho_init()` again) |

```c
#include <stdio.h>
#include <stdlib.h>
#include "mathomatic.h"

int main(void)
{
    char *output;

    if (!matho_init())
        return 1;
    matho_parse("y = a*x^2 + b*x + c", NULL);
    if (matho_process("solve x", &output)) {
        printf("%s\n", output);   /* solution, malloc()ed */
        free(output);
    } else {
        printf("error: %s\n", output);   /* constant string, do not free */
    }
    return 0;
}
```

On success the result string is `malloc()`ed and must be freed; on failure
a constant error message is returned instead. `matho_result_eqn()` tells
you which equation space also holds the result, so follow-up commands
(`simplify`, `code c`, ...) can target it.

- **Static library:** `cd lib && make` builds `libmathomatic.a`, the
  `testmain` exerciser, and installs headers + man pages via `make install`.
- **Shared library:** compile with `-DSHARED_LIB=1` (all sources compiled
  with `-DLIBRARY`; a unity build that `#include`s the `.c` files works
  well). `mathomatic.h` resolves symbol visibility automatically:
  `dllexport`/`visibility("default")` while building, `dllimport` for
  Windows consumers.

## Building

```sh
make            # the interactive program (add READLINE=1 for line editing)
make test       # run the regression test suite — should end 100% correct
cd lib && make  # the symbolic math library + man pages
```

Builds cleanly on Unix/Linux/macOS with gcc or clang, and — in this fork —
with MSVC and MinGW (cross-)compilers on or for Windows (`compile.mingw`,
CMake). See `INSTALL.txt` for the full upstream instructions and tunables
(`-DSECURE` for a sandboxed engine without file/shell access, m4 wrappers,
localization, ...).

## Documentation

- [`doc/manual.html`](doc/manual.html) — user manual
- [`doc/am.html`](doc/am.html) — complete command reference
- [`doc/quickrefcard.html`](doc/quickrefcard.html) — printable quick reference
- `mathomatic.1`, `rmath.1`, `lib/matho_*.3` — man pages
- `examples/`, `tests/` — annotated example scripts, doubling as the test suite
- `help` / `help examples` — built into the program itself

## License and provenance

Copyright © 1987–2012 George Gesslein II. Licensed under the
[GNU Lesser General Public License v2.1](COPYING); the documentation is
under the GNU FDL. This fork carries his work forward so that it remains
available, usable, and improving.
