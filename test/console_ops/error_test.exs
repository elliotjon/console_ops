defmodule ConsoleOps.ErrorTest do
  use ExUnit.Case, async: true

  alias ConsoleOps.Error

  doctest ConsoleOps.Error

  describe "struct" do
    test "has exactly the fields reason, id, suggestion, errors and value" do
      error = %Error{reason: :unknown_command, id: "billing.refund"}

      assert error |> Map.from_struct() |> Map.keys() |> Enum.sort() ==
               [:__exception__, :errors, :id, :reason, :suggestion, :value]
    end

    test "defaults suggestion and value to nil and errors to an empty list" do
      assert %Error{reason: :unknown_command, id: "billing.refund"} ==
               %Error{
                 reason: :unknown_command,
                 id: "billing.refund",
                 suggestion: nil,
                 errors: [],
                 value: nil
               }
    end

    test "is an exception" do
      assert is_exception(%Error{reason: :unknown_command, id: "billing.refund"})
    end

    test "requires reason and id" do
      assert_raise ArgumentError, fn -> struct!(Error, reason: :unknown_command) end
      assert_raise ArgumentError, fn -> struct!(Error, id: "billing.refund") end
    end
  end

  describe "message/1 for :unknown_command" do
    test "includes the suggestion when there is one" do
      error = %Error{
        reason: :unknown_command,
        id: "billing.invoce_state",
        suggestion: "billing.invoice_state"
      }

      assert Exception.message(error) ==
               ~S|unknown command "billing.invoce_state", did you mean "billing.invoice_state"?|
    end

    test "names only the command when there is no suggestion" do
      error = %Error{reason: :unknown_command, id: "shipping.track"}

      assert Exception.message(error) == ~S|unknown command "shipping.track"|
    end
  end

  describe "message/1 for :command_failed" do
    for {value, inspected} <- [
          {:card_declined, ":card_declined"},
          {"card declined", ~S|"card declined"|}
        ] do
      message = ~s|command "billing.refund" failed: #{inspected}|

      test "inspects the failure value #{inspected}" do
        error = %Error{reason: :command_failed, id: "billing.refund", value: unquote(value)}

        assert Exception.message(error) == unquote(message)
      end
    end
  end

  describe "message/1 for :invalid_params" do
    for {name, param_error, line} <- [
          {"missing", {:missing, :invoice_id}, "missing required param :invoice_id"},
          {"duplicate", {:duplicate, :limit},
           "duplicate param :limit, each param can be given at most once"},
          {"invalid", {:invalid, :active, :boolean, "maybe"},
           ~S|invalid value for param :active, expected a value of type :boolean, got: "maybe"|},
          {"unknown atom key with a suggestion", {:unknown, :limt, :limit},
           "unknown param :limt, did you mean :limit?"},
          {"unknown atom key", {:unknown, :verbose, nil}, "unknown param :verbose"},
          {"unknown string key with a suggestion", {:unknown, "limt", :limit},
           ~S|unknown param "limt", did you mean :limit?|},
          {"unknown string key", {:unknown, "verbose", nil}, ~S|unknown param "verbose"|}
        ] do
      message = ~s|invalid params for command "billing.invoice_state":\n  * #{line}|

      test "describes a #{name} error" do
        error = %Error{
          reason: :invalid_params,
          id: "billing.invoice_state",
          errors: [unquote(Macro.escape(param_error))]
        }

        assert Exception.message(error) == unquote(message)
      end
    end

    test "lists every error on its own line, without a trailing newline" do
      error = %Error{
        reason: :invalid_params,
        id: "billing.invoice_state",
        errors: [
          {:missing, :invoice_id},
          {:duplicate, :limit},
          {:invalid, :active, :boolean, "maybe"},
          {:unknown, :limt, :limit},
          {:unknown, :verbose, nil}
        ]
      }

      assert Exception.message(error) ==
               """
               invalid params for command "billing.invoice_state":
                 * missing required param :invoice_id
                 * duplicate param :limit, each param can be given at most once
                 * invalid value for param :active, expected a value of type :boolean, got: "maybe"
                 * unknown param :limt, did you mean :limit?
                 * unknown param :verbose\
               """
    end
  end

  describe "raising" do
    test "uses message/1 as the exception message" do
      assert_raise Error, ~S|unknown command "shipping.track"|, fn ->
        raise Error, reason: :unknown_command, id: "shipping.track"
      end
    end
  end
end
