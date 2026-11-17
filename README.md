# patch16

GNU `patch` 2.2 for 16-bit MS-DOS: `PATCH.EXE`, for an 8088 or later with DOS 3.0 or later, and GR-DOS. It applies unified, context and normal diffs, as `diff -u` and `git diff` make them on another machine, to files on DOS.

```dos
PATCH -p1 -i UPDATE.PAT
```

- **Manual:** [`docs/DOS.md`](docs/DOS.md): options, exit status, line ends, file names, rejects and backups, limits.
- **Download:** `patch.exe` from the [latest release](https://github.com/gr-dos/patch16/releases/latest), with its source and the source of libc16, which it is linked with.
- **Building:** [`BUILDING.md`](BUILDING.md).
- **GR-DOS:** [`docs/GR-DOS.md`](docs/GR-DOS.md): how GR-DOS packages it.

## How it differs from GNU patch 2.2

- DOS file names: backups are `FOO.ORG` and rejects `FOO.REJ`, never replacing a file; names from a patch must be 8.3 and stay in the current directory.
- Fuzz is off by default (`-F` turns it on); `-e` and RCS/SCCS are gone.
- CR LF and LF are both accepted, and each file keeps its own line ends.
- A file the patch deletes is removed; Git's binary, rename, copy and mode changes are reported, not made.
- When a hunk fails, the original is kept as `FOO.ORG`.
- Memory is bounded: a file of any size is patched in about 90 KB.

[`docs/PORT-FEASIBILITY.md`](docs/PORT-FEASIBILITY.md) has the details, and [`docs/PROVENANCE.md`](docs/PROVENANCE.md) what was changed.

## License

GPL version 2 or any later version ([`COPYING`](COPYING)), as GNU patch 2.2 is; authors and notices are in [`NOTICE`](NOTICE). libc16, linked into `patch.exe`, is MIT. [`docs/LICENSE-RESEARCH.md`](docs/LICENSE-RESEARCH.md) records how the license was established.
