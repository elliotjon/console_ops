%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/", "mix.exs"]
      },
      checks: %{
        extra: [
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.Specs, files: %{excluded: ["mix.exs"]}},
          {Credo.Check.Readability.StrictModuleLayout, []},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {Credo.Check.Warning.UnsafeToAtom, []}
        ]
      }
    }
  ]
}
