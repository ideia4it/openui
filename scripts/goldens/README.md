# Reference prompts

Generates `test/fixtures/goldens/` with the official `@openuidev/lang-core`: the system prompt for each case in `cases.mjs`, the LibrarySpec of the example catalog, and `cases.json`. The Elixir tests compare against these files; CI does not regenerate them.

```bash
bun install
OPENUI_TELEMETRY_DISABLED=1 bun run generate.mjs
```

`example-library.mjs` mirrors `test/support/example_library.ex`. Change both together.
