# patch16 in GR-DOS

GR-DOS ships the DOS programs of the `gr-dos` repositories whose names end in `16` in its full distribution: `C:\DOS` on a CF or hard disk install, and `BIN` in its release ZIP. Its `scripts/dist16` finds them, checks each release against a contract, and pins what it takes in `dist16/lock`. The contract is in GR-DOS's `docs/dist16.md`. This is how patch16 meets it, and what is still missing.

## The release contract

| GR-DOS requires | patch16 |
|---|---|
| a program asset `STEM.exe`, STEM the repository name with or without `16` | `patch.exe`, and no `patch16.exe` beside it (DESIGN.md §15) |
| an 8.3 name that is none of GR-DOS's own | `PATCH`: GR-DOS has no `PATCH` |
| a real-mode MZ executable, no extender | built with `wcc -0 -mc`, `format dos`; `scripts/release-files` checks the MZ header |
| GitHub's size and digest | GitHub gives them for every asset |
| a license GitHub finds at the release's commit | `COPYING`, the GPL version 2, at the root |
| for a GPL program, `dist16.source` at that commit | [`dist16.source`](../dist16.source): `GPL-2.0-or-later`, the source asset, `BUILDING.md`, `NOTICE`, and libc16 |
| a source asset of the release, holding `dist16.source`, the license file and the `build` file under one top directory | `patch16-VERSION-src.tar.gz`, `git archive` of the release commit; `scripts/release-files` checks those files are in it, and `scripts/check-source` that it builds the same `patch.exe` |
| for each linked library, a release with its own source asset | **missing**: see below |
| no Open Watcom C runtime | `scripts/check-link` on every build, and `scripts/release-files` checks for its banner |

### What is missing: libc16's source asset

`dist16.source` says that `patch.exe` is linked with libc16 0.05, whose source is `libc16-0.05-src.tar.gz` in libc16's own release v0.05. That release has only `libc16-0.05.zip`, which holds the headers and the library, not the C source. Until a libc16 release has a source asset, dist16 leaves patch16 out, with the reason.

patch16's own release already carries `libc16-0.05-src.tar.gz`, made by `git archive` of libc16's tag, so the GPL's requirement is met for anyone who gets `patch.exe` from patch16's release. dist16 asks for more: the library's source in the library's release. Either of these would provide it:

- a new libc16 release that attaches its source, followed by a patch16 release that pins it (`scripts/fetch-libc16`, and the `depends` line);
- attaching `libc16-0.05-src.tar.gz` to libc16's existing v0.05 release.

Then GR-DOS's `make dist16-resolve` takes patch16 into its lock, in its own reviewed change.

## Installing it

`C:\DOS` gets `PATCH.EXE`; `C:\DOS\SOURCES.TXT` and the ZIP's `SOURCE\PATCH16\` get the source archives and the license texts. `PATCH` is not on GR-DOS's boot floppies.

`PATCH` needs `FILES=20` or so in `CONFIG.SYS`, which GR-DOS's installs set; DOS's default of 8 can run out (`docs/DOS.md`). It needs about 90 KB of free memory, more for very large hunks.

## Testing on GR-DOS

`make test-grdos` boots GR-DOS 0.04's 1.44 MB floppy in QEMU, with `FILES=20`, and applies the round-trip corpus from a second floppy (`tests/grdos.sh`, `tests/corpus.sh`). CI runs it on every pull request and before every release.
