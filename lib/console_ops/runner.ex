defmodule ConsoleOps.Runner do
  @moduledoc """
  Runs the commands of a `ConsoleOps.Registry` by id.

  A command is looked up by id, its params are cast with
  `ConsoleOps.Param.cast_all/2`, and its handler is called with the cast
  params and a context.

  ## Handlers

  A handler returns `:ok`, `{:ok, value}` or `{:error, reason}`. Anything else
  raises `RuntimeError`, because it is a bug in the handler. Exceptions raised
  by a handler are not rescued.

  The context is a map. It is empty in this version, and later versions will
  add keys.

  ## Errors

  `run/3` returns a `t:result/0`. When a command cannot be run, the result is
  `{:error, error}` with a `ConsoleOps.Error`, and `run!/3` raises that error
  instead. Later versions will add error reasons, so keep a fallback clause
  when matching on `:reason`.

  Mistakes in the calling code raise instead of returning an error: a module
  that does not use `ConsoleOps.Registry`, or a struct given as params, raises
  `ArgumentError`; an id that is neither a string nor an atom, or params that
  are neither a map nor a list, raises `FunctionClauseError`.
  """

  alias ConsoleOps.Error
  alias ConsoleOps.Param

  @typedoc "The id of a command, such as `\"billing.invoice_state\"`. An atom is converted to a string."
  @type id :: String.t() | atom()

  @typedoc "The result of `run/3`."
  @type result :: {:ok, term()} | {:error, Error.t()}

  @doc """
  Runs the command with the given `id` in `registry`.

  `params` is a map or a list of key-value pairs, as accepted by
  `ConsoleOps.Param.cast_all/2`.

  Returns `{:ok, value}` when the handler returns `{:ok, value}`, or
  `{:ok, :ok}` when it returns `:ok`. Returns `{:error, error}` when the
  command is unknown, its params do not cast, or its handler returns
  `{:error, reason}`. See the module docs and `ConsoleOps.Error`.

      case ConsoleOps.Runner.run(MyApp.Console, "billing.invoice_state", invoice_id: "42") do
        {:ok, state} -> state
        {:error, %ConsoleOps.Error{} = error} -> Exception.message(error)
      end

  """
  @spec run(module(), id(), map() | [{atom() | String.t(), term()}]) :: result()
  def run(registry, id, params) when is_binary(id) or is_atom(id) do
    validate_registry!(registry)
    id = id_to_string(id)
    commands = registry.__console_ops__(:commands)

    case Enum.find(commands, &(&1.id == id)) do
      nil -> {:error, unknown_command(commands, id)}
      command -> cast_and_dispatch(registry, command, params)
    end
  end

  @doc """
  Runs a command like `run/3`, returning the value or raising the error.

  Returns the value of `{:ok, value}`, which is `:ok` when the handler returns
  a bare `:ok`. Raises the `ConsoleOps.Error` that `run/3` would return.
  """
  @spec run!(module(), id(), map() | [{atom() | String.t(), term()}]) :: term()
  def run!(registry, id, params) do
    case run(registry, id, params) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  defp id_to_string(id) when is_atom(id), do: Atom.to_string(id)
  defp id_to_string(id), do: id

  defp validate_registry!(registry) do
    if is_atom(registry) and Code.ensure_loaded?(registry) and
         function_exported?(registry, :__console_ops__, 1) do
      :ok
    else
      raise ArgumentError,
            "expected a module that uses ConsoleOps.Registry, got: #{inspect(registry)}"
    end
  end

  defp unknown_command(commands, id) do
    suggestion = Param.closest(id, Enum.map(commands, & &1.id))

    %Error{reason: :unknown_command, id: id, suggestion: suggestion}
  end

  defp cast_and_dispatch(registry, command, params) do
    case Param.cast_all(command.params, params) do
      {:ok, values} ->
        result = registry.__console_ops__(:run, command.id, values, %{})
        handle_result(result, command)

      {:error, errors} ->
        {:error, %Error{reason: :invalid_params, id: command.id, errors: errors}}
    end
  end

  defp handle_result({:ok, value}, _command), do: {:ok, value}
  defp handle_result(:ok, _command), do: {:ok, :ok}

  defp handle_result({:error, reason}, command) do
    {:error, %Error{reason: :command_failed, id: command.id, value: reason}}
  end

  defp handle_result(other, command) do
    raise RuntimeError,
          "expected command #{inspect(command.id)} to return :ok, {:ok, value} or " <>
            "{:error, reason}, got: #{inspect(other)}"
  end
end
