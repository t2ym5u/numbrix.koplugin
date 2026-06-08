# Numbrix

> **Status: stub — not yet implemented**

## Description

Similar to Hidato but adjacency is orthogonal only (no diagonals). Numbers 1–N form a snake-like path.

## Files to create

- `board.lua` — game logic, puzzle generator, serialize/load
- `board_widget.lua` — grid rendering and tap gestures
- `screen.lua` — full-screen layout (buttons + board)
- `main.lua` — PluginBase entry point

## Notes

Number placement puzzle — use GridWidgetBase from game-common.
