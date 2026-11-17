# PATCH: the manual

`PATCH.EXE` applies a diff to the files it describes. It is GNU `patch` 2.2, by Larry Wall and the Free Software Foundation, ported to 16-bit MS-DOS by the patch16 project. It runs on an 8088 or 8086 or later, under MS-DOS 3.0 or later, GR-DOS, or a compatible DOS. It needs about 90 KB of free memory for most patches, and no extended or expanded memory.

Its common use is a patch made on another machine with `diff -u` or `git diff`, applied on DOS to a copy of the same files.

## Running it

```dos
PATCH -p1 < UPDATE.PAT
PATCH -p1 -i UPDATE.PAT
PATCH HELLO.C UPDATE.PAT
PATCH --dry-run -p1 -i UPDATE.PAT
```

`PATCH` reads the patch from standard input, or from the file `-i` names, or from the second file named. It finds each file the patch changes from the patch's own headers, unless a file is named. Each file is patched in turn, and `PATCH` says so: `patching file hello.c`.

`PATCH --help` lists the options; `PATCH --version` prints `patch (patch16) VERSION (GNU patch 2.2)`.

## Options

| Option | Meaning |
|---|---|
| `-p NUM`, `--strip=NUM` | Strip NUM leading parts from the file names in the patch. Use `-p1` for a patch made by `git diff` or `diff -u a/... b/...`. With no `-p`, only the last part of each name is used, so `src/hello.c` patches `HELLO.C` in the current directory. |
| `-i FILE`, `--input=FILE` | Read the patch from FILE. |
| `--dry-run` | Say what would happen, and change nothing. |
| `-R`, `--reverse` | Apply the patch backwards, undoing it. |
| `-N`, `--forward` | Skip a patch that seems already applied, rather than asking. |
| `-F N`, `--fuzz=N` | Allow up to N lines of context not to match. The default is 0: every context line must match, unlike GNU `patch`'s default of 2. |
| `-l`, `--ignore-whitespace` | Match lines whose blanks differ. |
| `-c`, `-n`, `-u` | Take the patch as a context, normal or unified diff, rather than guessing. `-n` is "normal diff", as in GNU `patch` 2.2; it is not the dry run. |
| `-o FILE`, `--output=FILE` | Write the patched file to FILE, leaving the original as it is. |
| `-r FILE`, `--reject-file=FILE` | Put rejected hunks in FILE, replacing it, rather than in `FOO.REJ`. |
| `-b`, `--backup` | Keep each original as `FOO.ORG` (see below). |
| `-z EXT`, `--suffix=EXT` | Use EXT for backups; `.EXT` replaces the name's extension. |
| `-B PREFIX`, `-Y PREFIX` | Put PREFIX before backup names, or before their last part. |
| `-V simple` | The only backup style DOS can hold; `numbered` and `existing` make names such as `FOO.C.~1~`, which are not DOS names. |
| `-D NAME`, `--ifdef=NAME` | Merge the change into the file under `#ifdef NAME`, keeping the old lines under `#ifndef NAME`. |
| `-E`, `--remove-empty-files` | Remove any file left empty by the patch. A file the patch says it deletes is removed without `-E`. |
| `-t`, `--batch` | Ask no questions: skip a file with no name, and take a reversed patch as reversed. |
| `-f`, `--force` | Ask no questions, and take a reversed-looking patch as it is. |
| `-s`, `--quiet`; `--verbose` | Say less, or more. |
| `-d DIR`, `--directory=DIR` | Work in DIR. The directory, and the drive, are put back when `PATCH` ends. |

GNU `patch` 2.2's `-e` (ed scripts) and its RCS and SCCS checkout are not in `PATCH`. An ed script is an error.

## Exit status

| Status | Meaning |
|---|---|
| 0 | Every hunk of every file applied. |
| 1 | Some hunk was rejected, or some file was not changed (see below). The rest of the patch was applied. |
| 2 | An error: a bad option, a malformed or truncated patch, a file that could not be read or written, out of memory, a full disk, or Ctrl-Break. The file being patched when it happened is not changed; files earlier in the patch stay patched. |

A batch file can test it with `IF ERRORLEVEL 2` and then `IF ERRORLEVEL 1`.

## What it accepts

- **Formats:** unified diffs (`diff -u`, `git diff`, `git format-patch`), context diffs (`diff -c`) and normal diffs (`diff`). Mail headers, a diffstat and a signature around a patch are skipped, as is other text before or between the files.
- **New and deleted files:** a file whose old name is `/dev/null`, or dated at 1970-01-01 as `diff -N` dates a missing file, or that Git marks `new file mode`, is created, with its directories. One the patch deletes is removed, if every hunk applied; with `-b` it is kept as the backup.
- **Git:** text changes, new files and deleted files apply. A binary change, a rename, a copy or a mode change is reported, as `b/x.sh: patch16 does not apply a mode change; not changed`, and the exit status is 1. A mode change with a text change has its text applied.
- **`\ No newline at end of file`** is honoured: a last line without a newline stays without one, and one is added or removed only when the patch says so.

## Line ends

`PATCH` reads a patch with LF or CR LF line ends, or a mix, so a patch from Linux needs no conversion. A file's CR LF lines match the patch's lines either way. Lines that the patch does not change keep their own line ends. Added lines take the line end most of the file's lines have, and a new file takes the patch's. `^Z` is an ordinary byte, not the end of a file. Bytes other than the diff's own syntax are not interpreted: code page 437 text is patched as it is.

## File names

`PATCH` patches only files in the current directory or below it. It refuses a name from a patch that:

- starts at the root (`/AUTOEXEC.BAT`), names a drive (`C:CONFIG.SYS`), or goes up with `..`;
- is not an 8.3 name in every part (`config.h.in`, `verylongname.c`). `PATCH` never shortens a name;
- is a DOS device (`CON`, `PRN`, `AUX`, `NUL`, `CLOCK$`, `COM1`–`COM9`, `LPT1`–`LPT9`), with or without an extension.

Such a file is reported as `NAME: patch16 does not patch ...; not changed`, and the exit status is 1. A name that `PATCH` is given, by `-o`, `-r`, `-d`, as an argument, or at its `File to patch:` question, is used as it is. `\` and `/` are both separators.

## Rejects and backups

- A hunk that does not apply is written to `FOO.REJ`, as a context diff that `PATCH FOO.C FOO.REJ` can apply once corrected. If `FOO.REJ` exists, the next free name is used (`FOO.RE1`, `FOO.RE2`, …); a file is never replaced.
- When a hunk fails, the original is kept as `FOO.ORG`, or the next free name, even without `-b`. With `-b` it is always kept.
- A read-only file is not patched; its hunks go to `FOO.REJ`.

## Safety

- The patched file is written to a temporary file in the current directory first. The original is replaced only when that is complete: it is renamed aside, the new file renamed in, and the original then removed (or kept as the backup). If any of that fails, the original is put back. A file on another drive is copied, and a copy that fails is removed.
- A full disk, a write error, Ctrl-Break or a critical error (a drive not ready) stops `PATCH` with the file it was patching unchanged and its temporary files removed. Ctrl-Break is ignored only while a file is being replaced.
- DOS has no atomic rename over a file. If the machine stops while a file is being replaced, the original may be left as `PATCH16$.$$$` in the file's directory (or as its backup, `FOO.ORG`), and the new version under a temporary name DOS made in the current directory.

## Limits

| Limit | Value |
|---|---|
| Lines in one hunk | 15,992 |
| Bytes in one line of the patch | 16,383 |
| Bytes in one line of a file | 32,000 |
| Size of a file | no limit of `PATCH`'s; 4 bytes of temporary disk per line |
| Memory | about 81–88 KB for most patches, about 354 KB for the largest hunk |

A patch past a limit is an error (status 2), and the file is not changed. A NUL byte in a line of a hunk is refused the same way; a file being patched may contain NULs.

## CONFIG.SYS

`PATCH` keeps the patch, the file, the output and, for a file of more than 1,024 lines, a line index open together, and the reject file too while there are rejects. DOS's default of `FILES=8` is shared with the console, `AUX`, `PRN` and any redirection, so `PATCH` can fail with `Too many open files` (status 2, nothing changed). Set `FILES=20` in `CONFIG.SYS`, as GR-DOS's installs do.

## Licenses

`PATCH` is free software under the GNU General Public License, version 2 or any later version (`COPYING`), with no warranty. It is linked with libc16, under the MIT license. Each release carries the source of both; `NOTICE` lists the authors.
