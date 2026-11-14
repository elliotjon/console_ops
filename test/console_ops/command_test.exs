defmodule ConsoleOps.CommandTest do
  use ExUnit.Case, async: true

  alias ConsoleOps.Command

  @enforced [
    id: "billing.invoice_state",
    namespace: :billing,
    name: :invoice_state,
    summary: "Inspect invoice and payment state",
    mode: :readonly
  ]

  describe "struct" do
    # Comparing the whole map also pins the field set: there is no :run or :registry key.
    test "defaults tags and params to empty lists" do
      assert Map.from_struct(struct!(Command, @enforced)) == %{
               id: "billing.invoice_state",
               namespace: :billing,
               name: :invoice_state,
               summary: "Inspect invoice and payment state",
               mode: :readonly,
               tags: [],
               params: []
             }
    end
  end
end
