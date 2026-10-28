#!/bin/sh
#
# Test patch16.exe under DOSBox-X, on an 8086.
#
# Fixtures and patches are made on the host (patches with the host's
# diff -u), one batch file runs every DOS-side step, and the results are
# checked on the host afterwards.  Each step N records patch16's exit
# status in RN.TXT and its standard output in ON.TXT.  DOS cannot
# redirect standard error, so diagnostics are not checked.  rc.bat
# uses goto rather than "if errorlevel N echo ... >file" because the
# DOSBox-X shell opens the redirection even when the test is false.
#
# Usage: tests/run.sh [path/to/patch16.exe]
# Environment: DOSBOX (default dosbox-x), HOSTDIFF (default diff),
#              KEEP=1 to keep the work directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/patch16.exe}
DOSBOX=${DOSBOX:-dosbox-x}
HOSTDIFF=${HOSTDIFF:-diff}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
command -v "$HOSTDIFF" >/dev/null || { echo "$HOSTDIFF not found" >&2; exit 2; }
[ -f "$exe" ] || { echo "$exe not found" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/dospatch.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures

cd "$work" || exit 2
cp "$exe" patch16.exe
mkdir orig want

# udiff NAME: a -p1 patch from orig/NAME to want/NAME, with a/ and b/
# names as diff -u and git make them
udiff() {
    "$HOSTDIFF" -u --label "a/$1" --label "b/$1" "orig/$1" "want/$1"
}

printf 'first\nsecond\nthird\n' > orig/hello.c
printf 'first\nnew\nsecond\nthird\n' > want/hello.c
udiff hello.c > hello.pat
for f in a b c d e s; do cp orig/hello.c $f.c; done
sed 's/hello\.c/a.c/g' hello.pat > a.pat
sed 's/hello\.c/b.c/g' hello.pat > b.pat
sed 's/hello\.c/d.c/g' hello.pat > d.pat
sed 's/hello\.c/e.c/g' hello.pat > e.pat
sed 's#hello\.c#sub/s.c#g' hello.pat > s.pat
mkdir sub
cp orig/hello.c sub/s.c
# a hunk that cannot apply: the line it deletes is not there
printf -- '--- a/c.c\n+++ b/c.c\n@@ -1,3 +1,3 @@\n first\n-zzz\n+new\n third\n' \
    > c.pat
printf 'stale\n' > C.RE1

# a round trip on a larger file: lines changed, added and deleted
# throughout, in several hunks
awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "line %d of the original\n", i }' \
    > orig/big.txt
awk '{ if (NR % 97 == 0) print "changed " $0
       else if (NR % 211 == 0) { print; print "added after " NR }
       else if (NR % 307 != 0) print }' orig/big.txt > want/big.txt
udiff big.txt > big.pat
cp orig/big.txt big.txt

# CRLF lines, a lone CR and ^Z are ordinary bytes in a file and a patch
printf 'one\r\ntwo\r\nthree\032\r\nfour\rfive\r\n' > orig/crlf.txt
printf 'one\r\nTWO\r\nthree\032\r\nfour\rfive\r\nsix\r\n' > want/crlf.txt
udiff crlf.txt > crlf.pat
cp orig/crlf.txt crlf.txt

cat > rc.bat <<'EOF'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.txt
goto end
:rc1
echo rc1 >c:\r%1.txt
goto end
:rc2
echo rc2 >c:\r%1.txt
:end
EOF

cat > steps.bat <<'EOF'
@echo off
rem --- apply
patch16 -p1 -i a.pat >o1.txt
call rc 1
patch16 -p1 <d.pat >o2.txt
call rc 2
patch16 -p1 -i s.pat >o3.txt
call rc 3
patch16 -p1 -i big.pat >o4.txt
call rc 4
patch16 -p1 -i crlf.pat >o5.txt
call rc 5
rem --- backups: the second does not replace the first
patch16 -b -p1 -i b.pat >o6.txt
call rc 6
patch16 -R -b -p1 -i b.pat >o7.txt
call rc 7
rem --- rejects: an existing C.RE1 is kept
patch16 -p1 -i c.pat >o8.txt
call rc 8
patch16 -p1 -i c.pat >o9.txt
call rc 9
rem --- dry run
patch16 --dry-run -p1 -i e.pat >o10.txt
call rc 10
rem --- errors
patch16 -p1 -i nothere.pat >o11.txt
call rc 11
patch16 --bogus >o12.txt
call rc 12
rem --- version
patch16 --version >o13.txt
call rc 13
EOF

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "dosbox machine=cga" -set "cpu cputype=8086" \
    -set "cpu core=normal" -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "c:" \
    -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.TXT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# expect STEP < expected-lines; compares ON.TXT with CRs removed
expect() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null > got.txt
    cat > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# same WHAT FILE EXPECTED-FILE: byte for byte; DOS names are upper case
same() {
    if cmp -s "$2" "$3"; then
        ok
    else
        not_ok "$1: $2 differs from $3"
    fi
}

rc 1 0
expect 1 <<'EOF'
patching file a.c
EOF
same "step 1" A.C want/hello.c
rc 2 0
same "step 2: patch on standard input" D.C want/hello.c
rc 3 0
same "step 3: file in a subdirectory" sub/S.C want/hello.c
rc 4 0
same "step 4: diff -u round trip" BIG.TXT want/big.txt
rc 5 0
same "step 5: CRLF, CR and ^Z kept" CRLF.TXT want/crlf.txt

rc 6 0
expect 6 <<'EOF'
patching file b.c
Saving the original b.c as b.ORG
EOF
rc 7 0
expect 7 <<'EOF'
patching file b.c
Saving the original b.c as b.OR1
EOF
same "step 6: backup" B.ORG orig/hello.c
same "step 7: second backup" B.OR1 want/hello.c
same "step 7: reversed" B.C orig/hello.c

rc 8 1
expect 8 <<'EOF'
patching file c.c
Hunk #1 FAILED at 1.
1 out of 1 hunk FAILED--saving rejects to c.REJ
EOF
rc 9 1
expect 9 <<'EOF'
patching file c.c
Hunk #1 FAILED at 1.
1 out of 1 hunk FAILED--saving rejects to c.RE2
EOF
same "step 8: file unchanged" C.C orig/hello.c
printf 'stale\n' > stale.txt
same "step 9: existing reject kept" C.RE1 stale.txt
same "step 9: rejects" C.RE2 C.REJ
check_rej() {
    tr -d '\r' < C.REJ | grep -q '^- zzz$'
}
if check_rej; then ok; else not_ok "step 8: reject holds the hunk"; fi

rc 10 0
expect 10 <<'EOF'
patching file e.c
EOF
same "step 10: dry run" e.c orig/hello.c

rc 11 2
rc 12 2
rc 13 0
check_version() {
    head -1 O13.TXT | tr -d '\r' | grep -q "^patch $(cat "$top/VERSION") (GNU patch 2.2)\$"
}
if check_version; then ok; else not_ok "step 13: version"; fi

# no temp file is left behind
leftover=$(ls | grep -v -E '^(O|R)[0-9]+\.TXT$' |
    grep -v -x -E 'orig|want|sub|[A-Z]\.C|[A-Z]\.(ORG|OR1|REJ|RE[12])|BIG\.TXT|CRLF\.TXT|[a-z]+\.pat|C\.RE1|stale\.txt|got\.txt|want\.txt|patch16\.exe|rc\.bat|steps\.bat|dosbox\.log|[a-z]+\.c|big\.txt|crlf\.txt')
if [ -z "$leftover" ]; then ok; else not_ok "files left behind:" $leftover; fi

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
