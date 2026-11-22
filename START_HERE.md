# arc-shrinkler: start here

An Acorn Archimedes port of the Shrinkler decompressor in 26-bit ARM assembler (vasm), plus a test program that decompresses sample data (STNICCC, an A252 text, the QTM module) and verifies it.

| | |
|---|---|
| GitHub | https://github.com/kieranhj/arc-shrinkler (public) |
| Upstream | port of Blueberry's Shrinkler decruncher; compressor fork at `D:\amiga\mine\Shrinkler` |
| Local path | D:\archie\mine\arc-shrinkler (moved from OneDrive\Archie\Repos\arc-shrinkler on 2026-11-22) |
| Branch | main; other branches: wip/2026-11-tidy |
| Last commit | 2023-01-13: Add assemble option to remove progress callback. |

## What's in here

- `src/arc-shrinkler.asm`: the decompressor (`ShrinklerDecompress`, `ShrinklerParseHeader`); `src/main.asm`: the test program.
- `data/`: test inputs; `bin/`: vasm, `shrinkler.exe` (the endian-swap fork), `rose2arc.py`.
- `Makefile` (vasm build + deploy), `make.bat` (assemble only + copy to `..\arculator\hostfs`), `README.md` (options and usage).

## Build and run

- `make`: default target `shrinkler` = `build/shrinkler.bin` copied to `../../Arculator_V2.1_Windows/hostfs/shrinkler,ff8` (the `D:\archie\Arculator_V2.1_Windows` junction into `D:\tools`). On 2026-11-22 it said "Nothing to be done" (all up to date).
- Caveat: the recipes use `mkdir -p`, `rm -Rf` and `cp`, which do not exist under cmd.exe, so a real rebuild through `make` fails (and `mkdir -p` would make a stray `-p` folder). Until that is fixed use `cmd /c .\make.bat`, which assembles `src\main.asm` and copies to `..\arculator\hostfs\shrinkler,ff8` instead.
- Assemble options (`_DEBUG`, `_PARITY_MASK`, `_ENDIAN_SWAP`, `_PARSE_HEADER`) are `.equ`s at the top of `src/main.asm`; see `README.md`.
- Run `shrinkler` from HostFS in Arculator.

## Local changes

- Uncommitted: `src/main.asm` sets `_DEBUG` to 0.
- Untracked at the root: `dither.bin/.shri`, `dither2.bin/.shri` (test data).
- `wip/2026-11-tidy` (pushed): snapshot of all of the above.

## Status and next steps

- Working and documented; last added a data verification test and a no-callback option. See README "Future Work". Open: 4-byte parity notes (2022-10-15) vs the Shrinkler fork's wip/parity-4-bytes branch.

## See also

- `README.md`; `D:\amiga\mine\Shrinkler`; users: archie-verse, aklang, archieklang (`bin\Shrinkler.exe`).
