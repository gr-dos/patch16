# Building patch16

patch16 is cross-built on Linux (x86-64) into `patch.exe`, a real-mode DOS program, with Open Watcom C in the compact model. It is linked with libc16, not Open Watcom's C library.

## What it needs

- `make`, a POSIX shell, `curl`, `unzip`, `tar` with `xz`, `sha256sum`, `awk`, `git` and `perl`;
- for the tests: DOSBox-X, GNU `diff`, and `mtools`; QEMU (`qemu-system-i386`) for the GR-DOS tests.

On Ubuntu 24.04, as CI uses: `sudo apt-get install dosbox-x qemu-system-x86 mtools`.

Nothing else is installed. The build downloads what it needs into `build/`, and checks each download's SHA-256:

| What | Pinned by | From |
|---|---|---|
| libc16's release archive, `libc16-0.05.zip` (headers, `LIBC16C.LIB`, `tools/fetch-watcom`) | `scripts/fetch-libc16` | github.com/gr-dos/libc16 releases |
| the Open Watcom 2.0 snapshot libc16 was built with | libc16's `tools/fetch-watcom` | github.com/open-watcom/open-watcom-v2 releases |
| GR-DOS 0.04's 1.44 MB floppy, for `make test-grdos` | `scripts/fetch-grdos` | github.com/gr-dos/gr-dos releases |

## Commands

| Command | What it does |
|---|---|
| `make` | builds `patch.exe`, and checks from the link map that it holds only patch16's objects and libc16's (`scripts/check-link`) |
| `make test` | `tests/run.sh` under DOSBox-X on an emulated 8086, and the round-trip corpus (`tests/corpus.sh`) |
| `make test-grdos` | the corpus on GR-DOS, booted in QEMU (`tests/grdos.sh`) |
| `make LIBC16_ROOT=../libc16` | builds with a libc16 checkout, already built with its own `make` |
| `make clean` | removes what the build made, but not the downloads |

## Sources

- `src/`: GNU `patch` 2.2's C files, as adapted; each change is marked `patch16:`.
- `compat/`: patch16's own DOS code (install, file names, formatting, DOS calls).
- `upstream/`: GNU `patch` 2.2's README, NEWS, ChangeLog and manual page, and the checksums of the 2.2 files (`scripts/fetch-upstream`).
- `tests/`: the tests.
- `docs/`: the manual (`DOS.md`), design, provenance and license research.

## Releases

A release is made when a merge to `main` changes `VERSION` (`.github/workflows/release.yml`). It builds and tests, then:

1. `scripts/release-files build/release` makes the source archive of the commit (`patch16-VERSION-src.tar.gz`), the source of the libc16 release linked in, the license files and the release notes. It refuses a checkout with changes, and a `dist16.source` that does not name this version and libc16 release.
2. `scripts/check-source` unpacks the source archive, builds `patch.exe` from it, and checks that it is the same, byte for byte.
3. The release `vVERSION` is made with `patch.exe` and those files.

To make a release, change `VERSION` and the `source` line of `dist16.source` together; if `scripts/fetch-libc16` changes libc16's version, change the `depends` line too. CI runs steps 1 and 2 on every pull request.
