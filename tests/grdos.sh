#!/bin/sh
#
# Run a DOS disk's RUN.BAT on GR-DOS, in QEMU: boot a copy of the pinned
# GR-DOS floppy (scripts/fetch-grdos) in A:, with an AUTOEXEC.BAT that
# runs B:\RUN.BAT, and the files of DIR on a new 1.44 MB floppy in B:.
# AUTOEXEC.BAT reports to COM1 (OUT/serial.log) when it starts and ends,
# and CTTY AUX sends the console there in between, so that what programs
# write to standard error is kept; QEMU is stopped at the end, or after
# TIMEOUT seconds. B:'s files are then copied back to OUT/got.
# tests/corpus.sh uses it for the round-trip corpus.
#
# usage: tests/grdos.sh DIR OUT
#
# Needs qemu-system-i386, mtools and curl. Environment: TIMEOUT (default
# 300), GRDOS_IMG (default: fetched by scripts/fetch-grdos).

set -eu

[ $# -eq 2 ] || { echo "usage: $0 DIR OUT" >&2; exit 2; }
dir=$1 out=$2
top=$(cd "$(dirname "$0")/.." && pwd)
timeout=${TIMEOUT:-300}
img=${GRDOS_IMG:-$(cd "$top" && scripts/fetch-grdos)}
case $img in /*) ;; *) img=$top/$img ;; esac

rm -rf "$out"
mkdir -p "$out/got"

cp "$img" "$out/a.img"
chmod u+w "$out/a.img"
printf '@ECHO OFF\r\nPATH A:\\\r\nECHO PATCH16-GRDOS-BEGIN>AUX\r\nCTTY AUX\r\nB:\r\nCALL RUN.BAT\r\nA:\r\nECHO PATCH16-GRDOS-END\r\n' \
    > "$out/AUTOEXEC.BAT"
mcopy -o -i "$out/a.img" "$out/AUTOEXEC.BAT" ::AUTOEXEC.BAT

mformat -C -f 1440 -i "$out/b.img" ::
for f in "$dir"/*; do
    case $(basename "$f") in *[a-z]*) continue ;; esac   # host-only files
    mcopy -s -i "$out/b.img" "$f" ::
done

: > "$out/serial.log"
qemu-system-i386 -display none -m 4 -no-reboot \
    -drive "file=$out/a.img,if=floppy,index=0,format=raw" \
    -drive "file=$out/b.img,if=floppy,index=1,format=raw" \
    -boot a -serial "file:$out/serial.log" -monitor none &
pid=$!

finished=1
start=$(date +%s)
until tr -d '\r' < "$out/serial.log" | grep -qx PATCH16-GRDOS-END; do
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "grdos: QEMU exited early" >&2
        break
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
        echo "grdos: no end after $timeout seconds" >&2
        finished=0
        break
    fi
    sleep 1
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
tr -d '\r' < "$out/serial.log" | grep -qx PATCH16-GRDOS-BEGIN ||
    echo "grdos: AUTOEXEC.BAT did not start" >&2

mcopy -s -n -i "$out/b.img" '::*' "$out/got/"
tr -d '\r' < "$out/serial.log" | grep -qx PATCH16-GRDOS-END && [ "$finished" = 1 ]
