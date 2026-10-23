# ConsoleOps

[![CI](https://github.com/elliotjon/console_ops/actions/workflows/ci.yml/badge.svg)](https://github.com/elliotjon/console_ops/actions/workflows/ci.yml)

A project-owned, discoverable command registry for IEx.

> **Note:** ConsoleOps is in early development and is not yet published on Hex.
> Everything below describes the design target and may change before `0.1.0`.

## Why

Operational knowledge in Elixir teams tends to live in `.iex.exs` files, old
shell history, chat threads and one-off scripts. ConsoleOps aims to give it a
home: a registry of typed, documented commands that anyone on the team can
discover and run from IEx, whether locally, in a remote shell or in a release.

## A first look

```elixir
defmodule MyApp.Console do
  use ConsoleOps.Registry

  namespace :billing do
    op :invoice_state, "Inspect invoice and payment state" do
      mode :readonly
      param :invoice_id, :integer, required: true
      run &MyApp.Billing.Console.invoice_state/2
    end
  end
end
```

```elixir
# .iex.exs
use ConsoleOps.IEx, registry: MyApp.Console
```

```elixir
iex> ops("invoice")
iex> doc(:billing.invoice_state)
iex> run(:billing.invoice_state, invoice_id: 123)
```

`doc` and `run` are macros, so `:billing.invoice_state` is read as a command
name rather than evaluated as a function call. In code, commands are referred
to by their string id, `"billing.invoice_state"`.

## Design goals

- **No runtime dependencies** in the core package. Ecto and Livebook support
  will ship as separate, optional packages.
- **Commands are data.** Every command will be an inspectable struct, so
  search, documentation and notebook generation all work from one definition.
- **Safe by default.** Commands will declare whether they are read-only,
  mutating or destructive, and mutations can default to dry runs and require
  confirmation.
- **The same everywhere.** Local IEx, remote shells and releases should behave
  alike.

## Roadmap

| Version | Focus |
| --- | --- |
| `0.1` | Command registry, parameter validation and IEx helpers |
| `0.2` | Richer metadata, examples and search |
| `0.3` | Safety model: modes, dry runs, confirmation and audit events |
| Later | Ecto and Livebook integrations, release-shell hardening |

## License

Copyright (c) 2026 Elliot Nordin.

ConsoleOps is released under the Apache License 2.0. See
[LICENSE](https://github.com/elliotjon/console_ops/blob/main/LICENSE).
