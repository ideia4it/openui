# React app on a Phoenix backend

The same programs, drawn by the official React renderer (`@openuidev/react-lang`) with an Elixir backend. The catalog lives in Elixir; the app builds its library from the `library.json` the backend serves.

| Path | What it is |
| --- | --- |
| `library.json` | The catalog spec, generated from `OpenUI.Test.ExampleLibrary` |
| `server.exs` | The backend: `GET /library.json`, `POST /chat` (streams the model's answer) and `POST /tools/:name` (answers `Query`) |
| `src/library.ts` | Builds the React library from the spec |
| `src/components.tsx` | One React component per catalog component |
| `src/main.tsx` | The chat page |
| `contract/` | Runs the official parser and this library over the same programs and compares the results |

## Run

```bash
export OPENUI_EXAMPLE_MODEL="openrouter:<provider>/<model>"   # any ReqLLM model, with its provider key set
elixir examples/react_app/server.exs

cd examples/react_app
bun install
bun run dev
```

Open http://localhost:5173 and ask "show open tickets per day as a line chart, with a table of the oldest ones and buttons for follow-up questions".

- The model's program reads the tickets with `Query("list_tickets", ...)`; the renderer calls `POST /tools/list_tickets`.
- A button with `@ToAssistant` sends the click as the renderer's event. The backend turns it into the model's text with `OpenUI.Message.from_event/1`, so both clients keep the same conversation format.
- Each finished program is printed in the backend's terminal.

Every tool is reachable without the model. Check the user's authorization in each one, as you would for any endpoint.

## The contract test

`contract/programs` holds programs that use every component, function and action of the catalog, plus mistakes, cut text and state. Both sides summarize each program at stream end, the way the official conformance runner does, and the test compares them:

```bash
MIX_ENV=test mix openui.gen.spec OpenUI.Test.ExampleLibrary --out examples/react_app/library.json --check
cd examples/react_app
elixir contract/elixir_summary.exs   # writes contract/elixir.json
bun test contract
```

Error `message` and `hint` are text for the model and are not compared; the structural fields are. The same commands run in CI.
