# Changelog

All notable changes to this project will be documented in this file.

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
