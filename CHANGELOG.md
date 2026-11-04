# Changelog

All notable changes to this project will be documented in this file.

## [1.5.0] - 2026-11-04

### Changed
- Much faster 5×5 puzzles: on an odd grid the number path can only start on
  a corner-coloured square, and the generator used to try the other squares
  too, each time searching until it gave up. 5×5 went from up to 70 ms on a
  desktop (about 2 s on a Kobo) to a few milliseconds; the puzzles are the
  same.
- The uniqueness check skips cells too far from the next given number, and
  no longer scans the whole grid to find each given number: 6×6 Hard is
  about a third faster.
- New game and opening the game each build one puzzle instead of two (the
  board generated one on creation that the screen then replaced), so
  today's Daily Challenge grid is a different one than with 1.4.3.
- A "Generating puzzle…" progress bar appears if generation takes more than
  a fraction of a second.

## [1.4.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.4.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

## [1.3.0] - 2026-10-30

### Added
- "New game" once the puzzle is solved: the action bar shows it in place of
  Erase, Check and Hint, so the next puzzle no longer needs the menu.
- The rules now explain how to enter a number: two digits on the keypad, 0
  then 7 for 7.

### Changed
- Redesigned play screen, in line with the other games: a full-width action
  bar, the unified number pad (two even rows of five), a larger board that
  fills the available room, and one thick frame around it. The status line
  reads "size · difficulty · Empty: n" and wraps in landscape instead of
  being cut off.
- Title-bar menu shows "Difficulty: …" in full (was "Diff: …").
- New README screenshot.

### Fixed
- Using Hint wiped the saved game: the board was saved as nothing. And when
  a hint fills the last cell, the status now shows the win message.
- The board's closing grid line was drawn just past its edge.

## [1.2.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.
- `i18n_fr.lua` shipped to the device but was never loaded: nothing called
  `i18n.extend()` on it, so the whole table was dead weight. main.lua now
  merges it in before the menu entry is built.


## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button. Two taps, not one: the first says which cell is about to
  give, the second acts on it -- a player who is told where to look usually
  finds the rest themselves, and only pays for the full reveal if they want
  it. A cell that contradicts the solution is always reported before a fresh
  one is revealed, and on a mistake the hint empties the cell rather than
  solving it.

## [1.1.8] - 2026-07-29

### Fixed
- Generated puzzles had no uniqueness verification — clues were
  revealed as a random fraction of the solved path with no check that
  the remaining givens still pinned down a single orthogonally-
  connected 1..n*n path, so some puzzles admitted more than one valid
  solution even though only one was recognized as correct. Generation
  now digs clues one at a time and keeps a cell hidden only after
  proving with a bounded backtracking search that exactly one solution
  remains, guaranteeing every puzzle has a unique solution.
