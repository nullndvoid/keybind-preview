# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- **Build:** `zig build`
- **Run:** `zig build run`
- **Run with args:** `zig build run -- <args>`
- **Test:** `zig build test`

## Project Overview

A Zig tool for parsing and previewing keybindings from River (Wayland compositor) configuration files. It reads config files containing `riverctl map` commands and extracts keybinding information.

Requires Zig >= 0.15.2. No external dependencies.

## Architecture

- `src/main.zig` — Entry point and `Collector` struct. `Collector` opens a config file, parses lines starting with `riverctl map`, and produces `Bind` structs containing modifiers, key, description, and display format. Modifiers are represented as a `packed struct(u8)` bitfield (`Mods`).
- `src/Tokeniser.zig` — State-machine tokeniser (file-as-struct pattern) that splits a `riverctl map` line into tokens: modifier names (`Super`, `Alt`, `Shift`, `Ctrl`, `None`, `Mod3`, `Mod5`), `plus` separators, quoted `string` literals, `wildcard` (unrecognised words like mode name or key), and `eof`/`invalid`. The tokeniser expects the `riverctl map` prefix to already be stripped.

## Zig Conventions

- Uses Zig's file-as-struct pattern: `Tokeniser.zig` is imported as a type via `@import("Tokeniser.zig")`.
- Tests are co-located in source files (`test` blocks), run via `zig build test`.
