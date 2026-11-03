defmodule ConsoleOps.Command do
  @moduledoc """
  A console command: plain data describing one operation.

  Commands are built by `ConsoleOps.Registry` from its DSL, and read back with
  `__console_ops__(:commands)` on a registry module. A command does not hold
  the function that runs it; the registry does.

    * `:id` - the string `"<namespace>.<name>"`, unique within a registry
    * `:namespace` - the namespace the op was declared in
    * `:name` - the name of the op
    * `:summary` - a one-line description
    * `:mode` - what the op does, see `t:mode/0`
    * `:tags` - atoms for grouping and search, `[]` by default
    * `:params` - the `t:ConsoleOps.Param.t/0` definitions, in declaration
      order, `[]` by default
  """

  @modes [:readonly, :mutation, :destructive]

  @typedoc """
  What a command does: `:readonly` only reads, `:mutation` changes data and
  `:destructive` deletes or cannot be undone.
  """
  @type mode :: unquote(Enum.reduce(Enum.reverse(@modes), &{:|, [], [&1, &2]}))

  @typedoc "A command. Build it with `ConsoleOps.Registry`."
  @type t :: %__MODULE__{
          id: String.t(),
          namespace: atom(),
          name: atom(),
          summary: String.t(),
          mode: mode(),
          tags: [atom()],
          params: [ConsoleOps.Param.t()]
        }

  @enforce_keys [:id, :namespace, :name, :summary, :mode]
  defstruct [:id, :namespace, :name, :summary, :mode, tags: [], params: []]

  @doc false
  @spec modes() :: [mode()]
  def modes, do: @modes
end
