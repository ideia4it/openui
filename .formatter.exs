locals_without_parens = [component: 2, function: 2, action: 2, group: 2, group: 3]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "examples/**/*.exs"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
