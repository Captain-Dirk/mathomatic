#!/bin/sh
# Test the C, Java, and integer code output of Mathomatic's "code" command.
#
# First checks the emitted text for the expected forms (fmod, cbrt, fabs,
# tgamma, warnings), then compiles the emitted modulus code with a C compiler
# and compares it numerically against reference implementations of the three
# modulus_mode semantics of Mathomatic's calc() (see simplify.c).
#
# Usage: ./codegen_test.sh [path-to-mathomatic]
#
# Requires a C compiler ($CC or cc). Exits 0 if all checks pass.

MATHO=${1:-../mathomatic}
command -v "$MATHO" >/dev/null 2>&1 || MATHO=mathomatic
command -v "$MATHO" >/dev/null 2>&1 || { echo "mathomatic binary not found"; exit 2; }
CC=${CC:-cc}

TMP=`mktemp -d` || exit 2
trap 'rm -rf "$TMP"' EXIT
fail=0

# Feed lines to mathomatic, print the last output line (the generated code).
run() {
	printf '%s\n' "$@" | "$MATHO" -q -c 2>&1 | tail -n 1
}

# check <name> <expected-substring> <actual>
check() {
	if printf '%s' "$3" | grep -qF "$2"; then
		echo "ok: $1"
	else
		echo "FAIL: $1"
		echo "  expected substring: $2"
		echo "  got:                $3"
		fail=1
	fi
}

## Textual checks of the emitted code.

check "square strength reduction" '(x*x)' \
	"`run 'y = x^2' 'code c'`"
check "fmod for double modulus, mode 0" 'fmod(a, b)' \
	"`run 'set modulus_mode 0' 'y = a % b' 'code c'`"
check "adjusted double modulus, mode 1" '(fmod(a, b) != 0 && (fmod(a, b) < 0) != (b < 0) ? fmod(a, b) + b : fmod(a, b))' \
	"`run 'set modulus_mode 1' 'y = a % b' 'code c'`"
check "adjusted double modulus, mode 2" '(fmod(a, b) < 0 ? fmod(a, b) + fabs(b) : fmod(a, b))' \
	"`run 'set modulus_mode 2' 'y = a % b' 'code c'`"
check "adjusted integer modulus, mode 2" '((a % b) < 0 ? (a % b) + labs(b) : (a % b))' \
	"`run 'y = a % b' 'code integer'`"
check "adjusted Java modulus, mode 2" '((a % b) < 0 ? (a % b) + Math.abs(b) : (a % b))' \
	"`run 'y = a % b' 'code java'`"
check "real cube root" 'cbrt(x)' \
	"`run 'y = x^(1/3)' 'code c'`"
check "real cube root, Java" 'Math.cbrt(x)' \
	"`run 'y = x^(1/3)' 'code java'`"
check "absolute value" 'fabs((x))' \
	"`run 'y = |x|' 'code c'`"
check "factorial as true gamma" 'tgamma(x + 1.0)' \
	"`run 'y = x!' 'code c'`"
check "fourth root stays pow" 'pow(x, (1.0/4.0))' \
	"`run 'y = x^(1/4)' 'code c'`"
check "non-square root stays pow" 'pow((a + x), (1.0/2.0))' \
	"`run 'y = (a+x)^(1/2)' 'code c'`"
check "complex number warning" 'complex number support' \
	"`printf '%s\n' 'y = 2*i*x' 'code c' | \"$MATHO\" -q -c 2>&1 | grep -i warning`"

## Numeric checks: compile the emitted modulus code and compare it
## against the reference semantics for many operand sign combinations.

for m in 0 1 2; do
	run "set modulus_mode $m" 'y = a % b' 'code c'
done | sed -e 's/^y = /return /' | awk '{ printf "case %d: %s\n", NR-1, $0 }' > "$TMP/modcases.inc"

for m in 1 2; do
	run "set modulus_mode $m" 'y = a % b' 'code integer'
done | sed -e 's/^y = /return /' | awk '{ printf "case %d: %s\n", NR, $0 }' > "$TMP/imodcases.inc"

cat > "$TMP/codegen_check.c" <<'EOF'
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

static double emitted(int mode, double a, double b)
{
	switch (mode) {
#include "modcases.inc"
	}
	return NAN;
}

static long iemitted(int mode, long a, long b)
{
	switch (mode) {
#include "imodcases.inc"
	}
	return 0;
}

/* reference: the MODULUS semantics of Mathomatic's calc() in simplify.c */
static double reference(int mode, double a, double b)
{
	double r = fmod(a, b);
	if (mode && r < 0.0)
		r += fabs(b);
	if (mode == 1 && b < 0.0 && r > 0.0)
		r += b;
	return r;
}

int main(void)
{
	/* includes 0.001 % 1e9, which catches precision loss from unconditional adjustment */
	double vals[] = {7, -7, 3, -3, 2.5, -2.5, 0, 1e9, -1e9, 0.001};
	int n = sizeof(vals)/sizeof(vals[0]);
	int mode, i, j, bad = 0;
	long ia, ib;

	for (mode = 0; mode <= 2; mode++)
		for (i = 0; i < n; i++)
			for (j = 0; j < n; j++) {
				double a = vals[i], b = vals[j], e, r;
				if (b == 0) continue;
				e = emitted(mode, a, b);
				r = reference(mode, a, b);
				if (fabs(e - r) > 1e-9 * (fabs(r) + 1)) {
					printf("FAIL: double mode=%d a=%g b=%g emitted=%.17g reference=%.17g\n",
					    mode, a, b, e, r);
					bad++;
				}
			}
	for (mode = 1; mode <= 2; mode++)
		for (ia = -25; ia <= 25; ia++)
			for (ib = -25; ib <= 25; ib++) {
				if (ib == 0) continue;
				if ((double) iemitted(mode, ia, ib) != reference(mode, (double) ia, (double) ib)) {
					printf("FAIL: integer mode=%d a=%ld b=%ld emitted=%ld\n",
					    mode, ia, ib, iemitted(mode, ia, ib));
					bad++;
				}
			}
	if (cbrt(-8.0) != -2.0) { puts("FAIL: cbrt"); bad++; }
	if (fabs(tgamma(5.0 + 1.0) - 120.0) > 1e-9) { puts("FAIL: tgamma"); bad++; }
	if (fabs(-1e200) != 1e200) { puts("FAIL: fabs overflow"); bad++; }
	if (bad == 0)
		puts("ok: emitted modulus code matches calc() semantics");
	return bad != 0;
}
EOF

if "$CC" -O2 -Wall -I"$TMP" -o "$TMP/codegen_check" "$TMP/codegen_check.c" -lm; then
	"$TMP/codegen_check" || fail=1
else
	echo "FAIL: emitted code does not compile"
	fail=1
fi

if [ $fail = 0 ]; then
	echo "All code generation tests passed."
else
	echo "Code generation tests FAILED."
fi
exit $fail
