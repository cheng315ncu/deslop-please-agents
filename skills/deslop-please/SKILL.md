---
name: deslop-please
description: Check and fix the structure of Rust code with deslop-please (deep modules, narrow interfaces): module-cycle, tangle, field-leak, shallow-module, wide-directory and long-file errors. Use when working in a Cargo workspace after adding or moving modules, types or functions, when refactoring, before committing Rust changes, when the user asks about code structure or "slop", and whenever deslop-please reports errors (including from the Stop hook).
---

# deslop-please

`deslop-please` is an architectural linter for Rust workspaces after *A Philosophy of Software Design*: **deep** modules behind **narrow** interfaces. Every error it reports is one idea seen from a different angle: something that should be hidden is known outside the place that owns it.

## Running it

- Run `deslop-please --json` from anywhere inside the workspace, adding `--allow .deslop-please.allow` if that file exists at the workspace root. Exit code 0 is clean, 1 is errors, 2 is a failure to run. The JSON has `ok`, `count`, `fixed_allowed` and `diagnostics`, each with `lint`, `key`, `message`, `file`, `line` and `notes`.
- Without `--json` it prints the report as rustc-style text, with a picture of each problem's shape under it; read that when the shape of a cycle or tangle matters.
- `deslop-please <crate_or_mod>` checks one crate or module (`my-crate`, `my_crate::net`); `--target`, `-F`/`--features`, `--all-features` and `--no-default-features` pick the configuration, as `cargo check` takes them.
- It needs `rust-analyzer` on `PATH`. The first run indexes the workspace, which can take a while; later runs reuse the index until a source file changes.
- One run checks one configuration: code behind a `cfg` that configuration leaves off is not seen.

## The allow file is the user's

`.deslop-please.allow` at the workspace root lists existing debt, which is then not reported; only new errors count. **Never create it, add entries to it, or run `--update-allow` unless the user explicitly asks.** Muting an error is the user's decision. When an allowed entry gets fixed, tell the user they can tighten the file with `deslop-please --update-allow .deslop-please.allow`.

## Fixing errors

Fix from first principles, never by mechanical moves that only make an error disappear. The lints see through re-exports, relay functions, getters and setters, moved `impl` blocks and members lifted into a parent module: such moves change nothing they report, by design.

1. Read every error before changing anything, and group the ones about the same types or modules: fix them holistically, not one leak at a time.
2. For each group, decide the intended structure: which module belongs at which layer of abstraction, what each type is responsible for, which few operations its users actually need.
3. For anything beyond a local change, show the user the structure before and after (a small diagram of modules and who uses whom) and agree on it before restructuring.
4. Make the change, then run `deslop-please` again and the tests.

What each lint means and the usual direction of a fix:

- **module-cycle**: sibling modules use each other in a circle, so there is no order to read them in. Decide which one is the lower layer and move the item the lower one needs from the higher into it (or into a new lower module), so uses point one way.
- **tangle**: things (types with their methods, free functions) know each other in a circle across modules, or more than seven of them. Untie it: let code one level up coordinate the parts so they no longer know each other, or, if they really are one concept, make them one module.
- **field-leak**: code outside a type writes, borrows, indexes or calls methods on one of its fields, directly or through a getter or setter. Ask why outsiders touch it at all: give the type the operations they perform (`push`, `pop`, `backlog` instead of `queue.items.push(...)`), and keep the field private. Reading a plain value is fine; adding getters is not a fix.
- **shallow-module**: a crate, or a module with child modules, shows more functions than a reader holds in mind and at least as many as it hides. Find the patterns of use and offer a few deeper entry points that do more each, hiding the rest. Wrappers and forwarders do not count as depth.
- **wide-directory**: a directory holds more than 15 Rust files and directories. Group them into modules by concept, each with a narrow interface.
- **long-file**: a file has more than 2,000 lines. Split it along the parts it holds, each part a module that hides its details.
