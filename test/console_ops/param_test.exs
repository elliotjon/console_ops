defmodule ConsoleOps.ParamTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ConsoleOps.Param

  doctest ConsoleOps.Param

  # Bound for the wide integer generators in the cast/2 properties.
  @wide 2 ** 100

  describe "new!/3" do
    test "builds an optional param with no default and no doc" do
      assert Param.new!(:invoice_id, :id) ==
               %Param{name: :invoice_id, type: :id, required?: false, default: nil, doc: nil}
    end

    test "maps the :required option to the required? field" do
      assert %Param{required?: true} = Param.new!(:invoice_id, :id, required: true)
      assert %Param{required?: false} = Param.new!(:invoice_id, :id, required: false)
    end

    test "stores the :default and :doc options" do
      assert %Param{default: 10, doc: "Maximum number of rows"} =
               Param.new!(:limit, :integer, default: 10, doc: "Maximum number of rows")
    end

    test "accepts required: true with a nil default" do
      assert %Param{required?: true, default: nil} =
               Param.new!(:invoice_id, :id, required: true, default: nil)
    end

    test "accepts a nil doc" do
      assert %Param{doc: nil} = Param.new!(:invoice_id, :id, doc: nil)
    end
  end

  describe "new!/3 name and type validation" do
    for name <- ["amount", {:amount}, nil] do
      message = "invalid param name: expected an atom other than nil, got: #{inspect(name)}"

      test "raises when the name is #{inspect(name)}" do
        assert_raise ArgumentError, unquote(message), fn ->
          Param.new!(unquote(Macro.escape(name)), :integer)
        end
      end
    end

    # The type error names the param, so the name must be valid first.
    test "checks the name before the type" do
      assert_raise ArgumentError,
                   ~S|invalid param name: expected an atom other than nil, got: "amount"|,
                   fn -> Param.new!("amount", :int) end
    end

    for {type, message} <- [
          int: "unknown type :int for param :id, did you mean :integer?",
          bool: "unknown type :bool for param :id, did you mean :boolean?",
          str: "unknown type :str for param :id, did you mean :string?"
        ] do
      test "raises suggesting the closest supported type for #{inspect(type)}" do
        assert_raise ArgumentError, unquote(message), fn -> Param.new!(:id, unquote(type)) end
      end
    end

    for type <- [:float, "integer"] do
      message =
        "unknown type #{inspect(type)} for param :amount, supported types are: " <>
          "[:string, :integer, :boolean, :atom, :id, :map, :any]"

      test "raises listing the supported types for #{inspect(type)}" do
        assert_raise ArgumentError, unquote(message), fn -> Param.new!(:amount, unquote(type)) end
      end
    end
  end

  describe "new!/3 option validation" do
    for opts <- [[:required], [{"required", true}]] do
      message =
        "invalid options for param :amount: expected a keyword list, got: #{inspect(opts)}"

      test "raises when the options are #{inspect(opts)}, not a keyword list" do
        assert_raise ArgumentError, unquote(message), fn ->
          Param.new!(:amount, :integer, unquote(opts))
        end
      end
    end

    test "raises naming every unknown option and the allowed ones" do
      assert_raise ArgumentError,
                   "unknown options [:requird, :deflaut] for param :amount, " <>
                     "valid options are: [:required, :default, :doc]",
                   fn -> Param.new!(:amount, :integer, requird: true, deflaut: 1) end
    end

    test "lists an unknown option given twice only once" do
      assert_raise ArgumentError,
                   "unknown options [:foo] for param :amount, " <>
                     "valid options are: [:required, :default, :doc]",
                   fn -> Param.new!(:amount, :integer, foo: 1, foo: 2) end
    end

    for {option, opts} <- [
          required: [required: true, required: false],
          doc: [doc: "a", default: 1, doc: "b"]
        ] do
      message =
        "duplicate options [#{inspect(option)}] for param :amount, " <>
          "each option can be given at most once"

      test "raises when #{inspect(option)} is given more than once in #{inspect(opts)}" do
        assert_raise ArgumentError, unquote(message), fn ->
          Param.new!(:amount, :integer, unquote(opts))
        end
      end
    end

    for value <- [nil, "true", 1] do
      message =
        "invalid value for :required option of param :amount: " <>
          "expected a boolean, got: #{inspect(value)}"

      test "raises when :required is #{inspect(value)}" do
        assert_raise ArgumentError, unquote(message), fn ->
          Param.new!(:amount, :integer, required: unquote(value))
        end
      end
    end

    for value <- [:intro, 42, ~c"Amount in cents"] do
      message =
        "invalid value for :doc option of param :amount: " <>
          "expected a string or nil, got: #{inspect(value)}"

      test "raises when :doc is #{inspect(value)}" do
        assert_raise ArgumentError, unquote(message), fn ->
          Param.new!(:amount, :integer, doc: unquote(value))
        end
      end
    end

    test "raises when a required param also has a default" do
      assert_raise ArgumentError,
                   "invalid value for :default option of param :amount: " <>
                     "a required param cannot have a default, got: 5",
                   fn -> Param.new!(:amount, :integer, required: true, default: 5) end
    end
  end

  describe "new!/3 default validation" do
    for {type, default, hint} <- [
          {:integer, "5", "use 5 instead"},
          {:id, "5", "use 5 instead"},
          {:boolean, "true", "use true instead"},
          {:atom, "ok", "use :ok instead"}
        ] do
      message =
        "invalid value for :default option of param :amount: expected a value of type " <>
          "#{inspect(type)}, got: #{inspect(default)} (defaults are not cast, #{hint})"

      test "rejects #{inspect(default)} as a #{inspect(type)} default, hinting at the cast value" do
        assert_raise ArgumentError, unquote(message), fn ->
          Param.new!(:amount, unquote(type), default: unquote(default))
        end
      end
    end

    test "rejects a default that does not cast to the type, without a hint" do
      assert_raise ArgumentError,
                   "invalid value for :default option of param :amount: " <>
                     "expected a value of type :integer, got: 1.0",
                   fn -> Param.new!(:amount, :integer, default: 1.0) end
    end

    for {type, default} <- [id: 0, map: [a: 1]] do
      message =
        "invalid value for :default option of param :amount: expected a value of type " <>
          "#{inspect(type)}, got: #{inspect(default)}"

      test "rejects #{inspect(default)} as a #{inspect(type)} default without a hint" do
        assert_raise ArgumentError, unquote(message), fn ->
          Param.new!(:amount, unquote(type), default: unquote(default))
        end
      end
    end

    for {type, default} <- [
          string: "x",
          integer: 5,
          boolean: false,
          atom: :foo,
          id: 5,
          id: "abc-uuid",
          map: %{a: 1},
          any: "5",
          any: [a: 1]
        ] do
      test "accepts #{inspect(default)} as a #{inspect(type)} default" do
        default = unquote(Macro.escape(default))
        assert %Param{default: ^default} = Param.new!(:amount, unquote(type), default: default)
      end
    end
  end

  describe "cast/2 with :string" do
    for value <- ["x", ""] do
      test "accepts #{inspect(value)}" do
        assert Param.cast(param(:string), unquote(value)) == {:ok, unquote(value)}
      end
    end

    for value <- [:x, 1, ~c"x"] do
      test "rejects #{inspect(value)}" do
        assert Param.cast(param(:string), unquote(value)) == :error
      end
    end
  end

  describe "cast/2 with :integer" do
    for value <- [0, 42, -3] do
      test "accepts the integer #{value}" do
        assert Param.cast(param(:integer), unquote(value)) == {:ok, unquote(value)}
      end
    end

    for {string, integer} <- [{"42", 42}, {"-3", -3}, {"+5", 5}, {"007", 7}, {"-0", 0}] do
      test "parses #{inspect(string)} to #{integer}" do
        assert Param.cast(param(:integer), unquote(string)) == {:ok, unquote(integer)}
      end
    end

    # "٣" is ARABIC-INDIC DIGIT THREE: only ASCII digits are integers.
    for value <- [1.0, "1.0", " 1", "1 ", "1\n", "", "1_000", "12abc", "abc", "٣"] do
      test "rejects #{inspect(value)}" do
        assert Param.cast(param(:integer), unquote(value)) == :error
      end
    end
  end

  describe "cast/2 with :boolean" do
    for {value, boolean} <- [{true, true}, {false, false}, {"true", true}, {"false", false}] do
      test "casts #{inspect(value)} to #{boolean}" do
        assert Param.cast(param(:boolean), unquote(value)) == {:ok, unquote(boolean)}
      end
    end

    for value <- ["TRUE", "True", "1", "0", "yes", "", 1, 0, :yes] do
      test "rejects #{inspect(value)}" do
        assert Param.cast(param(:boolean), unquote(value)) == :error
      end
    end
  end

  describe "cast/2 with :atom" do
    for value <- [:foo, true, false, :""] do
      test "accepts the atom #{inspect(value)}" do
        assert Param.cast(param(:atom), unquote(value)) == {:ok, unquote(value)}
      end
    end

    test "converts a string naming an existing atom" do
      assert Param.cast(param(:atom), "ok") == {:ok, :ok}
    end

    test "rejects a string naming an atom that does not exist, without creating it" do
      string = "console_ops_never_#{System.unique_integer([:positive])}"
      refute existing_atom?(string)

      assert Param.cast(param(:atom), string) == :error
      refute existing_atom?(string)
    end

    # String.to_existing_atom("nil") returns nil, which is not a valid :atom value.
    test ~S(rejects "nil") do
      assert Param.cast(param(:atom), "nil") == :error
    end

    test "rejects the empty string" do
      assert Param.cast(param(:atom), "") == :error
    end

    # The string is looked up as is, so ":ok" names the atom :":ok", not :ok.
    test "does not strip a leading colon" do
      assert Param.cast(param(:atom), ":ok") == :error
    end

    for value <- [1, ~c"ok"] do
      test "rejects #{inspect(value)}" do
        assert Param.cast(param(:atom), unquote(value)) == :error
      end
    end
  end

  describe "cast/2 with :id" do
    for value <- [1, 42] do
      test "accepts the positive integer #{value}" do
        assert Param.cast(param(:id), unquote(value)) == {:ok, unquote(value)}
      end
    end

    for {string, integer} <- [{"1", 1}, {"42", 42}, {"007", 7}] do
      test "parses #{inspect(string)} to #{integer}" do
        assert Param.cast(param(:id), unquote(string)) == {:ok, unquote(integer)}
      end
    end

    for value <- [0, -1, "0", "000", "", 1.0, :invoice] do
      test "rejects #{inspect(value)}" do
        assert Param.cast(param(:id), unquote(value)) == :error
      end
    end

    # Only ASCII-digit strings are parsed. Anything else is an opaque string id,
    # so "-5" is not a negative integer and passes through like a UUID does.
    for value <- ["550e8400-e29b-41d4-a716-446655440000", "inv_123", "-5", "-0", " 5", "1.5"] do
      test "passes #{inspect(value)} through unchanged" do
        assert Param.cast(param(:id), unquote(value)) == {:ok, unquote(value)}
      end
    end
  end

  describe "cast/2 with :map" do
    test "accepts an empty map" do
      assert Param.cast(param(:map), %{}) == {:ok, %{}}
    end

    test "accepts a map with entries" do
      assert Param.cast(param(:map), %{"page" => 1}) == {:ok, %{"page" => 1}}
    end

    test "accepts a struct" do
      uri = URI.parse("https://example.com")
      assert Param.cast(param(:map), uri) == {:ok, uri}
    end

    for value <- [[page: 1], [], "page=1"] do
      test "rejects #{inspect(value)}" do
        assert Param.cast(param(:map), unquote(value)) == :error
      end
    end
  end

  describe "cast/2 with :any" do
    for value <- [nil, "x", 1, :foo, [a: 1], %{a: 1}] do
      test "returns #{inspect(value)} unchanged" do
        value = unquote(Macro.escape(value))
        assert Param.cast(param(:any), value) == {:ok, value}
      end
    end
  end

  describe "cast/2 with nil" do
    for type <- [:string, :integer, :boolean, :atom, :id, :map] do
      test "rejects nil for #{inspect(type)}" do
        assert Param.cast(param(unquote(type)), nil) == :error
      end
    end
  end

  describe "cast_all/2 input shapes" do
    test "accepts a keyword list" do
      assert Param.cast_all(invoice_params(), invoice_id: 42, limit: 5, note: "Overdue") ==
               {:ok, %{invoice_id: 42, limit: 5, note: "Overdue"}}
    end

    test "accepts a map with atom keys" do
      assert Param.cast_all(invoice_params(), %{invoice_id: "42", limit: "5"}) ==
               {:ok, %{invoice_id: 42, limit: 5, note: nil}}
    end

    test "accepts a map with string keys" do
      assert Param.cast_all(invoice_params(), %{"invoice_id" => "42", "note" => "Overdue"}) ==
               {:ok, %{invoice_id: 42, limit: 10, note: "Overdue"}}
    end

    test "accepts a list with string keys" do
      assert Param.cast_all(invoice_params(), [{"invoice_id", "42"}, {"limit", "5"}]) ==
               {:ok, %{invoice_id: 42, limit: 5, note: nil}}
    end

    test "accepts a list mixing atom and string keys" do
      assert Param.cast_all(invoice_params(), [{"invoice_id", "42"}, {:limit, 5}]) ==
               {:ok, %{invoice_id: 42, limit: 5, note: nil}}
    end

    test "matches string keys against the exact param name" do
      assert Param.cast_all(invoice_params(), [{"INVOICE_ID", "42"}]) ==
               {:error, [{:missing, :invoice_id}, {:unknown, "INVOICE_ID", nil}]}
    end

    test "returns an empty map for no params and empty input" do
      assert Param.cast_all([], []) == {:ok, %{}}
      assert Param.cast_all([], %{}) == {:ok, %{}}
    end

    test "raises on a list key that is neither an atom nor a string" do
      assert_raise ArgumentError, "expected input keys to be atoms or strings, got: 1", fn ->
        Param.cast_all(invoice_params(), [{"invoice_id", 1}, {1, "x"}])
      end
    end

    test "raises on a map key that is neither an atom nor a string" do
      assert_raise ArgumentError, "expected input keys to be atoms or strings, got: 1", fn ->
        Param.cast_all(invoice_params(), %{"invoice_id" => 1, 1 => "x"})
      end
    end

    test "raises on a list entry that is not a tuple" do
      assert_raise ArgumentError,
                   "expected input to be a map or a list of {key, value} pairs, got: :verbose",
                   fn -> Param.cast_all(invoice_params(), [:verbose]) end
    end

    test "raises on a list entry that is a tuple of the wrong size" do
      assert_raise ArgumentError,
                   "expected input to be a map or a list of {key, value} pairs, got: {:a, 1, 2}",
                   fn -> Param.cast_all(invoice_params(), [{:a, 1, 2}]) end
    end
  end

  describe "cast_all/2 missing and nil values" do
    test "fills missing optional params with their default, or nil without one" do
      assert Param.cast_all(invoice_params(), invoice_id: 42) ==
               {:ok, %{invoice_id: 42, limit: 10, note: nil}}
    end

    test "treats an explicit nil for an optional param as missing" do
      assert Param.cast_all(invoice_params(), invoice_id: 42, limit: nil, note: nil) ==
               {:ok, %{invoice_id: 42, limit: 10, note: nil}}
    end

    test "reports a missing required param" do
      assert Param.cast_all(invoice_params(), limit: 5) == {:error, [{:missing, :invoice_id}]}
    end

    test "treats an explicit nil for a required param as missing" do
      assert Param.cast_all(invoice_params(), invoice_id: nil) ==
               {:error, [{:missing, :invoice_id}]}
    end

    # cast/2 accepts nil for :any, but cast_all/2 checks for nil before casting.
    test "treats an explicit nil for a required :any param as missing" do
      params = [Param.new!(:payload, :any, required: true)]
      assert Param.cast_all(params, payload: nil) == {:error, [{:missing, :payload}]}
    end

    test "accepts an empty string for a required :string param" do
      params = [Param.new!(:name, :string, required: true)]
      assert Param.cast_all(params, name: "") == {:ok, %{name: ""}}
    end
  end

  describe "cast_all/2 duplicate keys" do
    test "reports a key given twice in a list" do
      assert Param.cast_all(invoice_params(), invoice_id: 1, invoice_id: 2) ==
               {:error, [{:duplicate, :invoice_id}]}
    end

    test "reports a key given three times once" do
      assert Param.cast_all(invoice_params(), invoice_id: 1, invoice_id: 2, invoice_id: 3) ==
               {:error, [{:duplicate, :invoice_id}]}
    end

    test "reports a key given in atom and string form in a list" do
      assert Param.cast_all(invoice_params(), [{:invoice_id, 1}, {"invoice_id", 1}]) ==
               {:error, [{:duplicate, :invoice_id}]}
    end

    test "reports a key given in atom and string form in a map" do
      assert Param.cast_all(invoice_params(), %{:invoice_id => 1, "invoice_id" => 1}) ==
               {:error, [{:duplicate, :invoice_id}]}
    end

    test "reports a duplicate rather than a missing value when one value is nil" do
      assert Param.cast_all(invoice_params(), invoice_id: nil, invoice_id: 1) ==
               {:error, [{:duplicate, :invoice_id}]}
    end

    test "reports a duplicate rather than invalid values" do
      assert Param.cast_all(invoice_params(), invoice_id: 1, limit: "ten", limit: "eleven") ==
               {:error, [{:duplicate, :limit}]}
    end
  end

  describe "cast_all/2 unknown keys" do
    test "suggests the closest param name for an unknown atom key" do
      assert Param.cast_all(invoice_params(), invoice_id: 1, limt: 5) ==
               {:error, [{:unknown, :limt, :limit}]}
    end

    test "keeps an unknown string key as a string" do
      assert Param.cast_all(invoice_params(), [{"invoice_id", 1}, {"limt", 5}]) ==
               {:error, [{:unknown, "limt", :limit}]}
    end

    # :length exists in every VM (erlang:length/1), yet the key must not become an atom.
    test "keeps an unknown string key as a string even when that atom exists" do
      assert Param.cast_all(invoice_params(), [{"invoice_id", 1}, {"length", 5}]) ==
               {:error, [{:unknown, "length", nil}]}
    end

    test "suggests nothing when no param name is close" do
      assert Param.cast_all(invoice_params(), invoice_id: 1, foo: 5) ==
               {:error, [{:unknown, :foo, nil}]}
    end

    # String.jaro_distance("usr", "user_id") is 0.81, just above the 0.8 threshold.
    test "suggests a name just above the similarity threshold" do
      params = [Param.new!(:user_id, :id)]
      assert Param.cast_all(params, usr: 1) == {:error, [{:unknown, :usr, :user_id}]}
    end

    # String.jaro_distance("cust", "customer_id") is 0.79, just below the 0.8 threshold.
    test "suggests nothing just below the similarity threshold" do
      params = [Param.new!(:customer_id, :id)]
      assert Param.cast_all(params, cust: 1) == {:error, [{:unknown, :cust, nil}]}
    end

    test "suggests the most similar of several close names" do
      params = [Param.new!(:limits, :integer), Param.new!(:limit, :integer)]
      assert Param.cast_all(params, limitz: 1) == {:error, [{:unknown, :limitz, :limit}]}
    end

    test "breaks suggestion ties in favour of the param declared first" do
      limit_a = Param.new!(:limit_a, :integer)
      limit_b = Param.new!(:limit_b, :integer)

      assert Param.cast_all([limit_a, limit_b], limit_c: 1) ==
               {:error, [{:unknown, :limit_c, :limit_a}]}

      assert Param.cast_all([limit_b, limit_a], limit_c: 1) ==
               {:error, [{:unknown, :limit_c, :limit_b}]}
    end

    test "reports repeated unknown keys once per occurrence, never as duplicates" do
      assert Param.cast_all(invoice_params(), [{:invoice_id, 1}, {:foo, 1}, {"foo", 2}, {:foo, 3}]) ==
               {:error, [{:unknown, :foo, nil}, {:unknown, "foo", nil}, {:unknown, :foo, nil}]}
    end

    test "reports every key as unknown when no params are declared" do
      assert Param.cast_all([], foo: 1) == {:error, [{:unknown, :foo, nil}]}
    end
  end

  describe "cast_all/2 error collection" do
    test "reports a failed cast with the param name, type and raw value" do
      assert Param.cast_all(invoice_params(), invoice_id: 1, limit: "ten") ==
               {:error, [{:invalid, :limit, :integer, "ten"}]}
    end

    test "reports param errors in declaration order, then unknown keys in input order" do
      input = [{"zebra", 1}, {:note, 5}, {:limt, 2}, {:limit, "ten"}]

      assert Param.cast_all(invoice_params(), input) ==
               {:error,
                [
                  {:missing, :invoice_id},
                  {:invalid, :limit, :integer, "ten"},
                  {:invalid, :note, :string, 5},
                  {:unknown, "zebra", nil},
                  {:unknown, :limt, :limit}
                ]}
    end
  end

  describe "cast/2 properties" do
    # integer() and friends only grow with the run size, so each generator is
    # mixed with a wide range to reach bignums while keeping small-value shrinking.
    property "casts every integer and its string form to that integer" do
      check all integer <- one_of([integer(), integer(-@wide..@wide)]) do
        assert Param.cast(param(:integer), integer) == {:ok, integer}
        assert Param.cast(param(:integer), Integer.to_string(integer)) == {:ok, integer}
      end
    end

    property "casts every positive integer and its string form to that :id" do
      check all id <- one_of([positive_integer(), integer(1..@wide)]) do
        assert Param.cast(param(:id), id) == {:ok, id}
        assert Param.cast(param(:id), Integer.to_string(id)) == {:ok, id}
      end
    end

    property "rejects every non-positive integer as an :id" do
      check all integer <- one_of([non_negative_integer(), integer(0..@wide)]) do
        assert Param.cast(param(:id), -integer) == :error
      end
    end

    property "never creates an atom from a string" do
      check all string <- string(:printable), not existing_atom?(string) do
        assert Param.cast(param(:atom), string) == :error
        refute existing_atom?(string)
      end
    end
  end

  defp param(type), do: Param.new!(:value, type)

  defp invoice_params do
    [
      Param.new!(:invoice_id, :id, required: true),
      Param.new!(:limit, :integer, default: 10),
      Param.new!(:note, :string)
    ]
  end

  defp existing_atom?(string) do
    _ = String.to_existing_atom(string)
    true
  rescue
    ArgumentError -> false
  end
end
