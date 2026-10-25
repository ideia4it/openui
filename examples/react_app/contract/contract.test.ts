// Parses every program in programs/ with the official parser and compares the summary
// with what the Elixir library produced (elixir.json, from elixir_summary.exs).
// The summary follows the official conformance runner (spec/fixtures/1.0/README.md,
// "How the tree is summarized").
import { describe, expect, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import {
  createLibrary,
  createParser,
  createStore,
  defineComponent,
  evaluate,
  evaluateRoot,
  markReactive,
  type EvaluationContext,
  type LibraryJSONSchema,
  type OpenUIError,
  type ParseResult,
} from "@openuidev/lang-core";
import * as z from "zod/v4";

type Dict = Record<string, unknown>;
type Call = { params: { properties?: Dict } };

const here = import.meta.dir;
const spec = JSON.parse(fs.readFileSync(path.join(here, "../library.json"), "utf8"));
const schema = spec.schema as LibraryJSONSchema;
const elixir: Record<string, Dict> = JSON.parse(
  fs.readFileSync(path.join(here, "elixir.json"), "utf8"),
);

// Same implementation as the Elixir side in elixir_summary.exs.
const FUNCTIONS: Record<string, (args: Dict) => unknown> = {
  Percent: ({ part, total }) => `${Math.round(((part as number) / (total as number)) * 100)}%`,
};

const library = {
  ...createLibrary({
    components: Object.entries(
      spec.components as Record<string, { signature: string; description: string }>,
    ).map(([name, { signature, description }]) => {
      const bindable = new Set([...signature.matchAll(/(\w+)\??: \$binding</g)].map((m) => m[1]));
      const props = Object.keys(spec.schema.$defs[name].properties ?? {}).map((key) => {
        const prop = z.any();
        if (bindable.has(key)) markReactive(prop);
        return [key, prop];
      });
      return defineComponent({
        name,
        description,
        props: z.object(Object.fromEntries(props)),
        component: null,
      });
    }),
    root: spec.root,
  }),
  toJSONSchema: () => schema,
};

const functions = Object.fromEntries(
  Object.entries((spec.schema.functions ?? {}) as Dict).map(([name, f]) => [
    name,
    { ...(f as Dict), fn: FUNCTIONS[name] },
  ]),
) as EvaluationContext["functions"];

const actionParams = Object.fromEntries(
  Object.entries((schema.actions ?? {}) as Dict).map(([name, a]) => [
    name,
    Object.keys((a as Call).params.properties ?? {}),
  ]),
);

const json = <T>(v: T): T => (v === undefined ? v : JSON.parse(JSON.stringify(v)));

type Ev = (ast: unknown) => unknown;

function summarizeAction(s: Dict, ev: Ev): Dict {
  switch (s.type) {
    case "continue_conversation":
      return { action: "ToAssistant", args: s.context == null ? [s.message] : [s.message, s.context] };
    case "open_url":
      return { action: "OpenUrl", args: [s.url] };
    case "set":
      return { action: "Set", args: [s.target, ev(s.valueAST) ?? null] };
    case "reset":
      return { action: "Reset", args: s.targets };
    case "run":
      return { action: "Run", args: [s.statementId] };
    default: {
      const params = (s.params as Dict) ?? {};
      const keys = actionParams[s.name as string] ?? Object.keys(params);
      return { action: s.name, args: keys.map((k) => summarize(params[k], ev)) };
    }
  }
}

function summarize(v: unknown, ev: Ev): unknown {
  if (v == null || typeof v !== "object") return v ?? null;
  if (Array.isArray(v)) return v.map((x) => summarize(x, ev));
  const o = v as Dict;
  if (o.type === "element") {
    const props = Object.entries(o.props as Dict)
      .map(([k, pv]) => [k, summarize(pv, ev)])
      .filter(([, s]) => s !== null);
    return { type: o.typeName, props: Object.fromEntries(props) };
  }
  if (Array.isArray(o.steps)) return { actions: (o.steps as Dict[]).map((s) => summarizeAction(s, ev)) };
  if (o.__reactive === "assign") return { $binding: o.target };
  return Object.fromEntries(Object.entries(o).map(([k, pv]) => [k, summarize(pv, ev)]));
}

// At stream end no fetch has returned: a query reads its defaults, a mutation is idle.
function canonical(result: ParseResult) {
  const store = createStore();
  store.initialize(result.stateDeclarations ?? {}, {});
  const ctx: EvaluationContext = {
    getState: (name) => store.get(name) ?? null,
    resolveRef: (name) => {
      const query = result.queryStatements.find((s) => s.statementId === name);
      if (query) return query.defaultsAST ? evaluate(query.defaultsAST, ctx) : null;
      const mutation = result.mutationStatements.some((s) => s.statementId === name);
      return mutation ? { status: "idle", data: null, error: null } : null;
    },
    functions,
    actions: schema.actions,
  };
  const runtimeErrors: OpenUIError[] = [];
  const tree = evaluateRoot(result, { ctx, library, store, errors: runtimeErrors });
  const errorObjects = [
    ...result.meta.errors.map((e) => ({ source: "parser", ...e, path: e.path || undefined })),
    ...runtimeErrors,
  ];
  return json({
    root: summarize(tree, (ast) => evaluate(ast as never, ctx)),
    errors: errorObjects.map(({ code, statementId }) => ({ code, statementId })),
    errorObjects,
    unresolved: result.meta.unresolved,
    orphans: result.meta.orphaned,
    incomplete: result.meta.incomplete,
    state: result.stateDeclarations ?? {},
  });
}

// Error lists are compared as multisets and name lists as sets: order is not part of the contract.
// message and hint are text for the model, never compared (spec/fixtures/1.0/README.md).
const structural = (errors: unknown[]) =>
  errors.map((error) => {
    const { message: _message, hint: _hint, ...fields } = error as Dict;
    return fields;
  });
const sortedJson = (xs: unknown[]) => xs.map((x) => JSON.stringify(x, Object.keys(x as Dict).sort())).sort();
const sortedSet = (xs: unknown) => [...new Set((xs ?? []) as string[])].sort();

const parser = createParser(schema, spec.root);
const programs = fs
  .readdirSync(path.join(here, "programs"))
  .filter((file) => file.endsWith(".oui"))
  .sort();

describe("the official parser and the Elixir library agree", () => {
  test("every program has an Elixir summary", () => {
    expect(Object.keys(elixir).sort()).toEqual(programs);
  });

  for (const file of programs) {
    test(file, () => {
      const js = canonical(parser.parse(fs.readFileSync(path.join(here, "programs", file), "utf8")));
      const ex = elixir[file];

      expect(ex.root).toEqual(js.root);
      expect(sortedJson(ex.errors as unknown[])).toEqual(sortedJson(js.errors));
      expect(sortedJson(structural(ex.errorObjects as unknown[]))).toEqual(
        sortedJson(structural(js.errorObjects)),
      );
      expect(sortedSet(ex.unresolved)).toEqual(sortedSet(js.unresolved));
      expect(sortedSet(ex.orphans)).toEqual(sortedSet(js.orphans));
      expect(ex.incomplete).toEqual(js.incomplete);
      expect(ex.state).toEqual(js.state);
    });
  }
});
