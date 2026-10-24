defmodule ConsoleOps.Param do
  @moduledoc """
  Typed parameter definitions for console commands.

  A param describes one named input of a command: its name, its type,
  whether it is required, and an optional default and doc. Build params
  with `new!/3`, then cast raw input with `cast/2` or `cast_all/2`.

      iex> params = [
      ...>   ConsoleOps.Param.new!(:invoice_id, :id, required: true),
      ...>   ConsoleOps.Param.new!(:limit, :integer, default: 10)
      ...> ]
      iex> ConsoleOps.Param.cast_all(params, %{"invoice_id" => "42"})
      {:ok, %{invoice_id: 42, limit: 10}}

  ## Types

  | Type       | Accepts                                                                                                 |
  | :--------- | :------------------------------------------------------------------------------------------------------ |
  | `:string`  | strings                                                                                                 |
  | `:integer` | integers, and strings that `Integer.parse/1` parses in full, such as `"+5"`                             |
  | `:boolean` | `true`, `false`, `"true"` and `"false"`                                                                 |
  | `:atom`    | atoms except `nil`; strings naming an existing atom, except `"nil"` and `""`                            |
  | `:id`      | positive integers; ASCII digit strings, parsed, rejected if zero; any other non-empty string, unchanged |
  | `:map`     | maps, including structs                                                                                 |
  | `:any`     | anything, unchanged                                                                                     |

  Casting never trims whitespace or ignores case.

  ## nil

  `nil` means "no value". `cast/2` rejects it for every type except `:any`.
  `cast_all/2` checks for `nil` before casting, so an explicit `nil` counts as
  missing for every type, `:any` included: a required param reports
  `{:missing, name}` and an optional param gets its default.

  ## IDs

  `:id` covers both integer keys and opaque string ids. A string of ASCII
  digits is parsed, so `"007"` casts to `7` and `"0"` is rejected. Any other
  non-empty string, such as a UUID, `"inv_123"` or `"-5"`, is returned unchanged.

  ## Atoms

  Strings are converted with `String.to_existing_atom/1`, so casting never
  creates atoms. `"nil"` and `""` are rejected even though those atoms exist,
  because a `"nil"` or `""` typed at a console is almost never meant as an atom.
  The string is looked up as is, so `":ok"` does not cast to `:ok`.

  ## Duplicates

  `cast_all/2` reports a param given more than once, whether repeated in a
  list or given as both `:name` and `"name"`, as a single `{:duplicate, name}`
  error, even when one of the values is `nil`.

  ## Differences from Ecto.Type

    * `cast/2` rejects `nil` for every type except `:any`, and `cast_all/2` treats it
      as missing. Ecto casts `nil` to `{:ok, nil}` for every built-in type.
    * `:boolean` accepts only `true`, `false`, `"true"` and `"false"`, not `"1"` or `"0"`.
    * `:id` rejects zero and negative integers, and returns any string that is not all
      ASCII digits, such as a UUID or `"-5"`, unchanged instead of parsing or rejecting it.
  """

  @types [:string, :integer, :boolean, :atom, :id, :map, :any]
  @options [:required, :default, :doc]

  @typedoc "A supported param type. See the table in the module docs."
  @type type :: :string | :integer | :boolean | :atom | :id | :map | :any

  @typedoc "A param definition. Build it with `new!/3`."
  @type t :: %__MODULE__{
          name: atom(),
          type: type(),
          required?: boolean(),
          default: term(),
          doc: String.t() | nil
        }

  @typedoc """
  An error returned by `cast_all/2`.

    * `{:missing, name}` - a required param is absent or `nil`
    * `{:duplicate, name}` - a param is given more than once
    * `{:invalid, name, type, value}` - `value` does not cast to `type`
    * `{:unknown, key, suggestion}` - `key` is not a declared param;
      `suggestion` is the closest param name, or `nil`
  """
  @type error ::
          {:missing, atom()}
          | {:duplicate, atom()}
          | {:invalid, atom(), type(), term()}
          | {:unknown, atom() | String.t(), atom() | nil}

  @enforce_keys [:name, :type]
  defstruct [:name, :type, required?: false, default: nil, doc: nil]

  @doc """
  Returns the supported types.

      iex> ConsoleOps.Param.types()
      [:string, :integer, :boolean, :atom, :id, :map, :any]

  """
  @spec types() :: [type()]
  def types, do: @types

  @doc """
  Builds a param, raising `ArgumentError` if the definition is invalid.

  ## Options

    * `:required` - whether `cast_all/2` reports the param as missing when
      it is absent or `nil`. Defaults to `false`.

    * `:default` - the value `cast_all/2` uses when an optional param is
      absent or `nil`. It is not cast, so it must already be a valid value
      of the type: `5` is a valid `:integer` default, `"5"` is not. Cannot be
      combined with `required: true`. Defaults to `nil`.

    * `:doc` - a description of the param. Defaults to `nil`.

  Each option can be given at most once.

  ## Examples

      iex> ConsoleOps.Param.new!(:limit, :integer, default: 10)
      %ConsoleOps.Param{name: :limit, type: :integer, required?: false, default: 10, doc: nil}

      iex> ConsoleOps.Param.new!(:limit, :int)
      ** (ArgumentError) unknown type :int for param :limit, did you mean :integer?

  """
  @spec new!(atom(), type(), keyword()) :: t()
  def new!(name, type, opts \\ []) do
    validate_name!(name)
    validate_type!(name, type)
    validate_options!(name, opts)

    required? = Keyword.get(opts, :required, false)
    default = Keyword.get(opts, :default)
    doc = Keyword.get(opts, :doc)

    validate_required!(name, required?)
    validate_doc!(name, doc)
    validate_default!(name, type, required?, default)

    %__MODULE__{name: name, type: type, required?: required?, default: default, doc: doc}
  end

  @doc """
  Casts `value` to the type of `param`.

  Returns `{:ok, cast_value}`, or `:error` if `value` cannot be cast.
  See the module docs for the rules of each type.

      iex> ConsoleOps.Param.cast(ConsoleOps.Param.new!(:limit, :integer), "42")
      {:ok, 42}

      iex> ConsoleOps.Param.cast(ConsoleOps.Param.new!(:limit, :integer), "ten")
      :error

      iex> ConsoleOps.Param.cast(ConsoleOps.Param.new!(:invoice_id, :id), "inv_123")
      {:ok, "inv_123"}

  """
  @spec cast(t(), term()) :: {:ok, term()} | :error
  def cast(%__MODULE__{type: type}, value), do: cast_type(type, value)

  @doc """
  Casts `input` against a list of params.

  `input` is a map or a list of key-value pairs. Keys may be atoms or
  strings, and a string key matches the param of the same name.

  Returns `{:ok, values}`, a map with a key for every param, where
  absent and `nil` optional params get their default. Otherwise returns
  `{:error, errors}` with every `t:error/0` found: at most one per param,
  in declaration order, followed by one per unknown key, in input order
  (enumeration order for a map).

  Raises `ArgumentError` if a list entry is not a `{key, value}` tuple or a key
  is neither an atom nor a string.

      iex> params = [
      ...>   ConsoleOps.Param.new!(:invoice_id, :id, required: true),
      ...>   ConsoleOps.Param.new!(:limit, :integer, default: 10)
      ...> ]
      iex> ConsoleOps.Param.cast_all(params, invoice_id: "42", limit: "5")
      {:ok, %{invoice_id: 42, limit: 5}}
      iex> ConsoleOps.Param.cast_all(params, limit: "ten", limt: 5)
      {:error, [{:missing, :invoice_id}, {:invalid, :limit, :integer, "ten"}, {:unknown, :limt, :limit}]}

  """
  @spec cast_all([t()], map() | [{atom() | String.t(), term()}]) ::
          {:ok, %{optional(atom()) => term()}} | {:error, [error()]}
  def cast_all(params, input) when is_list(params) and (is_map(input) or is_list(input)) do
    entries = Enum.map(input, &normalize_entry!/1)

    values_by_name =
      Enum.group_by(
        entries,
        fn {key_name, _key, _value} -> key_name end,
        fn {_key_name, _key, value} -> value end
      )

    results =
      for param <- params do
        values = Map.get(values_by_name, Atom.to_string(param.name), [])
        {param.name, cast_param(param, values)}
      end

    names = Enum.map(params, & &1.name)
    declared = Enum.map(names, &Atom.to_string/1)

    unknown_errors =
      for {key_name, key, _value} <- entries, key_name not in declared do
        {:unknown, key, closest(key_name, names)}
      end

    param_errors = for {_name, {:error, error}} <- results, do: error

    case param_errors ++ unknown_errors do
      [] -> {:ok, Map.new(results, fn {name, {:ok, value}} -> {name, value} end)}
      errors -> {:error, errors}
    end
  end

  defp validate_name!(name) when is_atom(name) and not is_nil(name), do: :ok

  defp validate_name!(name) do
    raise ArgumentError,
          "invalid param name: expected an atom other than nil, got: #{inspect(name)}"
  end

  defp validate_type!(_name, type) when type in @types, do: :ok

  defp validate_type!(name, type) do
    suggestion = if is_atom(type), do: closest(Atom.to_string(type), @types)

    message =
      if suggestion do
        "did you mean #{inspect(suggestion)}?"
      else
        "supported types are: #{inspect(@types)}"
      end

    raise ArgumentError, "unknown type #{inspect(type)} for param #{inspect(name)}, #{message}"
  end

  defp validate_options!(name, opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError,
            "invalid options for param #{inspect(name)}: expected a keyword list, got: #{inspect(opts)}"
    end

    keys = Keyword.keys(opts)

    case keys |> Enum.uniq() |> Enum.reject(&(&1 in @options)) do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown options #{inspect(unknown)} for param #{inspect(name)}, " <>
                "valid options are: #{inspect(@options)}"
    end

    case Enum.uniq(keys -- Enum.uniq(keys)) do
      [] ->
        :ok

      duplicates ->
        raise ArgumentError,
              "duplicate options #{inspect(duplicates)} for param #{inspect(name)}, " <>
                "each option can be given at most once"
    end
  end

  defp validate_required!(_name, required?) when is_boolean(required?), do: :ok

  defp validate_required!(name, required?) do
    raise ArgumentError,
          "invalid value for :required option of param #{inspect(name)}: " <>
            "expected a boolean, got: #{inspect(required?)}"
  end

  defp validate_doc!(_name, doc) when is_binary(doc) or is_nil(doc), do: :ok

  defp validate_doc!(name, doc) do
    raise ArgumentError,
          "invalid value for :doc option of param #{inspect(name)}: " <>
            "expected a string or nil, got: #{inspect(doc)}"
  end

  defp validate_default!(_name, _type, _required?, nil), do: :ok

  defp validate_default!(name, _type, true, default) do
    raise ArgumentError,
          "invalid value for :default option of param #{inspect(name)}: " <>
            "a required param cannot have a default, got: #{inspect(default)}"
  end

  defp validate_default!(name, type, false, default) do
    case cast_type(type, default) do
      {:ok, ^default} ->
        :ok

      result ->
        raise ArgumentError,
              "invalid value for :default option of param #{inspect(name)}: " <>
                "expected a value of type #{inspect(type)}, got: #{inspect(default)}" <>
                default_hint(result)
    end
  end

  defp default_hint({:ok, cast_value}),
    do: " (defaults are not cast, use #{inspect(cast_value)} instead)"

  defp default_hint(:error), do: ""

  defp cast_type(:any, value), do: {:ok, value}
  defp cast_type(:string, value) when is_binary(value), do: {:ok, value}
  defp cast_type(:integer, value) when is_integer(value), do: {:ok, value}
  defp cast_type(:integer, value) when is_binary(value), do: parse_integer(value)
  defp cast_type(:boolean, value) when is_boolean(value), do: {:ok, value}
  defp cast_type(:boolean, "true"), do: {:ok, true}
  defp cast_type(:boolean, "false"), do: {:ok, false}
  defp cast_type(:atom, value) when value in [nil, "nil", ""], do: :error
  defp cast_type(:atom, value) when is_atom(value), do: {:ok, value}
  defp cast_type(:atom, value) when is_binary(value), do: to_existing_atom(value)
  defp cast_type(:id, value) when is_integer(value) and value > 0, do: {:ok, value}

  defp cast_type(:id, value) when is_binary(value) and value != "" do
    if ascii_digits?(value), do: cast_type(:id, String.to_integer(value)), else: {:ok, value}
  end

  defp cast_type(:map, value) when is_map(value), do: {:ok, value}
  defp cast_type(_type, _value), do: :error

  defp parse_integer(string) do
    case Integer.parse(string) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp to_existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  defp ascii_digits?(string), do: String.match?(string, ~r/\A[0-9]+\z/)

  defp normalize_entry!({key, value}) when is_atom(key), do: {Atom.to_string(key), key, value}
  defp normalize_entry!({key, value}) when is_binary(key), do: {key, key, value}

  defp normalize_entry!({key, _value}) do
    raise ArgumentError, "expected input keys to be atoms or strings, got: #{inspect(key)}"
  end

  defp normalize_entry!(entry) do
    raise ArgumentError,
          "expected input to be a map or a list of {key, value} pairs, got: #{inspect(entry)}"
  end

  defp cast_param(param, [value]) when not is_nil(value) do
    case cast(param, value) do
      {:ok, cast_value} -> {:ok, cast_value}
      :error -> {:error, {:invalid, param.name, param.type, value}}
    end
  end

  defp cast_param(param, [_, _ | _]), do: {:error, {:duplicate, param.name}}

  defp cast_param(%__MODULE__{required?: true} = param, _absent),
    do: {:error, {:missing, param.name}}

  defp cast_param(param, _absent), do: {:ok, param.default}

  defp closest(string, candidates) do
    {candidate, distance} =
      candidates
      |> Enum.map(&{&1, String.jaro_distance(string, Atom.to_string(&1))})
      |> Enum.max_by(fn {_candidate, distance} -> distance end, fn -> {nil, 0.0} end)

    if distance >= 0.8, do: candidate
  end
end
