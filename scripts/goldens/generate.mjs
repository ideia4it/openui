// Writes the reference prompts and the example LibrarySpec the Elixir tests
// compare against. Run: OPENUI_TELEMETRY_DISABLED=1 bun run generate.mjs
import fs from "node:fs";
import path from "node:path";
import { generateSystemPrompt } from "@openuidev/lang-core";
import { cases } from "./cases.mjs";
import { exampleSpec } from "./example-library.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const out = path.join(root, "test/fixtures/goldens");
const fixturesSpec = JSON.parse(
  fs.readFileSync(path.join(root, "test/fixtures/openui-spec/library.json"), "utf8"),
);

fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, "example.spec.json"), JSON.stringify(exampleSpec, null, 2) + "\n");

for (const { name, library, options } of cases) {
  const spec = library === "fixtures" ? fixturesSpec : exampleSpec;
  const prompt = generateSystemPrompt({ library: spec, promptOptions: options });
  fs.writeFileSync(path.join(out, `${name}.prompt.txt`), prompt);
}

fs.writeFileSync(path.join(out, "cases.json"), JSON.stringify(cases, null, 2) + "\n");
