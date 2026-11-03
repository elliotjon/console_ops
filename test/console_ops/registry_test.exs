defmodule ConsoleOps.RegistryTest.Handler do
  @spec invoice_state(term(), term()) :: {:handled, term(), term()}
  def invoice_state(params, ctx), do: {:handled, params, ctx}
end

defmodule ConsoleOps.RegistryTest.AliasA.Handler do
  @spec invoice_state(term(), term()) :: {:alias_a, term(), term()}
  def invoice_state(params, ctx), do: {:alias_a, params, ctx}
end

defmodule ConsoleOps.RegistryTest.AliasB.Handler do
  @spec invoice_state(term(), term()) :: {:alias_b, term(), term()}
  def invoice_state(params, ctx), do: {:alias_b, params, ctx}
end

defmodule ConsoleOps.RegistryTest do
  use ExUnit.Case, async: true

  alias ConsoleOps.Command
  alias ConsoleOps.Param

  # Fixtures are compiled from strings under this made-up file name, so a
  # CompileError can be checked for the file and line of the faulty DSL call.
  # Asserted lines are lines of the fixture string, where line 1 is the defmodule.
  @fixture "test/registry_fixture.ex"

  @params %{invoice_id: 42}
  @ctx %{actor: "support"}

  describe "__console_ops__(:commands)" do
    test "is empty for a registry without ops" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
        end
        """)

      assert registry.__console_ops__(:commands) == []
      assert Enum.sort(registry.__info__(:functions)) == [__console_ops__: 1]
    end

    test "is empty for an empty namespace block" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
          end
        end
        """)

      assert registry.__console_ops__(:commands) == []
    end

    test "a registry with an op defines only the two __console_ops__ functions" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, _ctx -> params end
            end
          end
        end
        """)

      assert Enum.sort(registry.__info__(:functions)) == [__console_ops__: 1, __console_ops__: 4]
    end

    test "builds a command from each op" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              tags [:support, :incident]
              param :invoice_id, :id, required: true, doc: "The invoice to inspect"
              param :limit, :integer, default: 10
              run fn params, _ctx -> params end
            end
          end

          namespace :accounts do
            op :unlock, "Unlock a user account" do
              mode :mutation
              run fn params, _ctx -> params end
            end

            op :delete, "Delete a user account" do
              mode :destructive
              run fn params, _ctx -> params end
            end
          end
        end
        """)

      assert registry.__console_ops__(:commands) == [
               struct!(Command,
                 id: "billing.invoice_state",
                 namespace: :billing,
                 name: :invoice_state,
                 summary: "Inspect invoice and payment state",
                 mode: :readonly,
                 tags: [:support, :incident],
                 params: [
                   Param.new!(:invoice_id, :id, required: true, doc: "The invoice to inspect"),
                   Param.new!(:limit, :integer, default: 10)
                 ]
               ),
               struct!(Command,
                 id: "accounts.unlock",
                 namespace: :accounts,
                 name: :unlock,
                 summary: "Unlock a user account",
                 mode: :mutation,
                 tags: [],
                 params: []
               ),
               struct!(Command,
                 id: "accounts.delete",
                 namespace: :accounts,
                 name: :delete,
                 summary: "Delete a user account",
                 mode: :destructive,
                 tags: [],
                 params: []
               )
             ]
    end

    # Neither alphabetical order nor grouping by namespace gives this order.
    test "lists commands in declaration order, across namespaces and repeated namespace blocks" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :refund, "Refund an invoice" do
              mode :mutation
              run fn params, _ctx -> params end
            end

            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, _ctx -> params end
            end
          end

          namespace :accounts do
            op :unlock, "Unlock a user account" do
              mode :mutation
              run fn params, _ctx -> params end
            end
          end

          namespace :billing do
            op :void, "Void an invoice" do
              mode :destructive
              run fn params, _ctx -> params end
            end
          end
        end
        """)

      assert Enum.map(registry.__console_ops__(:commands), & &1.id) ==
               ["billing.refund", "billing.invoice_state", "accounts.unlock", "billing.void"]
    end

    test "accepts a module attribute as a param default" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          @default_limit 10

          namespace :billing do
            op :invoices, "List recent invoices" do
              mode :readonly
              param :limit, :integer, default: @default_limit
              run fn params, _ctx -> params end
            end
          end
        end
        """)

      assert [%{params: [param]}] = registry.__console_ops__(:commands)
      assert param == Param.new!(:limit, :integer, default: 10)
    end

    test "accepts namespace and op names with digits and underscores" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing_v2 do
            op :refund_2, "Refund an invoice" do
              mode :mutation
              run fn params, _ctx -> params end
            end
          end
        end
        """)

      assert [%{id: "billing_v2.refund_2"}] = registry.__console_ops__(:commands)
    end
  end

  describe "__console_ops__(:run, id, params, ctx)" do
    test "calls the fn of the op with the given id, passing params and ctx unchanged" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, ctx -> {:invoice_state, params, ctx} end
            end

            op :refund, "Refund an invoice" do
              mode :mutation
              run fn params, ctx -> {:refund, params, ctx} end
            end
          end
        end
        """)

      assert registry.__console_ops__(:run, "billing.invoice_state", @params, @ctx) ==
               {:invoice_state, @params, @ctx}

      assert registry.__console_ops__(:run, "billing.refund", @params, @ctx) ==
               {:refund, @params, @ctx}
    end

    test "calls a remote capture, resolving aliases" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          alias ConsoleOps.RegistryTest.Handler

          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run &Handler.invoice_state/2
            end
          end
        end
        """)

      assert registry.__console_ops__(:run, "billing.invoice_state", @params, @ctx) ==
               {:handled, @params, @ctx}
    end

    # The alias is rebound before the module ends. Resolving it there instead of where
    # the op is declared would call AliasB.Handler from "a.invoice_state" and leave the
    # first alias unused.
    test "a remote capture resolves aliases where the op is declared, not at the end of the module" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          alias ConsoleOps.RegistryTest.AliasA.Handler
          namespace :a do
            op :invoice_state, "Inspect invoice in A" do
              mode :readonly
              run &Handler.invoice_state/2
            end
          end

          alias ConsoleOps.RegistryTest.AliasB.Handler
          namespace :b do
            op :invoice_state, "Inspect invoice in B" do
              mode :readonly
              run &Handler.invoice_state/2
            end
          end
        end
        """)

      assert registry.__console_ops__(:run, "a.invoice_state", @params, @ctx) ==
               {:alias_a, @params, @ctx}

      assert registry.__console_ops__(:run, "b.invoice_state", @params, @ctx) ==
               {:alias_b, @params, @ctx}
    end

    test "a fn body resolves aliases where the op is declared, not at the end of the module" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          alias ConsoleOps.RegistryTest.AliasA.Handler
          namespace :a do
            op :invoice_state, "Inspect invoice in A" do
              mode :readonly
              run fn params, ctx -> Handler.invoice_state(params, ctx) end
            end
          end

          alias ConsoleOps.RegistryTest.AliasB.Handler
          namespace :b do
            op :invoice_state, "Inspect invoice in B" do
              mode :readonly
              run fn params, ctx -> Handler.invoice_state(params, ctx) end
            end
          end
        end
        """)

      assert registry.__console_ops__(:run, "a.invoice_state", @params, @ctx) ==
               {:alias_a, @params, @ctx}

      assert registry.__console_ops__(:run, "b.invoice_state", @params, @ctx) ==
               {:alias_b, @params, @ctx}
    end

    test "a fn body resolves imports where the op is declared, not at the end of the module" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          import String, only: [upcase: 1]
          namespace :a do
            op :up, "Upcase the name" do
              mode :readonly
              run fn p, _c -> upcase(p.name) end
            end
          end

          import String, only: [downcase: 1]
          namespace :b do
            op :down, "Downcase the name" do
              mode :readonly
              run fn p, _c -> downcase(p.name) end
            end
          end
        end
        """)

      assert registry.__console_ops__(:run, "a.up", %{name: "Ada"}, @ctx) == "ADA"
      assert registry.__console_ops__(:run, "b.down", %{name: "Ada"}, @ctx) == "ada"
    end

    test "calls a local capture of a private function" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run &invoice_state/2
            end
          end

          defp invoice_state(params, ctx), do: {:local, params, ctx}
        end
        """)

      assert registry.__console_ops__(:run, "billing.invoice_state", @params, @ctx) ==
               {:local, @params, @ctx}
    end

    test "picks the matching clause of a multi-clause fn" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn
                %{invoice_id: id}, _ctx when is_integer(id) -> {:integer, id}
                %{invoice_id: id}, _ctx -> {:other, id}
              end
            end
          end
        end
        """)

      run = &registry.__console_ops__(:run, "billing.invoice_state", &1, @ctx)
      assert run.(%{invoice_id: 42}) == {:integer, 42}
      assert run.(%{invoice_id: "inv_42"}) == {:other, "inv_42"}
    end
  end

  # compile_registry!/1 asserts there are no diagnostics, so each of these
  # fails on any warning the generated code would add to a user's build.
  describe "compiling without warnings" do
    test "a private helper defined between namespace blocks and called from run fns" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, _ctx -> tag(params) end
            end
          end

          defp tag(params), do: {:tagged, params}

          namespace :accounts do
            op :unlock, "Unlock a user account" do
              mode :mutation
              run fn params, _ctx -> tag(params) end
            end
          end
        end
        """)

      assert registry.__console_ops__(:run, "billing.invoice_state", @params, @ctx) ==
               {:tagged, @params}

      assert registry.__console_ops__(:run, "accounts.unlock", @params, @ctx) ==
               {:tagged, @params}
    end

    test "a module attribute read inside a run fn has the value it had where the op is declared" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          @greeting "first"
          namespace :billing do
            op :a, "Say the first greeting" do
              mode :readonly
              run fn _params, _ctx -> @greeting end
            end
          end

          @greeting "second"
          namespace :accounts do
            op :b, "Say the second greeting" do
              mode :readonly
              run fn _params, _ctx -> @greeting end
            end
          end
        end
        """)

      assert registry.__console_ops__(:run, "billing.a", @params, @ctx) == "first"
      assert registry.__console_ops__(:run, "accounts.b", @params, @ctx) == "second"
    end

    # use ConsoleOps.Registry must not import run/1, or this would conflict.
    test "a registry that defines its own run/1" do
      registry =
        compile_registry!("""
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, _ctx -> params end
            end
          end

          def run(value), do: {:own_run, value}
        end
        """)

      assert registry.run(:x) == {:own_run, :x}
      assert registry.__console_ops__(:run, "billing.invoice_state", @params, @ctx) == @params
    end
  end

  describe "warnings in user code" do
    test "an unused variable in a run fn is reported at its own line" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
            run fn params, _ctx ->
              unused = 1
              params
            end
          end
        end
      end
      """

      assert [%{severity: :warning, file: file, position: position, message: message}] =
               compile_diagnostics(code)

      assert file == @fixture
      assert line_of(position) == 7
      assert message =~ ~S(variable "unused" is unused)
    end
  end

  describe "namespace and op placement errors" do
    test "rejects an op outside a namespace" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        op :invoice_state, "Inspect invoice and payment state" do
          mode :readonly
          run fn params, _ctx -> params end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 3, "op :invoice_state must be defined inside a namespace block"}
    end

    test "rejects a nested namespace" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          namespace :admin do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, _ctx -> params end
            end
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 4,
                "namespace :admin cannot be nested inside namespace :billing, namespaces do not nest"}
    end

    test "rejects a call other than op inside a namespace" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          mode :readonly
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 4, "unknown call mode/1 in namespace :billing, expected op/3"}
    end
  end

  describe "name and id errors" do
    for source <- [~S("billing"), "Billing", ":Billing", ~S(:"my-ns"), ~S(:"a.b"), "nil"] do
      message =
        "invalid namespace name: expected a lowercase snake_case atom such as :billing, " <>
          "got: #{source}"

      test "rejects #{source} as a namespace name" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace #{unquote(source)} do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 3, unquote(message)}
      end
    end

    # Names must be literal atoms, even when an attribute holds a valid one.
    test "rejects a module attribute as a namespace name" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        @ns :billing
        namespace @ns do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 4,
                "invalid namespace name: expected a lowercase snake_case atom such as :billing, " <>
                  "got: @ns"}
    end

    for source <- [
          ~S("invoice_state"),
          "InvoiceState",
          ":InvoiceState",
          ~S(:"invoice-state"),
          ~S(:"invoice.state"),
          "nil"
        ] do
      message =
        "invalid op name in namespace :billing: expected a lowercase snake_case atom " <>
          "such as :invoice_state, got: #{source}"

      test "rejects #{source} as an op name" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op #{unquote(source)}, "Inspect invoice and payment state" do
              mode :readonly
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 4, unquote(message)}
      end
    end

    test "rejects a module attribute as an op name" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        @name :invoice_state
        namespace :billing do
          op @name, "Inspect invoice and payment state" do
            mode :readonly
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 5,
                "invalid op name in namespace :billing: expected a lowercase snake_case atom " <>
                  "such as :invoice_state, got: @name"}
    end

    test "rejects a duplicate op id in the same namespace block" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
            run fn params, _ctx -> params end
          end
          op :invoice_state, "Inspect invoice state again" do
            mode :readonly
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 8,
                ~S(duplicate op "billing.invoice_state", op ids must be unique within a registry)}
    end

    test "rejects a duplicate op id across two blocks of the same namespace" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
            run fn params, _ctx -> params end
          end
        end
        namespace :billing do
          op :invoice_state, "Inspect invoice state again" do
            mode :readonly
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 10,
                ~S(duplicate op "billing.invoice_state", op ids must be unique within a registry)}
    end
  end

  describe "op arguments errors" do
    @op_shape_message "op :invoice_state in namespace :billing expects a summary and a do block, " <>
                        ~S(such as: op :invoice_state, "Summary" do ... end)

    test "rejects an op without a summary" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state do
            mode :readonly
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert compile_error(code) == {@fixture, 4, @op_shape_message}
    end

    test "rejects an op without a do block" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state"
        end
      end
      """

      assert compile_error(code) == {@fixture, 4, @op_shape_message}
    end

    for source <- [":inspect", ~S(""), ~S("  "), "nil"] do
      message =
        ~S(invalid summary for op "billing.invoice_state": expected a non-blank string, ) <>
          "got: #{source}"

      test "rejects #{source} as a summary" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, #{unquote(source)} do
              mode :readonly
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 4, unquote(message)}
      end
    end
  end

  describe "missing, repeated and unknown calls in an op" do
    test "rejects an op without mode" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 4,
                ~S(op "billing.invoice_state" is missing mode, ) <>
                  "add one of: mode :readonly, mode :mutation, mode :destructive"}
    end

    test "rejects an op without run" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 4,
                ~S(op "billing.invoice_state" is missing run, ) <>
                  "add run fn params, ctx -> ... end or run &Mod.fun/2"}
    end

    for {call, repeated} <- [
          mode: "mode :mutation",
          tags: "tags [:incident]",
          run: "run fn _params, _ctx -> :ok end"
        ] do
      message =
        ~s(duplicate #{call} for op "billing.invoice_state", #{call} can be given at most once)

      test "rejects #{call} given twice" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              tags [:support]
              run fn params, _ctx -> params end
              #{unquote(repeated)}
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 8, unquote(message)}
      end
    end

    for {source, call} <- [
          {~S(description "Shows the invoice and its payments"), "description/1"},
          {"param :invoice_id", "param/1"}
        ] do
      message =
        ~s(unknown call #{call} in op "billing.invoice_state", ) <>
          "expected one of: mode/1, tags/1, param/2, param/3, run/1"

      test "rejects #{call} inside an op" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              #{unquote(source)}
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 6, unquote(message)}
      end
    end
  end

  describe "unknown and unexpected expressions" do
    @expected_in_op "expected one of: mode/1, tags/1, param/2, param/3, run/1"

    for {source, call} <- [
          {"IO.inspect(:debug)", "IO.inspect/1"},
          {":lists.reverse([])", ":lists.reverse/1"}
        ] do
      message = ~s(unknown call #{call} in op "billing.invoice_state", ) <> @expected_in_op

      test "rejects the remote call #{call} inside an op" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              #{unquote(source)}
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 6, unquote(message)}
      end
    end

    # Literals carry no line metadata, so the error points at the op; expressions
    # with metadata point at their own line.
    for {source, rendered, line} <- [
          {"42", "42", 4},
          {":debug", ":debug", 4},
          {~S("text"), ~S("text"), 4},
          {"{:a, :b}", "{:a, :b}", 4},
          {"x", "x", 6},
          {"f.(1)", "f.(1)", 6}
        ] do
      message =
        "unexpected expression #{rendered} in op \"billing.invoice_state\", " <> @expected_in_op

      test "rejects the expression #{source} inside an op" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              #{unquote(source)}
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, unquote(line), unquote(message)}
      end
    end

    test "rejects an op given as a keyword do: nil" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state", do: nil
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 4,
                ~s(unexpected expression nil in op "billing.invoice_state", ) <> @expected_in_op}
    end

    test "rejects a remote call inside a namespace" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          IO.inspect(:debug)
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 4, "unknown call IO.inspect/1 in namespace :billing, expected op/3"}
    end

    test "rejects a literal inside a namespace" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          42
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 3, "unexpected expression 42 in namespace :billing, expected op/3"}
    end

    test "rejects a namespace given as a keyword do: nil" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing, do: nil
      end
      """

      assert compile_error(code) ==
               {@fixture, 3, "unexpected expression nil in namespace :billing, expected op/3"}
    end
  end

  describe "mode and tags errors" do
    # String.jaro_distance/2 to the closest mode: "read_only" 0.96, "read" 0.83 and
    # "mutate" 0.82, above the 0.8 threshold; "destroy" 0.72, below it.
    for {source, suggestion} <- [
          {":read_only", ":readonly"},
          {":read", ":readonly"},
          {":mutate", ":mutation"}
        ] do
      message =
        ~s(unknown mode #{source} for op "billing.invoice_state", did you mean #{suggestion}?)

      test "rejects mode #{source}, suggesting #{suggestion}" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode #{unquote(source)}
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 5, unquote(message)}
      end
    end

    for source <- [":destroy", ~S("readonly")] do
      message =
        ~s(unknown mode #{source} for op "billing.invoice_state", ) <>
          "supported modes are: [:readonly, :mutation, :destructive]"

      test "rejects mode #{source}, listing the supported modes" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode #{unquote(source)}
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 5, unquote(message)}
      end
    end

    for source <- [
          ":support",
          ~S("support"),
          ~S([:support, "incident"]),
          "[:support | :incident]"
        ] do
      message =
        ~S(invalid tags for op "billing.invoice_state": expected a list of atoms, ) <>
          "got: #{source}"

      test "rejects tags #{source}" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              tags #{unquote(source)}
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 6, unquote(message)}
      end
    end
  end

  describe "run errors" do
    for source <- [
          "fn p -> p end",
          "fn -> :ok end",
          "&MyApp.Ops.f/1",
          "&f/3",
          "{Mod, :f}",
          "&f(&1, &2)",
          ":atom"
        ] do
      message =
        ~S(invalid run for op "billing.invoice_state": ) <>
          "expected fn params, ctx -> ... end, &fun/2 or &Mod.fun/2, got: #{source}"

      test "rejects run #{source}" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              run #{unquote(source)}
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 6, unquote(message)}
      end
    end
  end

  describe "param errors" do
    test "rejects a param declared twice" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
            param :invoice_id, :id
            param :invoice_id, :integer
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert compile_error(code) ==
               {@fixture, 7,
                ~S(duplicate param :invoice_id for op "billing.invoice_state", ) <>
                  "each param can be declared at most once"}
    end

    test "rejects a param default that cannot be stored in compiled code" do
      code = """
      defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
        use ConsoleOps.Registry
        namespace :billing do
          op :invoice_state, "Inspect invoice and payment state" do
            mode :readonly
            param :callback, :any, default: fn -> :ok end
            run fn params, _ctx -> params end
          end
        end
      end
      """

      assert {@fixture, 6, description} = compile_error(code)

      assert description =~
               ~r/\Ainvalid value for :default option of param :callback: expected a value that can be stored in compiled code, got: #Function</
    end

    # The description is the ArgumentError message of ConsoleOps.Param.new!/3, word for word.
    for {source, message} <- [
          {"param :invoice_id, :int",
           "unknown type :int for param :invoice_id, did you mean :integer?"},
          {"param :amount, :float",
           "unknown type :float for param :amount, " <>
             "supported types are: [:string, :integer, :boolean, :atom, :id, :map, :any]"},
          {~S(param "amount", :integer),
           ~S(invalid param name: expected an atom other than nil, got: "amount")},
          {"param :amount, :integer, requird: true",
           "unknown options [:requird] for param :amount, " <>
             "valid options are: [:required, :default, :doc]"},
          {"param :amount, :integer, required: true, default: 5",
           "invalid value for :default option of param :amount: " <>
             "a required param cannot have a default, got: 5"}
        ] do
      test "reports the param error for #{source}" do
        code = """
        defmodule ConsoleOps.RegistryTest.Fixture#{System.unique_integer([:positive])} do
          use ConsoleOps.Registry
          namespace :billing do
            op :invoice_state, "Inspect invoice and payment state" do
              mode :readonly
              #{unquote(source)}
              run fn params, _ctx -> params end
            end
          end
        end
        """

        assert compile_error(code) == {@fixture, 6, unquote(message)}
      end
    end
  end

  # Diagnostics are captured, so a warning fails a test instead of only
  # printing to stderr.
  defp compile(code) do
    Code.with_diagnostics(fn ->
      try do
        {:ok, Code.compile_string(code, @fixture)}
      rescue
        error in CompileError -> {:error, error}
      end
    end)
  end

  defp compile_registry!(code) do
    assert {{:ok, [{registry, _binary}]}, []} = compile(code)
    registry
  end

  defp compile_diagnostics(code) do
    assert {{:ok, _modules}, diagnostics} = compile(code)
    diagnostics
  end

  # The position of a diagnostic is a line or a {line, column} tuple, by Elixir version.
  defp line_of({line, _column}), do: line
  defp line_of(line) when is_integer(line), do: line

  # DSL errors are raised, not logged, so a failing fixture has no diagnostics either.
  defp compile_error(code) do
    assert {{:error, %CompileError{} = error}, []} = compile(code)
    {error.file, error.line, error.description}
  end
end
