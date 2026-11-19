defmodule ConsoleOps.Error do
  @moduledoc """
  The exception returned or raised when a command cannot be run.

  `ConsoleOps.Runner.run/3` returns it in an `{:error, error}` tuple, and
  `ConsoleOps.Runner.run!/3` raises it. `:reason` says what went wrong, and
  `:id` is the id of the command as a string:

    * `:unknown_command` - the registry has no command with that `:id`.
      `:suggestion` is the id of the closest command, or `nil`.
    * `:invalid_params` - the params did not cast. `:errors` lists every
      `t:ConsoleOps.Param.error/0` found.
    * `:command_failed` - the handler returned `{:error, reason}`. `:value`
      is that `reason`.

  Fields that a reason does not set keep their defaults: `:suggestion` and
  `:value` are `nil` and `:errors` is `[]`.

  Later versions will add reasons, so code that matches on `:reason` should
  keep a fallback clause.
  """

  @typedoc "Why a command could not be run. See the module docs."
  @type reason :: :unknown_command | :invalid_params | :command_failed

  @typedoc "An error. See the module docs for the fields each reason sets."
  @type t :: %__MODULE__{
          reason: reason(),
          id: String.t(),
          suggestion: String.t() | nil,
          errors: [ConsoleOps.Param.error()],
          value: term()
        }

  @enforce_keys [:reason, :id]
  defexception [:reason, :id, suggestion: nil, errors: [], value: nil]

  @doc """
  Returns the message of the error as a string.

      iex> error = %ConsoleOps.Error{
      ...>   reason: :unknown_command,
      ...>   id: "billing.invoce_state",
      ...>   suggestion: "billing.invoice_state"
      ...> }
      iex> Exception.message(error)
      "unknown command \\"billing.invoce_state\\", did you mean \\"billing.invoice_state\\"?"

      iex> error = %ConsoleOps.Error{
      ...>   reason: :invalid_params,
      ...>   id: "billing.invoice_state",
      ...>   errors: [
      ...>     {:missing, :invoice_id},
      ...>     {:invalid, :limit, :integer, "ten"},
      ...>     {:unknown, :limt, :limit}
      ...>   ]
      ...> }
      iex> Exception.message(error)
      "invalid params for command \\"billing.invoice_state\\":\\n" <>
        "  * missing required param :invoice_id\\n" <>
        "  * invalid value for param :limit, expected a value of type :integer, got: \\"ten\\"\\n" <>
        "  * unknown param :limt, did you mean :limit?"

  """
  @impl Exception
  @spec message(t()) :: String.t()
  def message(%__MODULE__{reason: :unknown_command, id: id, suggestion: suggestion}) do
    "unknown command #{inspect(id)}" <> suggestion_hint(suggestion)
  end

  def message(%__MODULE__{reason: :invalid_params, id: id, errors: errors}) do
    "invalid params for command #{inspect(id)}:" <>
      Enum.map_join(errors, &"\n  * #{param_error_message(&1)}")
  end

  def message(%__MODULE__{reason: :command_failed, id: id, value: value}) do
    "command #{inspect(id)} failed: #{inspect(value)}"
  end

  defp param_error_message({:missing, name}), do: "missing required param #{inspect(name)}"

  defp param_error_message({:duplicate, name}) do
    "duplicate param #{inspect(name)}, each param can be given at most once"
  end

  defp param_error_message({:invalid, name, type, value}) do
    "invalid value for param #{inspect(name)}, " <>
      "expected a value of type #{inspect(type)}, got: #{inspect(value)}"
  end

  defp param_error_message({:unknown, key, suggestion}) do
    "unknown param #{inspect(key)}" <> suggestion_hint(suggestion)
  end

  defp suggestion_hint(nil), do: ""
  defp suggestion_hint(suggestion), do: ", did you mean #{inspect(suggestion)}?"
end
