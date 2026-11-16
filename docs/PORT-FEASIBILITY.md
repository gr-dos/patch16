# patch16: port feasibility (E1)

**Status:** E1 exploration done 2026-10-28, for the **GNU `patch` 2.2** baseline (LICENSE-RESEARCH.md §8). Appendix A keeps the earlier findings for Wall's 1988 code.
**Inputs:** GNU `patch` 2.2 (`scripts/fetch-upstream`); `libc16` 0.04 built from `../libc16`; the Open Watcom snapshot `libc16` pins (`watcom-2026-10-01-Build`)

## 1. Summary

- **Viable.** All 13 C files that 2.2 builds compile with `wcc -0 -ms` and `-mc` against `libc16`'s headers. The only additions are a hand-written `config.h`, a generated `patchlevel.h`, and stub `<assert.h>`/`<signal.h>`; no source edits were needed.
- **Size:** 28.4 KB of `_TEXT` (small) or 35.7 KB (compact), plus about 10 KB of static `DGROUP` and a 2 KB stack, before library members. **Compact** is the chosen model (decision 9); measure again after the line-index work.
- **2.2 already does** what several decisions ask for:
  - `-n` is `--normal` and `--dry-run` exists (decision 1);
  - exit status is 0/1/2 (decision 2);
  - no `-p` means strip to the basename (decision 4);
  - unified diffs are supported;
  - plan A's size arithmetic is overflow-checked.
- **Still to do:**
  1. 16-bit `size_t` overflows in hunk-array growth and in plan B. Hostile input can trigger both (§4).
  2. Plan A is limited to files of about 13 KB in the compact model, so plan B, which uses fixed-width records, carries real workloads.
  3. Binary-mode I/O and CRLF/`^Z` policy.
  4. `\ No newline at end of file`, which 2.2 does not handle.
  5. DOS temp files and safe installation.
  6. A narrow local formatter (decision 7).
- **`libc16` additions:** `rename`, `unlink`/`remove`, `fseek`/`ftell` (decision 8). Everything else is `patch16`-local.

## 2. Build experiment

The test copied the 2.2 files to a scratch directory (not this repository) and compiled each with:

```sh
wcc -q -zl -zld -x -m{s,c} -0 -os -s -bt=dos -w1 -DHAVE_CONFIG_H -I. -Istub -I$LIBC16/include FILE.c
```

`config.h` defines `STDC_HEADERS`, `HAVE_STRING_H`, `HAVE_FCNTL_H`, `HAVE_LIMITS_H`, `HAVE_MKDIR`, `HAVE_MEMCMP`, `HAVE_VPRINTF` and `RETSIGTYPE void`. It also supplies values `libc16` lacks or the Makefile normally passes: `ED_PROGRAM`, `L_tmpnam`, `ENOTDIR`, and `<stddef.h>` for `memchr.c`. `patchlevel.h` (normally generated) is `#define PATCH_VERSION "2.2"`.

| | small | compact |
|---|---:|---:|
| files compiled | 12 of 12 (`rename.c` not needed) | 13 of 13 |
| `_TEXT` | 0x6EC4 (28,356) | 0x8B4B (35,659) |
| `CONST`+`CONST2`+`_DATA` | 7,807 | 8,055 |
| `_BSS` | 2,161 | 2,369 |

The figures exclude library members. `-mc` costs about 26% more code.

Link with `option nodefaultlibs` and `LIBC16{,C}.LIB`. Undefined symbols come in two kinds:

- **Header problems, not gaps:**
  - `open`, `read`, `write`, `close`, `lseek`, `chmod`, `getenv`, `mkdir` are called without `libc16`'s `<io.h>`/`<direct.h>`/`<stdlib.h>` prototypes, so they get Watcom's register-convention names (`open_`).
  - `getopt.c` declares its own `strlen`, `strcmp` and `strncmp` unless `__GNU_LIBRARY__`.
  - Fix: include the right headers from `config.h`.
- **Real gaps:**
  - `atol`, `chdir`, `creat`, `fseek`, `ftell`, `fstat`, `getpid`, `getuid`, `isatty`, `kill`, `link`, `popen`, `pclose`, `setbuf`, `signal`, `system`, `tmpnam`, `unlink`;
  - the formatted family: `printf`, `fprintf`, `sprintf`, `vfprintf`, `perror`.

## 3. Unix dependency inventory (2.2)

| API | Where | Used for | Disposition |
|---|---|---|---|
| `fprintf` 44, `sprintf` 15, `printf` 12, `vfprintf` (`say`, `fatal`, `pfatal`, `ask`), `perror` 1 | all | messages, reject headers, `--help`, file names | §6 |
| `fseek`/`ftell` | `pch.c` | random access in the patch file | **`libc16`** (decision 8) |
| `unlink` | `util.c`, `patch.c` | temp files, backups | **`libc16`** |
| `rename` (`rename.c` fallback uses `link`) | `util.c` `move_file` | install output, make backups | **`libc16` `rename`**. DOS 56h fails when the target exists, so `move_file` must unlink first, which opens a window (§5). |
| `tmpnam` + `TMPDIR` | `patch.c` `make_temp` | four temp names | `compat/`: INT 21h/5Ah in the target's directory (DOS 3.0) |
| `creat` | `inp.c`, `util.c` | plan B temp file, file creation | `open(O_CREAT\|O_TRUNC\|O_WRONLY\|O_BINARY)` |
| `fstat` | `pch.c`, `inp.c` | size and type of the patch and input | `compat/`: `filelength` plus a "regular file" check (IOCTL 4400h for devices) |
| `getuid` | `inp.c` | RCS/SCCS lock ownership | drop with RCS/SCCS (decision 5) |
| `system` | `inp.c`, `util.c` | RCS `co`/SCCS `get`; `makedirs` | drop RCS/SCCS; `makedirs` → `mkdir` loop |
| `popen`/`pclose` | `pch.c` | `-e` ed scripts | drop `-e` (decision 5) |
| `signal`/`sigaction`, `kill`/`getpid` | `util.c` | clean up temp files on a signal, then re-raise | `compat/`: Ctrl-Break (INT 23h) → clean up and exit 2 |
| `isatty` | `util.c` `ask` | find a terminal | `compat/`: IOCTL 4400h, falling back to `CON` |
| `chdir` | `patch.c` `-d` | working directory | defer `-d` (decision 5) |
| `setbuf` | `patch.c` | `stderr` buffer | drop (output is unbuffered) |
| `atol` | `pch.c` | hunk numbers | checked accumulation (overflow → malformed) |
| `memchr` | `pch.c`, `inp.c` | | 2.2's `memchr.c` (GPL; `patch16` only) |
| `fopen(..., "r"/"w")` | 6 sites | patch, input, output, reject | **binary modes** (§5.1) |

## 4. Memory hazards in 2.2 on a 16-bit host

`size_t` is 16 bits, `LINENUM` is `long`, and pointers are 4 bytes in the compact model.

### 4.1 Hunk arrays: overflow from a hunk header (must fix)

```c
static size_t hunkmax = INITHUNKMAX;                         /* pch.c:51 */
hunkmax *= 2;                                                /* grow_hunkmax */
realloc (p_line, hunkmax * sizeof (*p_line));
...
p_max = p_ptrn_lines + 6;                                    /* pch.c:605, context */
p_max = p_ptrn_lines + p_repl_lines + 1;                     /* pch.c:913, unified */
while (p_max >= hunkmax) if (! grow_hunkmax ()) ...
```

`p_ptrn_lines` and `p_repl_lines` come from the hunk header, before any lines are read. In the compact model, growth from 16,000 entries computes `32000 * 4` = 128,000. That wraps to 62,464, so `realloc` **shrinks** `p_line` and the parser then writes past it. `hunkmax` itself wraps at the next doubling (64,000 → 62,464 → …), and since `p_max` is a `long`, the `while` can keep calling `realloc` with nonsense sizes. One header line such as `@@ -1,20000 +1,20000 @@` can corrupt the heap.

**Fix:** reject a hunk whose claimed sizes exceed an explicit cap (for example 4,000 lines per side) before allocating. Make `grow_hunkmax` refuse any growth whose byte count would exceed 65,530. Add tests at the 16-bit boundaries.

### 4.2 Plan B: wrap and hang on long lines (must fix)

```c
for (tibufsize = TIBUFSIZE_MINIMUM; tibufsize < maxlen; tibufsize <<= 1)  /* inp.c:409 */
  continue;
tibuf[0] = xmalloc (2 * tibufsize);
```

2.2 removed the line-length limit, so `maxlen` is unbounded:

| Longest line | Effect |
|---|---|
| over 32,768 bytes | `tibufsize` goes 32,768 → 0, and `0 < maxlen` forever: **a hang** |
| over 16,384 bytes | `tibufsize` = 32,768 and `2 * tibufsize` = 0: `xmalloc(0)` followed by 32 KB writes, **a heap overrun** |

Plan B also keeps fixed-width records: every line is padded to `maxlen` in blocks of at least 8 KB. One 8,000-character line in a 10,000-line file therefore makes an **80 MB** temp file.

### 4.3 Plan A: safe but small

Eggert's checks (`size + 2 < 2`, `allocated_bytes / per_byte != size + 2`) make plan A refuse rather than overflow. Plan A allocates `(size + 2) * (sizeof (char *) + 1)` bytes as **one** object: 5 bytes per input byte in compact, 3 in small. So it handles at most about **13 KB** files in compact (`libc16`'s per-object limit is 65,530) or about 21 KB in small. Anything larger falls through to plan B, so plan B is the common path, not the exception.

### 4.4 Recommendation

Replace plan A and plan B with one bounded, file-backed **line-offset index**:

- 32-bit offsets of each line in the original, stored in fixed blocks in a small temp file with one or two blocks cached;
- lines read by seeking into the original, into a bounded buffer;
- an explicit maximum line length that fails before any output is replaced.

That is 4 bytes of disk per line, constant RAM, no `maxlen` padding, and `ifetch()`'s interface unchanged for `patch.c`. It can be written as a rework of 2.2's `inp.c` (GPL; DESIGN.md §3.4 allows adapting it). Cap hunk sizes as in §4.1. On-disk hunk staging can stay a later improvement.

## 5. DOS-specific work

| Need | Where | Notes |
|---|---|---|
| `rename`, `unlink`/`remove` | **`libc16`** | clean-room MIT with tests (decision 8); INT 21h/56h and 41h; `tico16` is a second consumer |
| `fseek`/`ftell` | **`libc16`** | must discard the input buffer and the `ungetc` hold. Test binary and text streams, `ungetc` before `ftell`, and seeks back to `ftell` values (decision 8). |
| temp files | `compat/` | 5Ah (create unique) in the **target's directory**, so the install is a same-drive rename. Never `TMPDIR` across drives. |
| buffered output | `compat/` | 2.2 writes whole lines with `fwrite`, so this is less critical than in 1988 code. A 512-byte buffer still cuts INT 21h calls for short lines. |
| safe install (`move_file`) | `compat/` | DOS 56h cannot rename over an existing file. The sequence: (1) rename the original to a collision-checked backup or hidden temp name; (2) rename the new file into place; (3) on failure, rename the original back; (4) delete the backup unless `-b`. Leave recovery instructions if the rollback fails (DESIGN.md §7). |
| backup/reject names | adapt `addext.c` | `.ORG` / `.REJ` **replace** the extension (`FOO.C` → `FOO.ORG`). If the name already ends in `.ORG` or `.REJ`, or the result exists, use 5Bh (create new) to pick `FOO.OR1`… or fail. Never overwrite silently (decision 6). |
| Ctrl-Break | `compat/` | clean up temp files, exit 2 |

### 5.1 Binary mode, CRLF and `^Z`

`libc16` text mode translates `\r\n` and **stops at `^Z`**. That also makes plan A's `read(...) != size` check fail on any CRLF file. All of `patch16`'s files must be opened binary:

- `fopen` with `"rb"`/`"wb"`;
- `open` with `O_BINARY`;
- `setmode(0, O_BINARY)` for a patch on standard input.

Then:

- **patch lines:** strip one trailing `\r` before parsing, so a Linux patch and a converted DOS patch read the same;
- **matching:** compare original lines without their terminator;
- **output:** write each original line's terminator back unchanged; give added lines the terminator style the target mostly uses (exact rule and tests in E4);
- **`^Z`:** an ordinary byte. No implicit EOF (DESIGN.md §7).

### 5.2 `\ No newline at end of file`

2.2 does not handle this marker; its 2.1 README listed it on the wish list. It has to be added in `pch.c`: mark the preceding line as lacking a newline on the relevant side and never add one. Later GNU releases still under GPLv2-or-later (2.5.x) handle it and may be adapted, with a PROVENANCE.md entry.

### 5.3 Git textual patches

2.2 predates Git. Its `intuit_diff_type` skips unrecognised lines, so `diff --git`, `index …`, `new file mode`, `deleted file mode` and `similarity index` are mostly ignored as leading garbage. Explicit handling is still needed:

- recognise the preamble;
- reject binary patches (`GIT binary patch`, `Binary files … differ`) and mode-only, rename and copy changes with a clear message (DESIGN.md §6);
- take `a/`/`b/` names with `-p1`.

## 6. Formatted output (decision 7)

The message functions `say`, `fatal`, `pfatal` and `ask` already go through one `vfprintf` path in `util.c`. Their 139 call sites plus `printf`/`fprintf`/`sprintf` use only `%s` ×104, `%ld` ×46, `%d` ×10, `%c` ×10, `%o` ×1 and `%3ld` ×1.

**Plan:** a `patch16`-local formatter in `compat/` that implements exactly `%s`, `%c`, `%d`, `%ld`, `%o`, a numeric width for `%ld`, and `%%`. It writes through the output buffer and aborts with an internal-error message on any other conversion. `say`, `fatal`, `pfatal` and `ask` call it directly. The remaining `fprintf`/`printf` sites (reject-file headers, `--help`) call it through a `fmt_out(FILE *, ...)` wrapper. `sprintf` sites that build file names become `strcpy`/`strcat`. Nothing goes into `libc16`.

## 7. Interface (decisions from PR #1)

| # | Topic | 2.2 | Change for `patch16` |
|---|---|---|---|
| 1 | `-n` | `--normal` | none; `--dry-run` already exists |
| 2 | exit status | 0 / 1 / 2 | none; add tests and a compatibility note (Wall's pl12 returned a failure count) |
| 3 | fuzz | `maxfuzz = 2` | default 0; `-F` opts in |
| 4 | no `-p` | `-p` "infinity" (basename) | none; document `-p1` for Git |
| 5 | `-e`, RCS/SCCS, `-d` | supported | drop `-e` and RCS/SCCS; defer `-d` |
| 5 | `-D` | supported | keep |
| 6 | backup/reject | `.orig`/`~`, `.rej`/`#` via `addext` | `.ORG`/`.REJ` replacing the extension; collision rules in §5 |

## 8. Next steps (E2)

1. `libc16`: `rename`, `unlink`/`remove`, `fseek`/`ftell`, as clean-room MIT members with specs and tests (separate PR in `gr-dos/libc16`).
2. `patch16`:
   - import the 2.2 files listed in PROVENANCE.md **unmodified** as the first commit;
   - then add the DOS `config.h`, `compat/` and a Makefile on the sibling pattern (`scripts/fetch-libc16`, `build/tools.env`, compact model);
   - get a first linked `PATCH16.EXE`.
3. Fixes in order: binary I/O (§5.1), hunk caps (§4.1), line index replacing plan A/B (§4.4), safe install and names (§5), fuzz default, formatter (§6).
4. Tests: host-side `diff -u` round trips and malformed input at 16-bit boundaries, run under DOSBox-X (DESIGN.md §9).

## Appendix A: Wall's 1988 code (historical, superseded)

The first exploration targeted Wall's patch 2.0 pl12 from X11R3 (LICENSE-RESEARCH.md §1). The findings, for the record:

- Four of its five files compiled unmodified with `-ms`/`-mc`. `util.c` failed on its K&R message functions and on `signal`. Partial `_TEXT` was 18.4 KB small and 22.9 KB compact.
- **Plan A overrun:** `malloc((MEM)(i_size+2))` with a 16-bit `MEM` wrapped for files of 65,534–65,535 bytes (mod 65,536), followed by `read` of nearly 64 KB.
- **Line-pointer overrun:** the array overran at 32,766 lines (small) or 16,382 (compact).
- **Hunk growth:** `int hunkmax` growth wrapped as in §4.1.
- **Plan B:** padded every line to the longest one, in 1 KB blocks.
- **Output:** went byte at a time through `putc`.
- **Interface:** `-n` meant "normal diff", the exit status was the failed-hunk count, and the default fuzz was 2.

2.2 fixes the plan A arithmetic, the per-byte output and the exit status, which is part of why it is the better baseline.
