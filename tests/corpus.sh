#!/bin/sh
#
# The Linux-to-DOS round-trip corpus (docs/DESIGN.md, E3): old and new
# file trees made on Linux, patches for them made by GNU diff and Git,
# patch16 applying each patch to the old tree on DOS, and the result
# compared byte for byte with the new tree.
#
# Cases (case_NN below) make a/, the old tree, and b/, the new one, and
# may make t/ and w/, the tree patched and the tree wanted, where those
# differ from a/ and b/ (a patch applied at an offset). Every file name
# is 8.3.
#
# Producers, one letter each; each makes a -p1 patch from a/ to b/:
#   U  diff -Nru          Z  diff -NrU0        W  diff -NrU10
#   P  diff -Nrup         C  diff -Nrc
#   G  git diff           F  git format-patch (a mail: headers, diffstat,
#                                              signature)
#   M  diff -Nru with the blanks of empty context lines stripped, as
#      some mailers and editors leave a patch
# Line ends:
#   L  as made on Linux: LF files, LF patch
#   D  the tree on DOS converted to CR LF, the patch not: added lines
#      take a file's CR LF, a new file the patch's LF
#   E  the tree and the patch both CR LF
# D and E are made for U, G and F.
#
# Each producer's runs go on a disk of their own (a 1.44 MB floppy for
# GR-DOS), DIR/dos/<producer>: RUN.BAT, RC.BAT and T\<run>\, where <run>
# is case, producer, line ends (01UL); the patch is T\<run>\P.PAT,
# patch16's output O.TXT and its exit status R.TXT. RUN.BAT runs
# \PATCH16 -p1 -i P.PAT in each, on the current drive.
#
# usage:
#   tests/corpus.sh make DIR             make the corpus in DIR
#   tests/corpus.sh check DIR GOT P      check producer P's runs: GOT is
#                                        its disk after RUN.BAT
#   tests/corpus.sh dosbox EXE [DIR]     make, run under DOSBox-X, check
#   tests/corpus.sh grdos EXE [DIR]      make, run on GR-DOS in QEMU
#                                        (tests/grdos.sh), check
#
# Needs GNU diff, git and perl to make the corpus; dosbox-x, or
# qemu-system-i386 and mtools, to run it. Environment: DOSBOX (default
# dosbox-x), HOSTDIFF (default diff), KEEP=1 to keep the directory made.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
HOSTDIFF=${HOSTDIFF:-diff}
DOSBOX=${DOSBOX:-dosbox-x}
PRODUCERS="U Z W P C G F M"

# lines N [PREFIX]: N numbered lines
lines() {
    awk -v n="$1" -v p="${2:-line}" 'BEGIN { for (i = 1; i <= n; i++) printf "%s %d\n", p, i }'
}

# ------------------------------------------------------------------
# cases

# a one-line file, changed: hunk headers without counts (@@ -1 +1 @@)
case_01() { printf 'x\n' > a/ONE.TXT; printf 'y\n' > b/ONE.TXT; }

# a new file, beside one that does not change
case_02() {
    lines 5 keep > a/KEEP.TXT; cp a/KEEP.TXT b/KEEP.TXT
    lines 5 new > b/NEW.TXT
}

# a file emptied, which stays (a zero-length new range)
case_03() { lines 3 > a/E.TXT; : > b/E.TXT; }

# a file deleted: the patch says so (diff -N's epoch date, Git's
# "deleted file mode" and /dev/null), and patch16 removes it
case_04() {
    lines 5 keep > a/KEEP.TXT; cp a/KEEP.TXT b/KEEP.TXT
    lines 4 gone > a/GONE.TXT
}

# lines inserted at the start, appended at the end, deleted at the
# start and the end, changed in the middle
case_05() { lines 20 > a/S.TXT; { lines 2 new; lines 20; } > b/S.TXT; }
case_06() { lines 20 > a/S.TXT; { lines 20; lines 2 new; } > b/S.TXT; }
case_07() { lines 20 > a/S.TXT; lines 20 | sed 1,3d > b/S.TXT; }
case_08() { lines 20 > a/S.TXT; lines 17 > b/S.TXT; }
case_09() { lines 20 > a/S.TXT; lines 20 | sed '10s/.*/changed/; 11d' > b/S.TXT; }

# a larger file, changed throughout, in many hunks
case_10() {
    lines 3000 > a/BIG.TXT
    awk '{ if (NR % 97 == 0) print "changed " $0
           else if (NR % 211 == 0) { print; print "added after " NR }
           else if (NR % 307 != 0) print }' a/BIG.TXT > b/BIG.TXT
}

# a last line without a newline: kept, added, removed, appended to
case_11() {
    printf 'a\nb' > a/NL1.TXT;   printf 'a\nc' > b/NL1.TXT
    printf 'a\nb' > a/NL2.TXT;   printf 'a\nb\n' > b/NL2.TXT
    printf 'a\nb\n' > a/NL3.TXT; printf 'a\nb' > b/NL3.TXT
    printf 'a\nb' > a/NL4.TXT;   printf 'a\nb\nc\n' > b/NL4.TXT
}

# the same lines over and over: the hunk's line number decides
case_12() {
    for i in 1 2 3 4 5 6 7 8 9 10; do printf 'x\ny\nz\n'; done > a/REP.TXT
    awk 'NR == 20 { print "Y" ; next } { print }' a/REP.TXT > b/REP.TXT
}

# several files in directories, one new in a new directory
case_13() {
    mkdir -p a/SRC a/DOC b/SRC b/DOC b/LIB
    lines 30 main > a/SRC/MAIN.C; lines 30 main | sed 's/^main 15$/main fifteen/' > b/SRC/MAIN.C
    lines 30 util > a/SRC/UTIL.C; { lines 30 util; echo 'util end'; } > b/SRC/UTIL.C
    lines 10 doc > a/DOC/README.TXT; lines 10 doc | sed 2d > b/DOC/README.TXT
    lines 6 new > b/LIB/NEW.C
}

# C functions, for the section labels of diff -p and git
case_14() {
    cat > a/F.C <<'EOF'
#include <stdio.h>

static int
first (int a)
{
  int b = a + 1;
  int c = b * 2;
  int d = c - 3;
  return d;
}

static int
second (int a)
{
  int b = a - 1;
  int c = b / 2;
  int d = c + 3;
  return d;
}

int
main (void)
{
  printf ("%d %d\n", first (1), second (2));
  return 0;
}
EOF
    sed 's/int c = b \* 2;/int c = b * 3;/; s/int d = c + 3;/int d = c + 4;/' a/F.C > b/F.C
}

# applied at an offset: the file has 7 more lines at the top
case_15() {
    lines 30 > a/OFS.TXT; lines 30 | sed 's/^line 20$/line twenty/' > b/OFS.TXT
    mkdir t w
    { lines 7 extra; cat a/OFS.TXT; } > t/OFS.TXT
    { lines 7 extra; cat b/OFS.TXT; } > w/OFS.TXT
}

# lines that look like diff syntax
case_16() {
    cat > a/LOOK.TXT <<'EOF'
plain
--- a/x
+++ b/y
@@ -1,2 +1,2 @@
-
+
*** 1,2 ****
\ No newline at end of file
diff --git a/x b/x
Index: x
end
EOF
    sed 's/^--- a\/x$//; s/^@@ -1,2 +1,2 @@$/@@ -3 +3 @@/; s/^\*\*\* 1,2 \*\*\*\*$/--- 1,2 ----/; s/^Index: x$/+++ added/' a/LOOK.TXT > b/LOOK.TXT
}

# bytes: code page 437 letters, tabs, trailing blanks, a form feed
case_17() {
    printf 'caf\202\n\tindent\ntrail   \nbox \311\315\273\n\014\nend\n' > a/B.TXT
    printf 'caf\202 au lait\n\tindent\ntrail   \nbox \311\315\315\273\n\014\nend\n' > b/B.TXT
}

# a long line (2000 bytes), changed
case_18() {
    awk 'BEGIN { s = ""; for (i = 0; i < 200; i++) s = s "0123456789"; print "a"; print s; print "z" }' > a/L.TXT
    sed '2s/^0/X/' a/L.TXT > b/L.TXT
}

# empty lines in the context
case_19() {
    printf 'one\n\n\ntwo\n\nthree\n\n\nfour\n' > a/BL.TXT
    printf 'one\n\n\ntwo\n\nTHREE\n\n\nfour\n' > b/BL.TXT
}

# an empty file given its first lines
case_20() { : > a/E.TXT; lines 3 > b/E.TXT; }

CASES="01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20"

# ------------------------------------------------------------------
# producers: patch P from a/ to b/ in the current directory, to stdout

git_env() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=corpus GIT_AUTHOR_EMAIL=corpus@example.invalid \
    GIT_COMMITTER_NAME=corpus GIT_COMMITTER_EMAIL=corpus@example.invalid \
    GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    "$@"
}

# a repository in g/ with a/ committed, then b/
git_repo() {
    rm -rf g; mkdir g
    (cd a && tar -cf - .) | (cd g && tar -xf -)
    (cd g && git_env git init -q && git_env git add -A &&
        git_env git commit -q --allow-empty -m old) || return 1
    (cd g && git_env git rm -rq --ignore-unmatch . >/dev/null &&
        (cd ../b && tar -cf - .) | tar -xf - &&
        git_env git add -A && git_env git commit -q --allow-empty -m 'new version')
}

produce() {
    case $1 in
    U) "$HOSTDIFF" -Nru a b ;;
    Z) "$HOSTDIFF" -NrU0 a b ;;
    W) "$HOSTDIFF" -NrU10 a b ;;
    P) "$HOSTDIFF" -Nrup a b ;;
    C) "$HOSTDIFF" -Nrc a b ;;
    M) "$HOSTDIFF" -Nru a b | sed 's/^ $//' ;;
    G) git_repo >&2 && (cd g && git_env git diff HEAD~1 HEAD) ;;
    F) git_repo >&2 && (cd g && git_env git format-patch -1 --stdout HEAD) ;;
    esac
    return 0
}

# ------------------------------------------------------------------
# make

dos() { perl -pe 's/\n/\r\n/'; }

# copy tree $1 to $2 converting every file to CR LF
dos_tree() {
    (cd "$1" && find . -type d) | (cd "$2" && xargs mkdir -p)
    (cd "$1" && find . -type f) | while read -r f; do dos < "$1/$f" > "$2/$f"; done
}

# want_tree T W E OUT: the tree wanted from target T, new tree W and line
# ends E: a file that had line ends takes them (CR LF for D and E); one
# that had none, or a new one, takes the patch's (LF for D, CR LF for E).
# A file deleted is removed.
want_tree() {
    t=$1 w=$2 e=$3 out=$4
    (cd "$w" && find . -type d) | (cd "$out" && xargs mkdir -p)
    (cd "$t" && find . -type d) | (cd "$out" && xargs mkdir -p)
    (cd "$w" && find . -type f) | while read -r f; do
        if [ "$e" = L ]; then
            cp "$w/$f" "$out/$f"
        elif [ "$e" = E ] || { [ -f "$t/$f" ] && [ "$(wc -l < "$t/$f")" -gt 0 ]; }; then
            dos < "$w/$f" > "$out/$f"
        else
            cp "$w/$f" "$out/$f"
        fi
    done
}

make_corpus() {
    dir=$1
    rm -rf "$dir"; mkdir -p "$dir/dos" "$dir/want" "$dir/ws"
    for p in $PRODUCERS; do
        mkdir -p "$dir/dos/$p/T"
        # CR LF: MS-DOS 4.00's COMMAND.COM reads a batch file's lines
        # up to CR; with LF alone the file is one line
        dos > "$dir/dos/$p/RC.BAT" <<'EOF'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >R.TXT
goto end
:rc1
echo rc1 >R.TXT
goto end
:rc2
echo rc2 >R.TXT
:end
EOF
        printf '@echo off\r\n' > "$dir/dos/$p/RUN.BAT"
    done
    for c in $CASES; do
        ws=$dir/ws/$c
        rm -rf "$ws"; mkdir -p "$ws/a" "$ws/b"
        (cd "$ws" && "case_$c") || { echo "case $c failed" >&2; return 1; }
        if (cd "$ws" && find a b -name P.PAT -o -name O.TXT -o -name R.TXT) | grep -q .; then
            echo "case $c: P.PAT, O.TXT and R.TXT are the run's own" >&2; return 1
        fi
        [ -d "$ws/t" ] || cp -r "$ws/a" "$ws/t"
        [ -d "$ws/w" ] || cp -r "$ws/b" "$ws/w"
        for p in $PRODUCERS; do
            (cd "$ws" && produce "$p") > "$ws/$p.pat" || return 1
            case $p in U|G|F) eols="L D E" ;; *) eols=L ;; esac
            for e in $eols; do
                run=$c$p$e
                rd=$dir/dos/$p/T/$run
                mkdir -p "$rd" "$dir/want/$run"
                if [ "$e" = L ]; then
                    (cd "$ws/t" && tar -cf - .) | (cd "$rd" && tar -xf -)
                    cp "$ws/$p.pat" "$rd/P.PAT"
                else
                    dos_tree "$ws/t" "$rd"
                    if [ "$e" = E ]; then dos < "$ws/$p.pat" > "$rd/P.PAT"
                    else cp "$ws/$p.pat" "$rd/P.PAT"; fi
                fi
                want_tree "$ws/t" "$ws/w" "$e" "$dir/want/$run"
                printf 'echo RUN %s\r\ncd \\T\\%s\r\n\\PATCH16 -p1 -i P.PAT >O.TXT\r\ncall \\RC\r\n' \
                    "$run" "$run" >> "$dir/dos/$p/RUN.BAT"
                echo "$run" >> "$dir/dos/$p/runs"
            done
        done
    done
    for p in $PRODUCERS; do printf 'cd \\\r\n' >> "$dir/dos/$p/RUN.BAT"; done
    rm -rf "$dir/ws"
}

# ------------------------------------------------------------------
# check

# check_runs DIR GOT P [CONSOLE]: CONSOLE is what the console showed (on
# GR-DOS, through CTTY AUX), with "RUN <run>" before each run; a failed
# run's part of it is shown, for patch16's standard error
check_runs() {
    dir=$1 got=$2 p=$3 console=${4:-}
    pass=0 fail=0
    for run in $(cat "$dir/dos/$p/runs"); do
        g=$got/T/$run
        bad=
        rc=$(tr -d ' \r' < "$g/R.TXT" 2>/dev/null)
        [ "$rc" = rc0 ] || bad="exit status ${rc:-missing}"
        if [ -z "$bad" ]; then
            want=$(cd "$dir/want/$run" && find . -type f | sort)
            have=$(cd "$g" && find . -type f ! -name P.PAT ! -name O.TXT ! -name R.TXT | sort)
            if [ "$want" != "$have" ]; then
                bad="files: wanted $(echo $want), have $(echo $have)"
            else
                for f in $want; do
                    cmp -s "$dir/want/$run/$f" "$g/$f" || bad="$bad ${f#./} differs"
                done
            fi
        fi
        if [ -z "$bad" ]; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
            echo "FAIL: $run: $bad"
            [ -f "$g/O.TXT" ] && tr -d '\r' < "$g/O.TXT" | sed 's/^/    /'
            [ -n "$console" ] && [ -f "$console" ] &&
                tr -d '\r' < "$console" |
                awk -v r="RUN $run" '$0 == r { on = 1; next } /^RUN / { on = 0 } on { print "    console: " $0 }'
        fi
    done
    echo "$p: $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
}

# ------------------------------------------------------------------
# runners

run_dosbox() {
    exe=$1 dir=$2
    status=0
    for p in $PRODUCERS; do
        cp "$exe" "$dir/dos/$p/PATCH16.EXE"
        SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout -k 10 600 \
            "$DOSBOX" -defaultconf -silent -nogui -nomenu \
            -set "dosbox machine=cga" -set "cpu cputype=8086" \
            -set "cpu core=normal" -set "cpu cycles=max" \
            -c "mount c \"$dir/dos/$p\"" -c "c:" \
            -c "call run.bat" -c "exit" >"$dir/dosbox-$p.log" 2>&1
        check_runs "$dir" "$dir/dos/$p" "$p" || status=1
    done
    return $status
}

run_grdos() {
    exe=$1 dir=$2
    status=0
    for p in $PRODUCERS; do
        cp "$exe" "$dir/dos/$p/PATCH16.EXE"
        if ! sh "$top/tests/grdos.sh" "$dir/dos/$p" "$dir/grdos-$p"; then
            echo "FAIL: $p: the GR-DOS run did not finish"
            status=1
        fi
        check_runs "$dir" "$dir/grdos-$p/got" "$p" "$dir/grdos-$p/serial.log" || status=1
    done
    return $status
}

# ------------------------------------------------------------------

[ $# -ge 1 ] || { sed -n '/^# usage:/,/^$/p' "$0" >&2; exit 2; }
cmd=$1; shift
case $cmd in
make)  make_corpus "$1" ;;
check) check_runs "$1" "$2" "$3" ;;
dosbox|grdos)
    exe=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
    dir=${2:-$(mktemp -d "${TMPDIR:-/tmp}/corpus.XXXXXX")}
    make_corpus "$dir" || exit 2
    if "run_$cmd" "$exe" "$dir"; then status=0; else status=1; fi
    if [ "$status" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
        echo "corpus directory: $dir"
    else
        rm -rf "$dir"
    fi
    exit $status ;;
*) sed -n '/^# usage:/,/^$/p' "$0" >&2; exit 2 ;;
esac
