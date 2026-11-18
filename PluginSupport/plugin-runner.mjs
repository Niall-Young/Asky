// Trusted Asky plugin runner. This is a protocol/lifecycle boundary, not a sandbox.
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";
import { inspect } from "node:util";
class ArgumentError extends Error {}
const emit = (value) => process.stdout.write(JSON.stringify(value) + "\n");
for (const method of ["log", "info", "warn", "error", "debug"]) {
  console[method] = (...args) => process.stderr.write(args.map(a => typeof a === "string" ? a : inspect(a)).join(" ") + "\n");
}
const cancellation = new AbortController();
process.on("SIGTERM", () => { cancellation.abort(); setTimeout(() => process.exit(143), 100).unref(); });
const input = createInterface({ input: process.stdin });
let started = false;
let disconnected = false;
let seq = 0;
const pending = new Map();
function rpc(method, body) {
  if (disconnected) {
    process.exitCode = 1;
    return Promise.reject(new Error("Plugin host disconnected"));
  }
  const id = ++seq;
  return new Promise((resolve, reject) => { pending.set(id, { resolve, reject }); emit({ ...body, type: "rpc", id, method }); });
}
input.on("close", () => {
  disconnected = true;
  if (pending.size) process.exitCode = 1;
  for (const waiter of pending.values()) waiter.reject(new Error("Plugin host disconnected"));
  pending.clear();
});
input.on("line", (line) => {
  if (Buffer.byteLength(line) > 1 << 20) { emit({ type: "result", error: "Plugin frame too large" }); process.exit(1); }
  let frame;
  try { frame = JSON.parse(line); } catch { emit({ type: "result", error: "Invalid host frame" }); process.exit(1); }
  if (started) {
    const waiter = pending.get(frame.id); pending.delete(frame.id);
    if (frame.error) waiter?.reject(new Error(frame.error)); else waiter?.resolve(frame.value);
    return;
  }
  started = true;
  void (async () => {
    validate(frame.arguments, frame.inputSchema);
    const plugin = (await import(pathToFileURL(frame.entry).href)).default;
    const tool = plugin?.tools?.[frame.tool];
    if (!tool || typeof tool.execute !== "function") throw new Error("Plugin tool entry missing");
    const context = {
      configuration: frame.configuration, requestID: frame.requestID, signal: cancellation.signal,
      state: frame.state,
      async saveState(value) { await rpc("state", { value }); this.state = value; },
      exec(executable, args, options = {}) {
        if (cancellation.signal.aborted) return Promise.reject(new Error("Plugin call cancelled"));
        return rpc("exec", { cwd: options.cwd, timeoutSeconds: options.timeoutSeconds, executable, arguments: args });
      },
    };
    const value = frame.readback ? (typeof tool.readback === "function" ? await tool.readback(frame.arguments, context, frame.output) : null)
                                : await tool.execute(frame.arguments, context);
    emit({ type: "result", value: value ?? null });
  })().catch(error => emit({ type: "result", error: String(error?.stack ?? error), errorCode: error instanceof ArgumentError ? "invalidArguments" : "adapterFailure" })).finally(() => { input.close(); process.stdout.write("", () => process.exit(process.exitCode ?? 0)); });
});

function validate(value, schema, path = "arguments") {
  if (!schema) return;
  const types = { object: value !== null && typeof value === "object" && !Array.isArray(value),
    array: Array.isArray(value), string: typeof value === "string", boolean: typeof value === "boolean",
    number: typeof value === "number", integer: Number.isInteger(value), null: value === null };
  if (schema.type && !types[schema.type]) throw new ArgumentError(`${path}: expected ${schema.type}`);
  if (schema.enum && !schema.enum.some((v) => JSON.stringify(v) === JSON.stringify(value))) throw new ArgumentError(`${path}: invalid option`);
  if (typeof value === "string" && value.length < (schema.minLength ?? 0)) throw new ArgumentError(`${path}: value is too short`);
  if (schema.type === "object") {
    for (const key of schema.required ?? []) if (!(key in value)) throw new ArgumentError(`${path}.${key}: required`);
    for (const [key, val] of Object.entries(value)) {
      if (schema.additionalProperties === false && !schema.properties?.[key]) throw new ArgumentError(`${path}.${key}: unexpected property`);
      validate(val, schema.properties?.[key], `${path}.${key}`);
    }
  }
  if (schema.type === "array" && schema.items) value.forEach((v, i) => validate(v, schema.items, `${path}[${i}]`));
}
