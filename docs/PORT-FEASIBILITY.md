# patch16: port feasibility (E1)

**Status:** E1 exploration done 2026-10-28; local and unpublished (the license gate is open, LICENSE-RESEARCH.md §5)
**Inputs:** Wall's patch 2.0 pl12 (`scripts/fetch-upstream`); `libc16` 0.04 built from `../libc16`; the Open Watcom snapshot `libc16` pins (`watcom-2026-10-01-Build`)

## 1. Summary

- **Viable.** Wall's code is about 2,650 lines of K&R C in five files. Four of the five compile **unmodified** with `wcc -0 -ms` and `-mc` against `libc16`'s headers. The fifth, `util.c`, fails only on its pre-varargs message functions and on `signal`.
- Code is small: 18.4 KB of `_TEXT` for the four files in the small model (22.9 KB compact), before `util.c` and library members. A complete `.EXE` well under 64 KB of code is realistic, so the small or compact model is viable. No large-model need appeared.
- **The real porting work is in four places, not the matcher:**
  1. 16-bit size arithmetic in `inp.c`'s in-memory "plan A" and `pch.c`'s hunk arrays. Both can overrun the heap, the latter from a single malformed hunk header (§4).
  2. `inp.c`'s on-disk "plan B" uses fixed-width records.
  3. Byte-at-a-time output on `libc16`'s unbuffered streams.
  4. The `printf` family (139 call sites).
- **`libc16` gaps** are small and mostly DOS-generic: `rename`, `unlink`/`remove`, and `fseek`/`ftell`, which suit `libc16`. Unique temp files, an output buffer and message output suit `patch16`'s `compat/` instead (§5).
- **Interface conflicts with DESIGN.md §5** need a decision before E2 (§7): Wall's `-n` is "normal diff", not dry run; his exit status is a failure count; fuzz defaults to 2.

## 2. Build experiment

The test copied Wall's `.c` and `.h` files unmodified into a scratch directory (not this repository) and compiled them as below. `malloc.c` was left out (LICENSE-RESEARCH.md §3.1). The fixed `config.h` was hand-written: `index`→`strchr`, `rindex`→`strrchr`, and the `Reg*` register macros. `<assert.h>` and `<signal.h>`, which `libc16` lacks, were empty stubs.

```sh
wcc -q -zl -zld -x -m{s,c} -0 -os -s -bt=dos -w3 -Istub -I$LIBC16/include FILE.c
```

| File | `-ms` | `-mc` | Notes |
|---|---|---|---|
| `patch.c` | compiles | compiles | K&R warnings only (W308/W131) |
| `pch.c` | compiles | compiles | same |
| `inp.c` | compiles | compiles | same |
| `version.c` | compiles | compiles | |
| `util.c` | 47 errors | 47 errors | 39 × E1071: `say`/`fatal`/`ask` are defined with `long` parameters (the non-`CANVARARG` path) but called with `char *`. 8 × undeclared `SIGHUP`/`SIGINT`/`SIG_IGN`. |

Linking the four objects with `option nodefaultlibs` and `LIBC16{,C}.LIB`:

| | small | compact |
|---|---:|---:|
| `_TEXT` | 0x490A (18,698) | 0x5ADB (23,259) |
| `CONST`+`CONST2`+`_DATA` | 0xDDF (3,551) | 0xE01 (3,585) |
| `_BSS` | 0xC06 (3,078) | 0xCB0 (3,248) |

These are partial figures, without `util.c` and without the library members that would resolve. Static data is dominated by `buf[MAXLINELEN]` (1 KB), `serrbuf[BUFSIZ]` and the fixed name buffers.

**Every external came back unresolved**, including functions `libc16` has (`strcpy_`, `malloc_`, `open_`, `read_`). Wall never includes `<string.h>`, `<stdlib.h>`, `<io.h>` or `<fcntl.h>`. `common.h` also redeclares `malloc`, `strcpy`, `lseek` and others K&R-style, so the calls get Watcom's register convention (`name_`) instead of `libc16`'s `__cdecl` (`_name`). The port therefore has to include the right headers and delete `common.h`'s libc redeclarations. That is a mechanical change, but a mandatory one; without it, prototypes-off mismatches would also hide argument-size bugs (`int` vs `long`).

## 3. Unix dependency inventory

Counts are call sites in `patch.c`, `pch.c`, `inp.c`, `util.c` and `version.c`.

| API | Sites | Used for | `libc16` 0.04 | Disposition |
|---|---:|---|---|---|
| `fprintf`, `sprintf`, `printf` (via `say`/`ask`/`fatal` too) | 13 + 14 + 1, plus 111 | messages, reject-file headers, file names, command strings | **no** (by design) | §6 |
| `fopen`/`fgets`/`fputs`/`putc`/`fclose`/`fflush` | many | patch file, plan B input, output, reject file | yes | keep; use binary mode (§5) |
| `ftell` / `fseek` | 7 / 5 | random access to the patch file (`pch.c`: hunk backtracking, `skip_to`) | **no** | add to `libc16` (§5) |
| `setbuf` | 1 | `stderr` buffering | no | drop (output is unbuffered) |
| `open`/`read`/`write`/`lseek`/`close`/`creat` | ~30 | plan A load, plan B temp file, `move_file`, `copy_file`, `ask` | yes, except `creat` | `creat` → `open(O_CREAT\|O_TRUNC\|O_WRONLY\|O_BINARY)` |
| `stat` / `fstat` | 16 / 1 | existence, size, mode, `S_IFDIR` | `stat` only | `fstat` → `filelength` |
| `chmod` | 4 | copy the original's mode to output | yes | map to DOS attributes; keep read-only out of the temp file |
| `unlink` | 8 | temp files, backup rotation | **no** | add to `libc16` (INT 21h/41h) |
| `link` | 2 | `move_file`: back up and install by hard link | **no**, and DOS has no links | replace with rename and copy in `compat/` (§5) |
| `mktemp` | 4 | `/tmp/patch[oirp]XXXXXX` | **no** | `compat/`: INT 21h/5Ah in the target directory (DOS 3.0) |
| `signal` | 6 | ignore `SIGHUP`/`SIGINT` while installing; clean up on interrupt | **no** | `compat/`: Ctrl-Break via INT 23h hook, or no-op for v0.01 |
| `system` | 3 | RCS `co -l`, SCCS `get -e`, `mkdir -p` (`makedirs`) | **no** | drop RCS/SCCS; `makedirs` → `mkdir` loop (`libc16` has `mkdir`) |
| `popen`/`pclose` | 2 / 1 | `-e` ed-script mode (pipes to `/bin/ed`) | **no** | drop `-e` (no `ed` on DOS) |
| `isatty` | 4 | `ask()` finds a terminal; `/dev/tty` fallback | **no** | `compat/`: IOCTL INT 21h/4400h, or always use `CON` |
| `chdir` | 1 | `-d DIR` | **no** | defer `-d` (DESIGN.md §5 already marks it "if feasible") |
| `abort` / `assert` | 1 / 12 | internal consistency | **no** | `patch16`-local `assert` macro → fatal message, exit 2 |
| `atol` / `atoi` | 9 / 3 | hunk numbers, `-p`/`-F` arguments | `atoi` only | checked digit accumulation (DESIGN.md §4) |
| `rindex`/`index` | 3 | path basename | as `strrchr`/`strchr` | `config.h` macro |
| ctype, `strlen`, `strcpy`, `strcat`, `strncmp`, `malloc`/`realloc`/`free` | many | | yes | keep |
| `/tmp/...`, `/dev/tty`, `.orig`/`~` backup names | | Unix paths | | `compat/` path rules; 8.3 names (DESIGN.md §7) |

## 4. Memory: what breaks on a 16-bit host

`typedef unsigned MEM` (16 bits) is the size `inp.c` and `pch.c` pass to `malloc`. `LINENUM` is `long`, which is fine.

### 4.1 Plan A (whole file in memory) has an overflow bug

```c
i_womp = malloc((MEM)(i_size+2));                   /* inp.c:125 */
if (read(ifd, i_womp, (int)i_size) != i_size) {...} /* inp.c:134 */
```

For a file of 65,534 or 65,535 bytes, `(MEM)(i_size+2)` wraps to 0 or 1, so `malloc` returns a tiny block (or null). `(int)i_size` is -2 or -1, which `libc16`'s `read(int, void *, unsigned)` takes as 65,534 or 65,535: **a heap overrun**. The same happens for every `i_size` congruent to 65,534 or 65,535 mod 65,536. For other sizes over 64 KB, the read count is truncated and the `!= i_size` check falls back to plan B. That fallback works, but only by luck.

The line-pointer array `(MEM)((iline + 2) * sizeof(char *))` wraps the same way once a file has 32,766 lines or more (small model), or 16,382 or more (compact). A file of 32,766 empty lines is only 32 KB, and the loop that fills the array then writes past it: **a second overrun**.

Even when correct, plan A is capped at one ≤ 64 KB object: `libc16`'s far heap allows at most 65,530 bytes per allocation (`libc16` `docs/spec/heap.md`). In the small model, file, index and hunk must all share the roughly 50 KB of `DGROUP` left after static data and stack.

### 4.2 Plan B (disk) uses fixed-width records

Plan B scans the file for its **longest** line (`maxlen`, capped by `fgets` at 1,023), then writes every line padded to `maxlen` into 1,024-byte blocks of `1024 / maxlen` lines each. One 1,000-character line in a 10,000-line source therefore makes a **10 MB** temporary file, which is fatal on a 360 KB floppy and slow on an XT disk. Lines longer than 1,023 bytes are also silently split by `fgets`.

### 4.3 Hunk storage

Each hunk line is copied with `savestr` (heap) and indexed through three arrays that start at `INITHUNKMAX` = 125 entries and double: `char *p_line[]`, `short p_len[]` and `char p_char[]`. That is 5 bytes per line (small) or 7 (compact), plus the text. In the small model a 1,000-line hunk of 40-character lines needs about 46 KB, which is nearly all the near heap.

`hunkmax` is a 16-bit `int`, and `grow_hunkmax()` is called while `p_max`, the line count **claimed by the hunk header**, is at least `hunkmax`. The header is read before any lines are, and the only bound is `MAXHUNKSIZE` = 100,000. With far pointers, growth from 16,000 to 32,000 entries computes `(MEM)32000 * 4` = 128,000, which wraps to 62,464. `realloc` then *shrinks* `p_line` and the parser writes past it. The next doubling overflows `hunkmax` itself to a negative value. In the small model the same wrap comes one step later; there, `realloc` will usually fail first for lack of near heap. **A malformed or hostile patch can corrupt memory with one header line**, such as `*** 1,20000 ****`. Hunk sizes must be validated against an explicit cap before any allocation (DESIGN.md §6, "Validate counts … overflow").

### 4.4 Recommendation

- **Replace plan A and plan B with one bounded design** (DESIGN.md §8). It would build a file-backed index of 32-bit line **offsets** in the original, kept as a small file in fixed blocks with one or two blocks cached, and seek into the original to fetch lines into a bounded buffer. That is 4 bytes of disk per line instead of `maxlen`, with constant RAM. `ifetch()`'s interface (line number → line pointer valid until the next call on that buffer) can stay, so `patch.c`'s matcher is unchanged. This must be an independently written module under DESIGN.md §3.4 rules; it replaces the Wall component rather than translating it.
- **Bound hunk size explicitly**, for example to 2,000 lines and 64 KB of text, failing before any output is replaced. On-disk hunk staging can stay a later improvement, as the design says.
- **Memory model: compact.** It costs about 24% more code than small (18.4 KB → 22.9 KB for the measured objects), but moves hunk text and buffers out of `DGROUP` onto the far heap. With the bounded line index, that leaves most of conventional memory for large hunks. Small is possible if hunks are capped tightly. Measure both again once the line-index module exists (DESIGN.md §12, question 6).

## 5. `libc16` gaps and where each belongs

| Need | Belongs in | Reason |
|---|---|---|
| `int rename(const char *, const char *)` (INT 21h/56h) | **`libc16`** | C89, DOS 2.0. A second consumer exists: `tico16/src/dos.c` has private `dos_rename`/`dos_unlink`. |
| `int unlink(const char *)` and `int remove(const char *)` (INT 21h/41h) | **`libc16`** | same |
| `long ftell(FILE *)`, `int fseek(FILE *, long, int)` | **`libc16`** | C89. Input is buffered, so these must discard or adjust the read buffer and the `ungetc` hold. Text-mode `ftell` must return a value `fseek` accepts. |
| unique temp file in a given directory (INT 21h/5Ah, DOS 3.0) | `patch16` `compat/` | DESIGN.md §4 says to investigate first. Its semantics (same directory as the target, DOS 3.0+) are `patch16`-specific. If added to `libc16` later, `tmpnam` would be the wrong shape. |
| buffered output stream | `patch16` `compat/` | `libc16` output is unbuffered by design (`docs/spec/stdio.md`). `dump_line()` and `copy_till()` call `putc` per byte, which is one INT 21h per output byte, far too slow on an 8088. A 512-byte write buffer on the output and reject files fixes it without changing `libc16`. |
| `isatty`, Ctrl-Break handling, `fstat` | `compat/` | Small, `patch16`-specific uses. `filelength` already covers `fstat`'s size. |
| `assert`, `atol` | `patch16` | `assert` → `fatal`; `atol` → checked parser (DESIGN.md §4). |

**DOS 3.0 minimum.** The only DOS 3.0 call needed is 5Ah (create unique file). 5Bh (create new file, fail if it exists) is also 3.0 and is useful for collision-checked backup names. Everything else is DOS 2.0. This confirms DESIGN.md §2's "DOS 3.0+".

### 5.1 Text mode and `^Z`

`libc16`'s default text mode translates `\r\n` → `\n` on `read`. It also **stops at `^Z`**, leaving later bytes unreadable (`docs/spec/io.md`). DESIGN.md §7 forbids silently discarding bytes, and CRLF has to be preserved on output. So `patch16` must open the patch, original, output and reject files in binary mode (`O_BINARY`, `"rb"`/`"wb"`) and handle `\r` itself:

- strip a trailing `\r` before comparing a patch line;
- remember each original line's terminator and write it back unchanged;
- give added lines the terminator style the target file predominantly uses (rule to be fixed in E4).

Wall's matcher compares lines with `strnEQ`/`similar` on `\n`-terminated text, so a normalised comparison buffer fits behind the new `ifetch()`.

## 6. Formatted output

There are 139 call sites (`say` 49, `fatal` 54, `ask` 8, `fprintf` 13, `Sprintf` 14, `printf` 1), using only five conversions: `%s` ×73, `%ld` ×42, `%d` ×11, `%c` ×5 and `%3d` ×1.

Two options:

1. **Rewrite each call** into explicit `msg_str`/`msg_long`/`msg_char` sequences. This needs no engine, which matches DESIGN.md §4 literally. It is about 140 edits touching most of Wall's diagnostic lines, which makes later diffs against upstream noisier.
2. **A `patch16`-local `say`/`fatal`/`ask` interpreter limited to exactly those five conversions** (around 60 lines, rejecting anything else at run time). Wall's call sites stay unchanged, and the K&R `say1..say4` macros become real varargs. DESIGN.md §4 says not to build "a general formatting engine". This would be a fixed, non-general one, but it is still a judgment call (§7).

`Sprintf` is mostly used to build file names (`%s%s`) and Unix command strings. The command strings disappear with RCS/SCCS/`ed`, and the file names become `strcpy`/`strcat`.

## 7. Wall's interface versus DESIGN.md §5

From `get_some_switches()`: `-b ext`, `-B prefix`, `-c`, `-d dir`, `-D sym`, `-e`, `-f`, `-F n`, `-l`, `-n`, `-N`, `-o file`, `-p[n]`, `-r file`, `-R`, `-s`, `-S`, `-v`, `-x n`.

| Topic | Wall pl12 | DESIGN.md §5 | Decision needed |
|---|---|---|---|
| `-n` | **force "normal diff"** interpretation | `-n` = dry run | Keep Wall's meaning and use another letter or `--dry-run` for dry run, or break compatibility. GNU later used `--dry-run` with no short form. |
| Exit status | `my_exit(failtotal)`: the **number** of failed hunks; `fatal` exits 1 | 0 / 1 (rejects) / 2 (fatal) | Adopt 0/1/2 as an explicit deviation, documented. |
| Fuzz | default `maxfuzz = 2` | start at zero | Default `-F0` for v0.01, with `-F` kept. |
| `-p` absent | `strippath = 957`: use the **basename** only | — | Keep Wall's default or require `-p`; Git patches need `-p1`. |
| `-e` (ed scripts) | via `popen("/bin/ed")` | not listed | Drop. |
| RCS/SCCS checkout | `system("co -l")`, `system("get -e")` | not listed | Drop. |
| `-D` (`#ifdef` output) | supported | not listed | Keep; pure text, no OS cost. |
| Backup names | `.orig`, or `~` without `FLEXFILENAMES` | not specified | 8.3: replace the extension with `.ORG`? Define in E4. |
| Reject file | `.rej`, or `#` | not specified | `.REJ` replacing the extension; collisions per DESIGN.md §7. |

## 8. Formats in the baseline

`intuit_diff_type()` recognises `CONTEXT_DIFF` (old-style `diff -c`), `NEW_CONTEXT_DIFF` (4.3BSD `diff -c`), `NORMAL_DIFF` and `ED_DIFF`. Unified diff is absent, as expected. The hunk model (`p_line`/`p_len`/`p_char` with `' '`, `'-'`, `'+'`, `'!'`, `'='`, `'*'`) can represent unified hunks. A separate unified parser that fills the same arrays, as DESIGN.md §4 intends, needs no matcher changes. Separately, `pch_swap()`, used for `-R`, works on that model too, so `-R` is likely inherited for free.

## 9. Proposed next steps (E2 preparation, after the license gate)

1. Decide the §7 interface questions and the §6 formatting option.
2. `libc16`: propose `rename`, `unlink`/`remove`, `fseek`/`ftell` as clean-room MIT additions with specs and tests.
3. `patch16`: `compat/` for temp files, buffered output, messages and `move_file` replacement; independent line-index module; fixed DOS `config.h`; Makefile on the sibling-project pattern (`scripts/fetch-libc16`, `build/tools.env`).
4. Commit Wall's files under `src/` only after LICENSE-RESEARCH.md §5 is resolved.
