# Used by "mix format"
locals_without_parens = [namespace: 2, op: 3, mode: 1, tags: 1, param: 2, param: 3, run: 1]

[
  import_deps: [:stream_data],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
