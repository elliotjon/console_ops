defmodule ConsoleOps.RunnerTest.Handlers do
  @spec invoice_state(map(), map()) :: {:ok, {map(), map()}}
  def invoice_state(params, ctx) do
    send(self(), {:called, params, ctx})
    {:ok, {params, ctx}}
  end

  @spec refund(map(), map()) :: {:error, :card_declined}
  def refund(_params, _ctx), do: {:error, :card_declined}

  @spec bad(map(), map()) :: 42
  def bad(_params, _ctx), do: 42

  @spec ok_atom(map(), map()) :: :ok
  def ok_atom(_params, _ctx), do: :ok

  @spec boom(map(), map()) :: no_return()
  def boom(_params, _ctx), do: raise("boom")

  @spec echo(map(), map()) :: term()
  def echo(params, _ctx), do: params.value
end

defmodule ConsoleOps.RunnerTest.Console do
  use ConsoleOps.Registry

  alias ConsoleOps.RunnerTest.Handlers

  namespace :billing do
    op :invoice_state, "Inspect invoice and payment state" do
      mode :readonly
      param :invoice_id, :id, required: true
      param :limit, :integer, default: 10
      run &Handlers.invoice_state/2
    end

    op :refund, "Refund an invoice" do
      mode :mutation
      run &Handlers.refund/2
    end

    op :bad, "Return a value outside the handler contract" do
      mode :readonly
      run &Handlers.bad/2
    end

    op :ok_atom, "Return a bare :ok" do
      mode :readonly
      run &Handlers.ok_atom/2
    end

    op :boom, "Raise" do
      mode :readonly
      run &Handlers.boom/2
    end

    op :echo, "Return the :value param as the handler result" do
      mode :readonly
      param :value, :any
      run &Handlers.echo/2
    end
  end
end

defmodule ConsoleOps.RunnerTest.Empty do
  use ConsoleOps.Registry
end

defmodule ConsoleOps.RunnerTest.Point do
  defstruct [:x]
end

defmodule ConsoleOps.RunnerTest do
  use ExUnit.Case, async: true

  alias ConsoleOps.Error
  alias ConsoleOps.Runner
  alias ConsoleOps.RunnerTest.Console
  alias ConsoleOps.RunnerTest.Empty
  alias ConsoleOps.RunnerTest.Handlers
  alias ConsoleOps.RunnerTest.Point

  @invoice_state "billing.invoice_state"
  @invoice_result {%{invoice_id: 42, limit: 10}, %{}}

  describe "run/3 and run!/3 success" do
    test "casts the params, applies defaults and passes an empty ctx to the handler" do
      assert Runner.run(Console, @invoice_state, invoice_id: "42") == {:ok, @invoice_result}
      assert_received {:called, params, ctx}
      assert params == %{invoice_id: 42, limit: 10}
      assert ctx == %{}
    end

    test "accepts the id as an atom" do
      assert Runner.run(Console, :"billing.invoice_state", invoice_id: "42") ==
               {:ok, @invoice_result}
    end

    for {shape, params} <- [
          {"a keyword list", [invoice_id: 42]},
          {"a map with atom keys", %{invoice_id: 42}},
          {"a map with string keys", %{"invoice_id" => 42}},
          {"a list mixing atom and string keys", [{:invoice_id, 42}, {"limit", 10}]}
        ] do
      test "accepts params as #{shape}" do
        assert Runner.run(Console, @invoice_state, unquote(Macro.escape(params))) ==
                 {:ok, @invoice_result}
      end
    end

    test "run! returns the unwrapped result" do
      assert Runner.run!(Console, @invoice_state, invoice_id: 42) == @invoice_result
    end
  end

  describe "handler return contract" do
    test "unwraps {:ok, value}" do
      assert Runner.run(Console, "billing.echo", value: {:ok, 7}) == {:ok, 7}
      assert Runner.run!(Console, "billing.echo", value: {:ok, 7}) == 7
    end

    test "returns a bare :ok as {:ok, :ok}" do
      assert Runner.run(Console, "billing.ok_atom", []) == {:ok, :ok}
      assert Runner.run!(Console, "billing.ok_atom", []) == :ok
    end

    test "returns {:error, reason} as a :command_failed error" do
      assert {:error, %Error{} = error} = Runner.run(Console, "billing.refund", [])

      assert error == %Error{
               reason: :command_failed,
               id: "billing.refund",
               value: :card_declined,
               suggestion: nil,
               errors: []
             }
    end

    test "run! raises the :command_failed error that run returns" do
      assert {:error, error} = Runner.run(Console, "billing.refund", [])

      assert assert_raise(Error, fn -> Runner.run!(Console, "billing.refund", []) end) == error
    end

    test "raises when the handler returns a value outside the contract" do
      message =
        ~S|expected command "billing.bad" to return :ok, {:ok, value} or {:error, reason}, | <>
          "got: 42"

      assert_raise RuntimeError, message, fn -> Runner.run(Console, "billing.bad", []) end
      assert_raise RuntimeError, message, fn -> Runner.run!(Console, "billing.bad", []) end
    end

    for {name, value, inspected} <- [
          {"a bare :error", :error, ":error"},
          {"nil", nil, "nil"},
          {"a 3-tuple", {:ok, 1, 2}, "{:ok, 1, 2}"},
          {"a string", "ok", ~S|"ok"|}
        ] do
      message =
        ~S|expected command "billing.echo" to return :ok, {:ok, value} or {:error, reason}, | <>
          "got: #{inspected}"

      test "raises when the handler returns #{name}" do
        assert_raise RuntimeError, unquote(message), fn ->
          Runner.run(Console, "billing.echo", value: unquote(Macro.escape(value)))
        end

        assert_raise RuntimeError, unquote(message), fn ->
          Runner.run!(Console, "billing.echo", value: unquote(Macro.escape(value)))
        end
      end
    end
  end

  describe "a raising handler" do
    test "run re-raises the handler's exception" do
      assert_raise RuntimeError, "boom", fn -> Runner.run(Console, "billing.boom", []) end
    end

    test "run! re-raises the handler's exception" do
      assert_raise RuntimeError, "boom", fn -> Runner.run!(Console, "billing.boom", []) end
    end

    # Rescuing and raising again (`raise e`) in the Runner would replace the handler's
    # stacktrace with one starting in the Runner; the handler frame must come first.
    test "keeps the handler's frame ahead of any Runner frame in the stacktrace" do
      for call <- [&Runner.run/3, &Runner.run!/3] do
        stacktrace =
          try do
            call.(Console, "billing.boom", [])
          rescue
            RuntimeError -> __STACKTRACE__
          end

        handler = Enum.find_index(stacktrace, &match?({Handlers, :boom, 2, _}, &1))
        runner = Enum.find_index(stacktrace, &match?({Runner, _, _, _}, &1))

        assert handler != nil
        assert runner == nil or handler < runner
      end
    end
  end

  # String.jaro_distance/2 over the full id: "billing.invoce_state" scores 0.984 against
  # "billing.invoice_state" and at most 0.792 against the others, so the typo is
  # suggested. "shipping.track" scores at most 0.66 against any id, so nothing is.
  describe "unknown command" do
    test "suggests the closest id" do
      assert Runner.run(Console, "billing.invoce_state", []) ==
               {:error,
                %Error{
                  reason: :unknown_command,
                  id: "billing.invoce_state",
                  suggestion: "billing.invoice_state",
                  errors: [],
                  value: nil
                }}
    end

    test "reports an atom id as a string" do
      assert {:error, %Error{id: "billing.invoce_state"}} =
               Runner.run(Console, :"billing.invoce_state", [])
    end

    test "gives no suggestion when no id is close enough" do
      assert Runner.run(Console, "shipping.track", []) ==
               {:error,
                %Error{
                  reason: :unknown_command,
                  id: "shipping.track",
                  suggestion: nil,
                  errors: [],
                  value: nil
                }}
    end

    test "gives no suggestion for a registry without ops" do
      assert {:error, %Error{reason: :unknown_command, suggestion: nil}} =
               Runner.run(Empty, @invoice_state, [])
    end

    test "does not look at the params, and does not call any handler" do
      assert {:error, %Error{reason: :unknown_command}} =
               Runner.run(Console, "billing.invoce_state", limit: "ten", limt: 5)

      refute_received {:called, _params, _ctx}
    end

    test "does not create an atom for the unknown id" do
      id = "billing.x#{System.unique_integer([:positive])}"

      assert {:error, %Error{reason: :unknown_command, id: ^id}} = Runner.run(Console, id, [])
      assert_raise ArgumentError, fn -> String.to_existing_atom(id) end
    end

    # "nil" scores at most 0.616 against the fixture ids, so there is no suggestion.
    test "treats the atom nil as the id \"nil\"" do
      assert Runner.run(Console, nil, []) ==
               {:error,
                %Error{
                  reason: :unknown_command,
                  id: "nil",
                  suggestion: nil,
                  errors: [],
                  value: nil
                }}
    end
  end

  describe "invalid params" do
    test "returns every param error and does not call the handler" do
      assert Runner.run(Console, @invoice_state, limit: "ten", limt: 5) ==
               {:error,
                %Error{
                  reason: :invalid_params,
                  id: @invoice_state,
                  errors: [
                    {:missing, :invoice_id},
                    {:invalid, :limit, :integer, "ten"},
                    {:unknown, :limt, :limit}
                  ],
                  suggestion: nil,
                  value: nil
                }}

      refute_received {:called, _params, _ctx}
    end
  end

  describe "run!/3 raises the error that run/3 returns" do
    for {name, id, params} <- [
          {"unknown command with a suggestion", "billing.invoce_state", []},
          {"unknown command without a suggestion", "shipping.track", []},
          {"invalid params", "billing.invoice_state", [limit: "ten"]},
          {"command failed", "billing.refund", []}
        ] do
      test "for #{name}" do
        assert {:error, error} = Runner.run(Console, unquote(id), unquote(params))

        assert assert_raise(Error, fn -> Runner.run!(Console, unquote(id), unquote(params)) end) ==
                 error
      end
    end
  end

  describe "programmer errors" do
    # Passed through the test context so Elixir 1.20's type checker doesn't reject the literal.
    for registry <- [Enum, ConsoleOps.RunnerTest.Missing, "MyApp.Console", nil] do
      message =
        "expected a module that uses ConsoleOps.Registry, got: #{inspect(registry)}"

      @tag registry: registry
      test "raises for the registry #{inspect(registry)}", %{registry: registry} do
        assert_raise ArgumentError, unquote(message), fn ->
          Runner.run(registry, @invoice_state, [])
        end

        assert_raise ArgumentError, unquote(message), fn ->
          Runner.run!(registry, @invoice_state, [])
        end
      end
    end

    # In `iex -S mix` a registry is often not loaded yet, and function_exported?/3 is
    # false for an unloaded module, so the Runner must load it before checking.
    @tag :tmp_dir
    test "accepts a registry that is compiled but not loaded yet", %{tmp_dir: dir} do
      [{registry, beam}] =
        Code.compile_string("""
        defmodule ConsoleOps.RunnerTest.Lazy#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry

          namespace :a do
            op :b, "Return one" do
              mode :readonly
              run fn _params, _ctx -> {:ok, 1} end
            end
          end
        end
        """)

      File.write!(Path.join(dir, "#{registry}.beam"), beam)
      :code.delete(registry)
      :code.purge(registry)
      true = :code.add_patha(String.to_charlist(dir))
      on_exit(fn -> :code.del_path(String.to_charlist(dir)) end)

      assert :code.is_loaded(registry) == false
      assert function_exported?(registry, :__console_ops__, 1) == false

      assert Runner.run(registry, "a.b", []) == {:ok, 1}
    end

    # Passed through the test context so Elixir 1.20's type checker doesn't reject the literal.
    @tag id: 42
    test "raises FunctionClauseError for an id that is neither a string nor an atom", %{id: id} do
      assert_raise FunctionClauseError, fn -> Runner.run(Console, id, []) end
      assert_raise FunctionClauseError, fn -> Runner.run!(Console, id, []) end
    end

    test "raises ArgumentError for a struct as params" do
      message =
        "expected input to be a map or a list of {key, value} pairs, " <>
          "got a struct: %ConsoleOps.RunnerTest.Point{x: 1}"

      assert_raise ArgumentError, message, fn ->
        Runner.run(Console, @invoice_state, %Point{x: 1})
      end

      assert_raise ArgumentError, message, fn ->
        Runner.run!(Console, @invoice_state, %Point{x: 1})
      end
    end

    # Passed through the test context so Elixir 1.20's type checker doesn't reject the literal.
    @tag params: nil
    test "raises FunctionClauseError from run/3 for nil params and a known id", %{params: params} do
      error =
        assert_raise FunctionClauseError, fn -> Runner.run(Console, @invoice_state, params) end

      assert {error.module, error.function, error.arity} == {Runner, :run, 3}

      error =
        assert_raise FunctionClauseError, fn -> Runner.run!(Console, @invoice_state, params) end

      assert {error.module, error.function, error.arity} == {Runner, :run, 3}
    end

    # Passed through the test context so Elixir 1.20's type checker doesn't reject the literal.
    @tag params: nil
    test "raises FunctionClauseError from run/3 for nil params and an unknown id", %{
      params: params
    } do
      error =
        assert_raise FunctionClauseError, fn -> Runner.run(Console, "shipping.track", params) end

      assert {error.module, error.function, error.arity} == {Runner, :run, 3}

      error =
        assert_raise FunctionClauseError, fn -> Runner.run!(Console, "shipping.track", params) end

      assert {error.module, error.function, error.arity} == {Runner, :run, 3}
    end

    # An unknown id is reported before params are looked at.
    @tag params: %Point{x: 1}
    test "returns :unknown_command for a struct as params and an unknown id", %{params: params} do
      assert Runner.run(Console, "shipping.track", params) ==
               {:error,
                %Error{
                  reason: :unknown_command,
                  id: "shipping.track",
                  suggestion: nil,
                  errors: [],
                  value: nil
                }}
    end
  end
end
