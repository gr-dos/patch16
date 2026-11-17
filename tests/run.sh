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
# Usage: tests/run.sh [path/to/patch16.exe [path/to/patch16t.exe]]
# patch16t.exe is the test build (make build/patch16t.exe), which raises
# Ctrl-Break where P16BREAK says (tests/breakpt.c); without it those
# steps are skipped.
# The Git steps need git to make their patches; without it they are
# skipped. The disk-full step needs mtools (mformat, mcopy, mdir) to make and read
# a floppy image; without them it is skipped.
#
# Environment: DOSBOX (default dosbox-x), HOSTDIFF (default diff),
#              KEEP=1 to keep the work directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/patch16.exe}
texe=${2:-$top/build/patch16t.exe}
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
breaks=0
if [ -f "$texe" ]; then cp "$texe" patch16t.exe; breaks=1; fi
mkdir orig want

# udiff NAME: a -p1 patch from orig/NAME to want/NAME, with a/ and b/
# names as diff -u and git make them
udiff() {
    "$HOSTDIFF" -u --label "a/$1" --label "b/$1" "orig/$1" "want/$1"
}

printf 'first\nsecond\nthird\n' > orig/hello.c
printf 'first\nnew\nsecond\nthird\n' > want/hello.c
udiff hello.c > hello.pat
for f in a b c d e f g r s; do cp orig/hello.c $f.c; done
sed 's/hello\.c/a.c/g' hello.pat > a.pat
sed 's/hello\.c/b.c/g' hello.pat > b.pat
sed 's/hello\.c/d.c/g' hello.pat > d.pat
sed 's/hello\.c/e.c/g' hello.pat > e.pat
sed 's/hello\.c/r.c/g' hello.pat > r.pat
sed 's#hello\.c#sub/s.c#g' hello.pat > s.pat
mkdir sub
cp orig/hello.c sub/s.c
# a hunk that cannot apply: the line it deletes is not there
printf -- '--- a/c.c\n+++ b/c.c\n@@ -1,3 +1,3 @@\n first\n-zzz\n+new\n third\n' \
    > c.pat
printf 'stale\n' > C.RE1
# a context line that does not match: rejected without fuzz, applied
# with -F2 (it is the second line of the suffix context)
sed 's/hello\.c/f.c/g; s/^ second$/ SECOND/' hello.pat > f.pat
sed 's/hello\.c/g.c/g; s/^ second$/ SECOND/' hello.pat > g.pat
# an ed script, which patch16 does not apply
printf '1a\nnew\n.\n' > ed.pat
# -d, and no -p: the file is found by its basename in sub
sed 's#hello\.c#deep/dir/t.c#g' hello.pat > t.pat
cp orig/hello.c sub/t.c

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

# hostile and boundary hunk headers (16-bit sizes), each its own file
# so that a failure cannot spill into the next
mkdir mal
for n in 1 2 3 4 5 6 7 8 9; do cp orig/hello.c mal/m$n.c; done
hdr() { printf -- '--- a/m%s.c\n+++ b/m%s.c\n' "$1" "$1"; }
{ hdr 1; printf '@@ -1,16384 +1,16384 @@\n first\n'; } > mal/m1.pat
{ hdr 2; printf '@@ -1,65536 +1,1 @@\n first\n'; } > mal/m2.pat
{ hdr 3; printf '@@ -1,99999999999 +1,1 @@\n first\n'; } > mal/m3.pat
{ hdr 4; printf '@@ -1,-5 +1,3 @@\n first\n'; } > mal/m4.pat
{ hdr 5; printf '@@ -2147483647,1 +2147483647,1 @@\n first\n'; } > mal/m5.pat
{ printf -- '*** a/m6.c\n--- b/m6.c\n***************\n*** 10,5 ****\n'; } > mal/m6.pat
{ printf '1,70000c1\n< first\n---\n> new\n'; } > mal/m7.pat
# the largest hunk patch16 takes, and one line more
: > orig/huge.txt
awk 'BEGIN { for (i = 1; i <= 15992; i++) printf "%d\n", i }' > want/huge.txt
udiff huge.txt > huge.pat
cp orig/huge.txt huge.txt
{ hdr 8; printf '@@ -0,0 +1,15993 @@\n'
  awk 'BEGIN { for (i = 1; i <= 15993; i++) printf "+%d\n", i }'; } > mal/m8.pat
# the longest patch line (16383 bytes with its + and newline), and one
# byte more
long() { head -c "$1" /dev/zero | tr '\0' x; }
printf 'first\n%s\n' "$(long 16381)" > want/long.txt
printf 'first\n' > orig/long.txt
udiff long.txt > long.pat
cp orig/long.txt long.txt
{ hdr 9; printf '@@ -1,1 +1,2 @@\n first\n+%s\n' "$(long 16382)"; } > mal/m9.pat

# truncated and empty patches: each leaves its file unchanged; a hunk cut
# short is rejected (1) -- 2.2 takes missing lines as blank ones chopped
# in transit, which then do not match -- and the rest are errors (2)
mkdir trunc
for n in 1 2 3 4 5 6 7 8; do cp orig/hello.c trunc/t$n.c; done
thdr() { printf -- '--- a/t%s.c\n+++ b/t%s.c\n' "$1" "$1"; }
{ thdr 1; printf '@@ -1,3 +1,4 @@\n first\n+new\n'; } > trunc/t1.pat
{ thdr 2; printf '@@ -1,3 +1,4 @@\n first\n+new\n second\n thi'; } > trunc/t2.pat
printf -- '*** a/t3.c\n--- b/t3.c\n***************\n*** 1,3 ****\n--- 1,4 ----\n  first\n+ new\n' > trunc/t3.pat
printf -- '*** a/t4.c\n--- b/t4.c\n***************\n*** 1,3 ****\n  first\n  second\n' > trunc/t4.pat
printf '1a2\n' > trunc/t5.pat
{ thdr 6; printf '@@ -1,3 +1,4 @@\n'; } > trunc/t6.pat
: > trunc/t7.pat
head -c 2000 /dev/urandom | tr -d '\n' > trunc/t8.pat

# the line index: files whose line counts are at and around an index
# block (1024 lines), changed at both ends; a 20000-byte line copied
# through; and a line over the 32000-byte limit, which is refused
for n in 1023 1024 1025; do
    awk -v n=$n 'BEGIN { for (i = 1; i <= n; i++) printf "row %d\n", i }' > orig/x$n.txt
    awk -v n=$n '{ if (NR == 2) print "second"; else if (NR == n - 1) print "penultimate"; else print }
                 END { print "appended" }' orig/x$n.txt > want/x$n.txt
    udiff x$n.txt > x$n.pat
    cp orig/x$n.txt x$n.txt
done
# (outside the hunk's context, where it would be a patch line)
{ printf 'top\n1\n2\n3\n4\n%s\nbottom\n' "$(long 20000)"; } > orig/wide.txt
{ printf 'TOP\n1\n2\n3\n4\n%s\nbottom\n' "$(long 20000)"; } > want/wide.txt
udiff wide.txt > wide.pat
cp orig/wide.txt wide.txt
{ printf 'top\n%s\n' "$(long 32001)"; } > orig/over.txt
{ printf 'TOP\n%s\n' "$(long 32001)"; } > want/over.txt
udiff over.txt > over.pat
cp orig/over.txt over.txt

# Ctrl-Break while applying (in sub, through -d) and while installing
cp orig/hello.c sub/k.c
for f in k m n; do sed "s/hello\.c/$f.c/g" hello.pat > $f.pat; done
cp orig/hello.c m.c
cp orig/hello.c n.c
# the new file lost between moving the original aside and moving it in:
# the original is put back, with and without -b
for f in q u; do sed "s/hello\.c/$f.c/g" hello.pat > $f.pat; cp orig/hello.c $f.c; done

# a disk full: a 360 KB floppy image with big.txt, big.pat and a filler
# leaving 40 KB, too little for the 75 KB patched file
full=0
if command -v mformat >/dev/null && command -v mcopy >/dev/null &&
    command -v mdir >/dev/null; then
    mformat -C -f 360 -i fd.img :: &&
    mcopy -i fd.img orig/big.txt big.pat :: &&
    free=$(mdir -i fd.img :: | sed -n 's/^ *\([0-9 ]*\) bytes free.*/\1/p' | tr -d ' ') &&
    fill=$((free - 40960)) &&
    [ "$fill" -gt 0 ] && [ "$fill" -lt 368640 ] &&
    head -c "$fill" /dev/zero > filler.bin &&
    mcopy -i fd.img filler.bin :: &&
    rm filler.bin &&
    full=1
fi

# a disk full on another drive: temp files are made in the current
# directory, C:, so a target on A: is copied there rather than renamed.
# xd.img holds XB.TXT (an existing target), XR.REJ (a reject that must
# not be replaced) and a filler leaving 40 KB. Each copy runs out of
# room; each must leave the disk as it was: no partial new file, no
# partial reject, the original put back.
#   xn.pat  makes the new file A:\XN.TXT (75 KB)
#   xb.pat  patches A:\XB.TXT (the new version is 75 KB)
#   xr.pat  fails every hunk on xr.txt; its 70 KB reject goes to A:,
#           as XR.RE1 since XR.REJ exists
xfull=0
if command -v mformat >/dev/null && command -v mcopy >/dev/null &&
    command -v mdir >/dev/null; then
    : > orig/xn.txt
    cp want/big.txt want/xn.txt
    udiff xn.txt > xn.pat
    sed 's#big\.txt#xb.txt#g' big.pat > xb.pat
    awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "row %d of the original\n", i }' \
        > orig/xr.txt
    awk '{ if (NR % 10 == 0) print "changed " $0; else print }' orig/xr.txt > want/xr.txt
    udiff xr.txt > xr.pat
    awk '{ print "other " $0 }' orig/xr.txt > xr.txt
    printf 'keep\r\n' > XR.REJ
    mformat -C -f 360 -i xd.img :: &&
    mcopy -i xd.img orig/big.txt ::XB.TXT &&
    mcopy -i xd.img XR.REJ ::XR.REJ &&
    rm XR.REJ &&
    free=$(mdir -i xd.img :: | sed -n 's/^ *\([0-9 ]*\) bytes free.*/\1/p' | tr -d ' ') &&
    fill=$((free - 40960)) &&
    [ "$fill" -gt 0 ] && [ "$fill" -lt 368640 ] &&
    head -c "$fill" /dev/zero > filler.bin &&
    mcopy -i xd.img filler.bin :: &&
    rm filler.bin &&
    [ "$(wc -c < xr.pat)" -gt 61440 ] &&
    xfull=1
fi

# line ends: a patch's CR LF or LF matches either in the file, and added
# lines take the line ends most of the file has (for a file with none,
# the patch's); lines not changed keep theirs
printf 'one\r\ntwo\r\nthree\r\n' > dl.txt
printf -- '--- a/dl.txt\n+++ b/dl.txt\n@@ -1,3 +1,4 @@\n one\n-two\n+TWO\n+2b\n three\n' > dl.pat
printf 'one\r\nTWO\r\n2b\r\nthree\r\n' > want/dl.txt
printf 'one\ntwo\nthree\n' > ud.txt
printf -- '--- a/ud.txt\r\n+++ b/ud.txt\r\n@@ -1,3 +1,3 @@\r\n one\r\n-two\r\n+TWO\r\n three\r\n' > ud.pat
printf 'one\nTWO\nthree\n' > want/ud.txt
printf 'one\r\ntwo\nthree\r\nfour\r\n' > mx.txt
printf -- '--- a/mx.txt\n+++ b/mx.txt\n@@ -1,4 +1,5 @@\n one\n two\n+new\n three\n four\n' > mx.pat
printf 'one\r\ntwo\nnew\r\nthree\r\nfour\r\n' > want/mx.txt
: > em.txt
printf -- '--- a/em.txt\r\n+++ b/em.txt\r\n@@ -0,0 +1,2 @@\r\n+a\r\n+b\r\n' > em.pat
printf 'a\r\nb\r\n' > want/em.txt
printf 'one\r\ntwo  words\r\nthree\r\n' > ws.txt
printf -- '--- a/ws.txt\n+++ b/ws.txt\n@@ -1,3 +1,3 @@\n one\n-two words\n+2\n three\n' > ws.pat
printf 'one\r\n2\r\nthree\r\n' > want/ws.txt
printf 'one\r\ntwo\r\nthree\r\n' > df.txt
sed 's/dl\.txt/df.txt/g' dl.pat > df.pat
printf 'one\r\n#ifndef X\r\ntwo\r\n#else\r\nTWO\r\n2b\r\n#endif /* X */\r\nthree\r\n' > want/df.txt
# -D with a context diff's changed (!) lines
printf 'first\nsecond\nthird\n' > dc.txt
printf 'first\nSECOND\nthird\n' > want/dc-new.txt
"$HOSTDIFF" -c --label a/dc.txt --label b/dc.txt dc.txt want/dc-new.txt > dc.pat
printf 'first\n#ifndef X\nsecond\n#else\nSECOND\n#endif /* X */\nthird\n' > want/dc.txt

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
rem --- a read-only file is refused, and its hunks are rejects
attrib +r r.c
patch16 -p1 -i r.pat >o14.txt
call rc 14
attrib -r r.c
rem --- fuzz: none unless asked for
patch16 -p1 -i f.pat >o15.txt
call rc 15
patch16 -F2 -p1 -i g.pat >o16.txt
call rc 16
rem --- no ed scripts, no -e
patch16 a.c ed.pat >o17.txt
call rc 17
patch16 -e a.c ed.pat >o18.txt
call rc 18
rem --- -d, and no -p; the directory is current again afterwards
patch16 -d sub -i ..\t.pat >o19.txt
call rc 19
cd >o20.txt
rem --- hostile headers: 21 to 29 fail with status 2
cd mal
..\patch16 -p1 -i m1.pat >..\o21.txt
call ..\rc 21
..\patch16 -p1 -i m2.pat >..\o22.txt
call ..\rc 22
..\patch16 -p1 -i m3.pat >..\o23.txt
call ..\rc 23
..\patch16 -p1 -i m4.pat >..\o24.txt
call ..\rc 24
..\patch16 -p1 -i m5.pat >..\o25.txt
call ..\rc 25
..\patch16 -p1 -i m6.pat >..\o26.txt
call ..\rc 26
..\patch16 m7.c m7.pat >..\o27.txt
call ..\rc 27
..\patch16 -p1 -i m8.pat >..\o28.txt
call ..\rc 28
..\patch16 -p1 -i m9.pat >..\o29.txt
call ..\rc 29
cd ..\trunc
rem --- truncated: 91 to 93 rejected (1), 94 to 98 fail (2)
..\patch16 -p1 -i t1.pat >..\o91.txt
call ..\rc 91
..\patch16 -p1 -i t2.pat >..\o92.txt
call ..\rc 92
..\patch16 -p1 -i t3.pat >..\o93.txt
call ..\rc 93
..\patch16 -p1 -i t4.pat >..\o94.txt
call ..\rc 94
..\patch16 t5.c t5.pat >..\o95.txt
call ..\rc 95
..\patch16 -p1 -i t6.pat >..\o96.txt
call ..\rc 96
..\patch16 t7.c t7.pat >..\o97.txt
call ..\rc 97
..\patch16 t8.c t8.pat >..\o98.txt
call ..\rc 98
cd ..
rem --- the largest hunk and the longest line apply
patch16 -p1 -i huge.pat >o30.txt
call rc 30
patch16 -p1 -i long.pat >o31.txt
call rc 31
rem --- the line index
patch16 -p1 -i x1023.pat >o32.txt
call rc 32
patch16 -p1 -i x1024.pat >o33.txt
call rc 33
patch16 -p1 -i x1025.pat >o34.txt
call rc 34
patch16 -p1 -i wide.pat >o35.txt
call rc 35
patch16 -p1 -i over.pat >o36.txt
call rc 36
rem --- line ends
patch16 -p1 -i dl.pat >o45.txt
call rc 45
patch16 -p1 -i ud.pat >o46.txt
call rc 46
patch16 -p1 -i mx.pat >o47.txt
call rc 47
patch16 -p1 -i em.pat >o48.txt
call rc 48
patch16 -l -p1 -i ws.pat >o49.txt
call rc 49
patch16 -D X -p1 -i df.pat >o50.txt
call rc 50
patch16 -D X -p1 -i dc.pat >o51.txt
call rc 51
if not exist patch16t.exe goto nobreak
rem --- Ctrl-Break: while applying it cleans up and exits 2; between the
rem --- renames that install the file it is ignored
set P16BREAK=1
patch16t -d sub -p1 -i ..\k.pat >o37.txt
call rc 37
cd >o38.txt
set P16BREAK=2
patch16t -b -p1 -i m.pat >o39.txt
call rc 39
patch16t -p1 -i n.pat >o40.txt
call rc 40
set P16BREAK=
set P16LOSE=2
patch16t -p1 -i q.pat >o41.txt
call rc 41
patch16t -b -p1 -i u.pat >o42.txt
call rc 42
set P16LOSE=
:nobreak
if not exist fd.img goto nofull
rem --- a disk full: patch16 fails and the original is kept
imgmount a fd.img -t floppy >nul
a:
c:\patch16 -p1 -i big.pat >c:\o43.txt
call c:\rc 43
c:
dir a:\ >o44.txt
imgmount -u a >nul
:nofull
if not exist xd.img goto noxfull
rem --- a disk full on another drive: each copy fails and is taken back
imgmount a xd.img -t floppy >nul
patch16 -i xn.pat a:\xn.txt >o52.txt
call rc 52
patch16 -i xb.pat a:\xb.txt >o53.txt
call rc 53
patch16 -r a:\xr.rej -i xr.pat xr.txt >o54.txt
call rc 54
dir a:\ >o55.txt
imgmount -u a >nul
:noxfull
EOF

# a last line without a newline ("\ No newline at end of file"): round
# trips made with diff -u, -c and normal diff, steps 60 on, each its own
# file; NL_CASES lists them as name, old text, new text (printf formats)
NL_CASES='nb a\nb a\nc
ad a\nb a\nb\n
rm a\nb\n a\nb
ap a\nb a\nb\nc\n
fa x\n1\n2\n3\n4\na\nb y\n1\n2\n3\n4\na\nb'
nl=60
printf '%s\n' "$NL_CASES" | while read -r name old new; do
    for fmt in u c n; do
        f=$name$fmt.txt
        printf "$old" > orig/$f
        printf "$new" > want/$f
        cp orig/$f $f
        case $fmt in
            u) udiff $f > $name$fmt.pat ;;
            c) "$HOSTDIFF" -c --label "a/$f" --label "b/$f" orig/$f want/$f > $name$fmt.pat ;;
            n) "$HOSTDIFF" orig/$f want/$f > $name$fmt.pat ;;
        esac
        if [ $fmt = n ]; then
            echo "patch16 $f $name$fmt.pat >o$nl.txt" >> steps.bat
        else
            echo "patch16 -p1 -i $name$fmt.pat >o$nl.txt" >> steps.bat
        fi
        echo "call rc $nl" >> steps.bat
        echo "$nl $f" >> nlsteps.txt
        nl=$((nl + 1))
    done
done
# Git: a text change, a new file and a deleted file apply; a binary
# change (with --binary and without), a rename (with and without edits)
# a copy and a mode change are reported as not applied (status 1); a
# mode change with a text change has its text applied, with a note. gitb and gitp hold the old tree for each patch.
gits=0
if command -v git >/dev/null; then
    mkdir repo
    (
        cd repo && git init -q &&
        printf 'one\ntwo\nthree\n' > t1.c &&
        head -c 300 /dev/urandom > img.bin &&
        seq 1 20 > r_old.c && seq 100 130 > m_old.c && seq 200 230 > c_src.c &&
        printf 'echo hi\n' > x.sh && printf 'echo hi\n' > e.sh &&
        printf 'gone\nsoon\n' > d.c &&
        git add . && git -c user.email=t@t -c user.name=t commit -q -m 1 &&
        printf 'one\nTWO\nthree\n' > t1.c &&
        head -c 300 /dev/urandom > img.bin &&
        git mv r_old.c r_new.c && git mv m_old.c m_new.c &&
        sed -i 's/^115$/one hundred fifteen/' m_new.c &&
        cp c_src.c c_dst.c && chmod +x x.sh && chmod +x e.sh &&
        printf 'echo there\n' >> e.sh &&
        printf 'brand\nnew\n' > n.c && git add -A && git rm -q d.c &&
        git diff --cached -M -C --find-copies-harder --binary > ../gitb.pat &&
        git diff --cached -M -C --find-copies-harder > ../gitp.pat &&
        mkdir ../gitb ../gitp ../want/git &&
        git archive HEAD | tar -x -C ../gitb &&
        git archive HEAD | tar -x -C ../gitp &&
        git archive HEAD | tar -x -C ../want/git &&
        cp t1.c n.c e.sh ../want/git/
    ) && grep -q '^copy from c_src.c' gitp.pat && gits=1
    rm -rf repo
fi
if [ "$gits" = 1 ]; then
    for g in gitb gitp; do
        printf '%s\n' "cd $g" "..\\patch16 -p1 -i ..\\$g.pat >..\\o$g.txt" \
            "call ..\\rc $g" "cd .." >> steps.bat
    done
fi

# and on a CR LF file, with an LF patch
printf 'a\r\nb' > crnl.txt
printf -- '--- a/crnl.txt\n+++ b/crnl.txt\n@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+c\n\\ No newline at end of file\n' > crnl.pat
printf 'a\r\nc' > want/crnl.txt
echo "patch16 -p1 -i crnl.pat >o80.txt" >> steps.bat
echo "call rc 80" >> steps.bat

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout -k 10 300 \
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

# absent WHAT FILE
absent() {
    if [ -e "$2" ]; then not_ok "$1: $2 exists"; else ok; fi
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
    head -1 O13.TXT | tr -d '\r' | grep -q "^patch16 $(cat "$top/VERSION") (GNU patch 2.2)\$"
}
if check_version; then ok; else not_ok "step 13: version"; fi

rc 14 1
expect 14 <<'EOF'
File r.c is read-only; refusing to patch
Hunk #1 ignored at 1.
1 out of 1 hunk ignored--saving rejects to r.REJ
EOF
same "step 14: read-only file unchanged" r.c orig/hello.c
if tr -d '\r' < R.REJ | grep -q '^+ new$'; then ok; else not_ok "step 14: reject holds the hunk"; fi

rc 15 1
expect 15 <<'EOF'
patching file f.c
Hunk #1 FAILED at 1.
1 out of 1 hunk FAILED--saving rejects to f.REJ
EOF
same "step 15: no fuzz" F.C orig/hello.c
rc 16 0
expect 16 <<'EOF'
patching file g.c
EOF
same "step 16: fuzz 2" G.C want/hello.c
rc 17 2
same "step 17: ed script not applied" A.C want/hello.c
rc 18 2
rc 19 0
expect 19 <<'EOF'
patching file t.c
EOF
same "step 19: -d and basename" sub/T.C want/hello.c
expect 20 <<'EOF'
C:\
EOF

for n in 1 2 3 4 5 6 7 8 9; do
    rc 2$n 2
    same "step 2$n: file unchanged" mal/m$n.c orig/hello.c
done
for n in 1 2 3 4 5 6 7 8; do
    case $n in 1|2|3) want=1 ;; *) want=2 ;; esac
    rc 9$n $want
    f=trunc/t$n.c; [ -f $f ] || f=trunc/T$n.C
    same "step 9$n: truncated patch, file unchanged" $f orig/hello.c
done
for n in 1 2 3; do
    if [ -f trunc/T$n.REJ ]; then ok; else not_ok "step 9$n: reject written"; fi
done
rc 30 0
same "step 30: largest hunk" HUGE.TXT want/huge.txt
rc 31 0
same "step 31: longest line" LONG.TXT want/long.txt
rc 32 0
same "step 32: 1023 lines" X1023.TXT want/x1023.txt
rc 33 0
same "step 33: 1024 lines" X1024.TXT want/x1024.txt
rc 34 0
same "step 34: 1025 lines" X1025.TXT want/x1025.txt
rc 35 0
same "step 35: a 20000-byte line" WIDE.TXT want/wide.txt
rc 36 2
same "step 36: over the line limit, unchanged" over.txt orig/over.txt

rc 45 0
same "step 45: LF patch, CR LF file" DL.TXT want/dl.txt
rc 46 0
same "step 46: CR LF patch, LF file" UD.TXT want/ud.txt
rc 47 0
same "step 47: mixed file" MX.TXT want/mx.txt
rc 48 0
same "step 48: empty file, CR LF patch" EM.TXT want/em.txt
rc 49 0
same "step 49: -l, CR LF file" WS.TXT want/ws.txt
rc 50 0
same "step 50: -D, CR LF file" DF.TXT want/df.txt
rc 51 0
same "step 51: -D, context diff" DC.TXT want/dc.txt

while read -r n f; do
    rc $n 0
    same "step $n: no newline at end ($f)" "$(echo $f | tr a-z A-Z)" want/$f
done < nlsteps.txt
rc 80 0
same "step 80: no newline at end, CR LF file" CRNL.TXT want/crnl.txt

if [ "$gits" = 1 ]; then
    for g in gitb gitp; do
        G=$(echo $g | tr a-z A-Z)
        rc $G 1
        expect $G <<'EOF'
b/c_dst.c: patch16 does not apply a copy; not changed
patching file d.c
b/e.sh: patch16 does not change file modes; applying the text
patching file e.sh
b/img.bin: patch16 does not apply a binary change; not changed
b/m_new.c: patch16 does not apply a rename; not changed
Hunk #1 ignored at 13.
1 out of 1 hunk ignored--saving rejects to m_old.REJ
patching file n.c
b/r_new.c: patch16 does not apply a rename; not changed
patching file t1.c
b/x.sh: patch16 does not apply a mode change; not changed
EOF
        same "$g: mode and text change" $g/E.SH want/git/e.sh
        same "$g: text change" $g/T1.C want/git/t1.c
        same "$g: new file" $g/N.C want/git/n.c
        same "$g: binary file unchanged" $g/img.bin want/git/img.bin
        same "$g: renamed file unchanged" $g/r_old.c want/git/r_old.c
        same "$g: renamed and edited file unchanged" $g/m_old.c want/git/m_old.c
        same "$g: copied file unchanged" $g/c_src.c want/git/c_src.c
        absent "$g: no rename target" $g/R_NEW.C
        absent "$g: no copy target" $g/C_DST.C
        if [ -s $g/D.C ]; then not_ok "$g: deleted file not emptied"; else ok; fi
    done
elif command -v git >/dev/null; then
    not_ok "Git steps: could not make the Git patches"
else
    echo "skipped: Git steps (no git)"
fi

if [ "$breaks" = 1 ]; then
    rc 37 2
    same "step 37: Ctrl-Break, file unchanged" sub/k.c orig/hello.c
    expect 38 <<'EOF'
C:\
EOF
    rc 39 0
    same "step 39: Ctrl-Break ignored while installing" M.C want/hello.c
    same "step 39: backup" M.ORG orig/hello.c
    rc 40 0
    same "step 40: Ctrl-Break ignored while installing" N.C want/hello.c
    rc 41 2
    same "step 41: original put back" Q.C orig/hello.c
    rc 42 2
    same "step 42: original put back from its backup" U.C orig/hello.c
    absent "step 42: no backup left" U.ORG
else
    echo "skipped: Ctrl-Break and rollback steps (no $texe)"
fi
if [ "$full" = 1 ]; then
    rc 43 2
    mcopy -n -i fd.img ::big.txt full.txt
    same "step 43: disk full, original kept" full.txt orig/big.txt
    if tr -d '\r' < O44.TXT | grep -q '^ *3 File(s)' &&
        tr -d '\r' < O44.TXT | grep -q ' 40,960 Bytes free'; then
        ok
    else
        not_ok "step 44: files left on the full disk"
        tr -d '\r' < O44.TXT | sed 's/^/    /'
    fi
else
    echo "skipped: disk-full step (no mtools)"
fi
if [ "$xfull" = 1 ]; then
    rc 52 2
    rc 53 2
    rc 54 2
    for f in XB.TXT XR.REJ; do mcopy -n -i xd.img "::$f" "x-$f"; done
    same "step 53: disk full on another drive, original put back" x-XB.TXT orig/big.txt
    printf 'keep\r\n' > want/XR.REJ
    same "step 54: existing reject kept" x-XR.REJ want/XR.REJ
    rm -f x-XB.TXT x-XR.REJ want/XR.REJ
    # only what was there before, and the same room
    files=$(tr -d '\r' < O55.TXT | awk '$2 ~ /^[A-Z]+$/ && NF >= 4 { print $1 "." $2 }' | sort | tr '\n' ' ')
    if [ "$files" = "FILLER.BIN XB.TXT XR.REJ " ] &&
        tr -d '\r' < O55.TXT | grep -q ' 40,960 Bytes free'; then
        ok
    else
        not_ok "step 55: files left on the full disk on another drive"
        tr -d '\r' < O55.TXT | sed 's/^/    /'
    fi
else
    echo "skipped: disk-full steps on another drive (no mtools)"
fi
leftover=$(ls sub | grep -v -x -E 'S\.C|T\.C|t\.c|k\.c|s\.c')
if [ -z "$leftover" ]; then ok; else not_ok "files left behind in sub:" $leftover; fi

# no temp file is left behind
leftover=$(ls | grep -v -E '^(O|R)[0-9]+\.TXT$' |
    grep -v -x -E 'orig|want|sub|mal|trunc|gitb|gitp|git[bp]\.pat|OGIT[BP]\.TXT|RGIT[BP]\.TXT|nlsteps\.txt|CRNL\.TXT|[A-Z]{2}[UCN]\.TXT|[a-z]{2}[ucn]\.(txt|pat)|crnl\.pat|patch16t\.exe|M\.ORG|fd\.img|xd\.img|XR\.TXT|xr\.txt|full\.txt|DL\.TXT|UD\.TXT|MX\.TXT|EM\.TXT|WS\.TXT|DF\.TXT|DC\.TXT|ed\.pat|HUGE\.TXT|LONG\.TXT|huge\.txt|long\.txt|X10[0-9]+\.TXT|WIDE\.TXT|over\.txt|[a-z0-9]+\.pat|[A-Z]\.C|[A-Z]\.(ORG|OR1|REJ|RE[12])|BIG\.TXT|CRLF\.TXT|[a-z]+\.pat|C\.RE1|stale\.txt|got\.txt|want\.txt|patch16\.exe|rc\.bat|steps\.bat|dosbox\.log|[a-z]+\.c|big\.txt|crlf\.txt')
if [ -z "$leftover" ]; then ok; else not_ok "files left behind:" $leftover; fi

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
