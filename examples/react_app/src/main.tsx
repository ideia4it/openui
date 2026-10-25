import { Renderer, type ActionEvent, type Library, type OpenUIError } from "@openuidev/react-lang";
import { StrictMode, useEffect, useState, type FormEvent } from "react";
import { createRoot } from "react-dom/client";
import { renderers } from "./components";
import { buildLibrary } from "./library";
import "./styles.css";

type Turn =
  | { role: "user"; text: string }
  | { role: "user"; event: ActionEvent }
  | { role: "assistant"; text: string; streaming: boolean };

const postJson = (url: string, body: unknown) =>
  fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

// Query and Mutation call the backend; it answers with the same functions the LiveView renderer uses.
const toolProvider = {
  list_tickets: (args: Record<string, unknown>) => postJson("/tools/list_tickets", args).then((r) => r.json()),
};

function App() {
  const [library, setLibrary] = useState<Library | null>(null);
  const [turns, setTurns] = useState<Turn[]>([]);
  const [question, setQuestion] = useState("");
  const busy = turns.some((turn) => turn.role === "assistant" && turn.streaming);

  useEffect(() => {
    fetch("/library.json")
      .then((r) => r.json())
      .then((spec) => setLibrary(buildLibrary(spec, renderers)));
  }, []);

  async function ask(userTurn: Turn) {
    if (busy) return;
    const history = [...turns, userTurn];
    setTurns([...history, { role: "assistant", text: "", streaming: true }]);

    const response = await postJson("/chat", { turns: history.map(({ streaming: _s, ...turn }: any) => turn) });
    const reader = response.body!.pipeThrough(new TextDecoderStream()).getReader();
    let text = "";
    for (let chunk = await reader.read(); !chunk.done; chunk = await reader.read()) {
      text += chunk.value;
      const sofar = text;
      setTurns((all) => [...all.slice(0, -1), { role: "assistant", text: sofar, streaming: true }]);
    }
    setTurns((all) => [...all.slice(0, -1), { role: "assistant", text, streaming: false }]);
  }

  function onAction(event: ActionEvent) {
    if (event.type === "continue_conversation") ask({ role: "user", event });
    else if (event.type === "open_url") window.open(String(event.params.url), "_blank", "noopener");
    else if (event.type === "CopyToClipboard") navigator.clipboard.writeText(String(event.params.text));
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    if (!question.trim()) return;
    ask({ role: "user", text: question.trim() });
    setQuestion("");
  }

  if (!library) return <p className="muted">Loading the catalog...</p>;

  return (
    <main>
      <header>
        <h1>Support assistant</h1>
        <p className="muted">React app, official renderer, Phoenix backend.</p>
      </header>
      <div id="messages">
        {turns.map((turn, index) =>
          turn.role === "user" ? (
            <p key={index} className="user">
              {"text" in turn ? turn.text : turn.event.humanFriendlyMessage}
            </p>
          ) : (
            <div key={index} className="answer">
              <Renderer
                response={turn.text}
                library={library}
                isStreaming={turn.streaming}
                toolProvider={toolProvider}
                onAction={onAction}
                onError={(errors: OpenUIError[]) => errors.length && console.info("program errors", errors)}
              />
              {turn.streaming && !turn.text && <p className="muted">Thinking...</p>}
            </div>
          ),
        )}
      </div>
      <form id="question-form" className="composer" onSubmit={submit}>
        <input
          value={question}
          onChange={(event) => setQuestion(event.target.value)}
          placeholder="Ask about the tickets"
          disabled={busy}
        />
        <button type="submit" disabled={busy}>
          Send
        </button>
      </form>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
