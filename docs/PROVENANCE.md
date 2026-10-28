# patch16: provenance

Where each source module comes from (DESIGN.md §3.4). Licensing is in `docs/LICENSE-RESEARCH.md` §8.

## Rules

- **Baseline:** GNU `patch` 2.2, tag `v2.2`, commit `bcce1233902dc7a94623b3a90cd7920c44f22474`, GPL-2.0-or-later. `scripts/fetch-upstream` fetches it and checks it against `upstream/MANIFEST.sha256`.
- **Adapted upstream files** keep their copyright and license notices verbatim. Our changes are marked by an added `Copyright <year> patch16 contributors` line under the upstream lines, and by the git history. The first commit of each such file is the unmodified upstream file, so `git log -p` separates GNU/Wall code from ours.
- **New modules** carry the same GPLv2-or-later notice with only our copyright line. Each gets an entry below, with references consulted and tests (DESIGN.md §3.4).
- **Other GPLv2-or-later sources:** code from a later GNU `patch` release (≤ 2.5.9) gets an entry here naming the release, file and change, with its notices preserved.
- **Excluded:** `libc16` gets no code from here. No Jörg Schilling-authored code is used, and no GPLv3-only GNU releases (2.6 onward).

## Upstream inventory and planned disposition

| File | Lines | Copyright | Plan |
|---|---:|---|---|
| `patch.c` | 1127 | Wall 1984–88; FSF 1989–97 | adapt: main loop, options, fuzz default `-F0`, safe install |
| `pch.c` | 1533 | Wall 1986–88; FSF 1990–97 | adapt: bounded hunk sizes; add `\ No newline at end of file` handling; Git preamble |
| `inp.c` | 501 | Wall 1986, 1988; FSF 1991–97 | adapt or replace plan A/B with a bounded, file-backed line index (PORT-FEASIBILITY.md §4) |
| `util.c` | 681 | Wall 1986; FSF 1992–97 | adapt: `move_file`, `ask`, signals, `makedirs` and temp files move behind `compat/` |
| `version.c` | 30 | Wall 1984–88; FSF 1989–97 | adapt: `patch16` version text |
| `common.h`, `inp.h`, `pch.h`, `util.h`, `version.h` | | Wall / FSF | adapt |
| `addext.c` | 89 | FSF (MacKenzie, Eggert) | adapt for 8.3: `.ORG` and `.REJ` replace the extension; no silent overwrite |
| `backupfile.c`, `backupfile.h` | 289 | FSF (MacKenzie) | keep or trim (numbered backups may not fit 8.3) |
| `argmatch.c`, `argmatch.h` | 99 | FSF (MacKenzie) | keep (`--version-control`) |
| `basename.c` | 24 | FSF | keep; also handle `\` and `X:` |
| `getopt.c`, `getopt1.c`, `getopt.h` | 1137 | FSF | keep (`getopt_long`, for `--dry-run` and the other long options) |
| `memchr.c` | 199 | FSF | keep (`libc16` has no `memchr`) |
| `rename.c` | 51 | FSF | **not used**: emulates `rename` with `link`/`unlink`; `libc16`'s `rename` replaces it |
| `patch.man` | | | basis for `docs/DOS.md` |
| `COPYING` | | FSF | becomes `LICENSES/GPL-2.0.txt` |
| `README`, `NEWS`, `ChangeLog` | | | kept with the upstream notices; README's license statement is quoted in LICENSE-RESEARCH.md §8 |
| `configure`, `configure.in`, `config.hin`, `acconfig.h`, `Makefile.in`, `INSTALL`, `install-sh`, `mkinstalldirs` | | FSF / M.I.T. | not used; a fixed DOS `config.h` and a Makefile replace them |

## New modules (`compat/`)

All by patch16 contributors, GPLv2-or-later, written for this port; no code taken from elsewhere. References are the `libc16` specs (`docs/spec/`) and the MS-DOS INT 21h function descriptions.

| File | What | Tests |
|---|---|---|
| `compat/include/config.h` | the fixed DOS configuration that replaces `configure` | build |
| `compat/include/p16.h`, `unistd.h`, `signal.h`, `assert.h` | POSIX names GNU `patch` uses, mapped onto `libc16` and the adapters below | build |
| `compat/fmt.c` | message formatter: `%s %c %d %ld %o %%` with a width, nothing else (decision 7) | `tests/run.sh` (messages) |
| `compat/dos.c` | `isatty`, `fstat` (IOCTL 4400h), `chdir` (3Bh), `creat` (binary), `tmpnam` (5Ah), checked `atol`; stubs for `system`, `popen`, `link`, signals | `tests/run.sh` |
| `compat/install.c` | safe install: the original moves aside before the new file goes in and is put back on failure; backups and rejects take the next free name, never replacing a file (decision 6) | `tests/run.sh` steps 1–9 |

## Changes to upstream files

Each change is commented `patch16:` in the source; `git log -p src/` shows it against the unmodified import.

| File | Change |
|---|---|
| `util.c` | `move_file` builds the backup name as before and calls `p16_move_file`; GNU's same-file search, which never ends on DOS (`st_ino` is always 0), is removed. `copy_file` opens binary. |
| `patch.c` | generated reject names go through `p16_move_new` (`FOO.REJ`, `FOO.RE1`, …), and the message names the file used; `cleanup` restores an original that was moved aside; output and reject files open binary |
| `addext.c` | an extension beginning with `.` replaces the name's own (`FOO.C` → `FOO.ORG`) |
| `backupfile.c` | the default suffix is `.ORG` |
| `basename.c` | `\` and `:` also end a directory or drive prefix |
| `inp.c`, `pch.c` | every file opens binary, and a patch on standard input is read binary |

## Historical material

Larry Wall's patch 2.0 pl12 as shipped in X11R3 (`upstream/x11r3-patch-2.0pl12.sha256`) is documented in LICENSE-RESEARCH.md §1–§7 as history only. No code is taken from it.

## Reference-only material consulted

- GNU `patch` git, tags `v2.1` through `v2.6`: README, NEWS, COPYING, ChangeLog and file notices, for the license chain.
- `libc16` (`../libc16`, release 0.04, and 0.05 for `rename`, `unlink`, `fseek` and `ftell`): headers and `docs/` specs, for the API gap list and the adapters.
