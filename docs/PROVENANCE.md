# patch16: provenance

Origins of each source module (DESIGN.md §3.4). Nothing from upstream is in the repository yet; this records the upstream inventory and the planned disposition of each file. Notices and licensing: `docs/LICENSE-RESEARCH.md`.

## Upstream snapshot

Larry Wall's patch 2.0, patchlevel 12, from `X.V11R3/util/patch` in the X11R3 distribution (SHA-256 `1800eaa9…f1b9c1`). Fetch it with `scripts/fetch-upstream`; per-file SHA-256s are in `upstream/MANIFEST.sha256`.

| File | Lines | Author | Planned disposition |
|---|---:|---|---|
| `patch.c` | 824 | Wall; contributions noted in LICENSE-RESEARCH.md §3.2 | adapt (main loop, hunk location, application, `-D` output) |
| `pch.c` | 1123 | Wall | adapt (context and normal parsers; header intuition); unified parser added as a separate module |
| `inp.c` | 319 | Wall | replace plan A/plan B storage with a bounded, file-backed line index (PORT-FEASIBILITY.md §4) |
| `util.c` | 364 | Wall | adapt; `move_file`, `ask`, signals, `makedirs` and message output move to `compat/` |
| `version.c` | 28 | Wall | adapt |
| `common.h` | 158 | Wall | adapt (remove K&R libc redeclarations, Unix temp names) |
| `EXTERN.h`, `INTERN.h`, `inp.h`, `pch.h`, `util.h`, `version.h`, `patchlevel.h` | small | Wall | keep |
| `config.H`, `config.h.SH`, `Configure`, `Makefile.SH` | | Wall | not used; replaced by a fixed DOS `config.h` and a Makefile |
| `patch.man` | | Wall | basis for `docs/DOS.md` after the license gate |
| `README`, `MANIFEST` | | Wall | historical; the README notice goes to `docs/HISTORY-LICENSE.md` |
| `malloc.c` | 467 | Caltech / U of M / BRL; not Wall | **excluded** (unknown terms; not built upstream either) |
| `CHANGES`, `Makefile`, `filexp`, `myread` | | X Consortium / generated | not used |

## Reference-only material consulted

- GNU `patch` git (`git.savannah.gnu.org/git/patch.git`), tags `v2.1` through `v2.6`: README, NEWS, COPYING, ChangeLog and file-header notices only, for the license chain. No code read for implementation.
- `libc16` (`../libc16`, release 0.04): headers and `docs/` specs, to compile the API gap list.
