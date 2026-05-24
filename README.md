# lex-log — OpenTelemetry for Lex

> **Status: v0.1.** Structured logs, distributed-tracing spans, and
> metrics for Lex services, exported over OTLP/HTTP JSON (no gRPC
> dependency) with a zero-config stdout fallback.

When an agent generates a service and ships it, the humans watching that
service in production need structured logs and traces to trust it
behaves correctly — *without* re-reading the source. Observability is the
runtime complement to compile-time attestation: lex-log is how an
agent-written lex-web / lex-agent service makes its runtime behaviour
legible.

## What's in the box

| Module | Purpose |
|---|---|
| `context` | `TraceCtx` + W3C **traceparent** parse/serialise (`from_header` / `to_header`). |
| `log` | Structured `LogRecord`s at six severities, each carrying the active `trace_id` / `span_id`. |
| `span` | Distributed-tracing `Span`s: `start` / `start_child` / `set_attr` / `set_error` / `finish`. |
| `meter` | `Counter` / `Gauge` / `Histogram` metrics. |
| `exporter` | OTLP/HTTP JSON export for logs, traces, and metrics — plus the stdout JSON-lines fallback. |
| `instrument` | The wiring layer: wrap a request or task in a span with correlated logs (`http_begin`/`http_finish`, `a2a_begin`/`a2a_finish`). |

Import the whole surface through the facade:

```lex
import "lex-log/lex_log" as otel   # otel.TraceCtx, otel.Span, otel.Scope, ...
```

…or pull just the module you need (`import "lex-log/instrument" as inst`).

## Configuring the endpoint

A `Config` is `{ endpoint :: Str, service :: Str }`. Two constructors:

```lex
import "lex-log/exporter" as exporter

# Ship to a collector (Grafana Alloy, the OTel Collector, Jaeger, …):
let cfg := exporter.otlp_config("http://otel-collector:4318", "lex-web")

# Or write OTLP JSON to stdout — one line per batch, prefixed
# `otel.logs `/`otel.traces `/`otel.metrics `. No collector needed:
let cfg := exporter.stdout_config("lex-web")
```

The exporter POSTs to the standard OTLP/HTTP paths under `endpoint`:
`/v1/logs`, `/v1/traces`, `/v1/metrics`. An empty `endpoint` selects the
stdout fallback. Run with `--allow-effects net` (and `--allow-net-host`
for your collector) when exporting over the wire; `io` is enough for the
stdout fallback.

## Wiring lex-log into a lex-web service (MwTracing)

`instrument` packages the tracing middleware behaviour: parse the inbound
`traceparent`, open a child span (or a fresh root when there's no parent),
attach the span's `trace_id` / `span_id` to every log emitted for the
request, and close + export the span on the response.

```lex
import "std.map" as map
import "lex-log/instrument" as inst
import "lex-log/exporter" as exporter

fn handle(req :: Request) -> [random, time, net, io] Response {
  let cfg := exporter.otlp_config("http://otel-collector:4318", "lex-web")

  # 1. inherit (or start) the trace, opening an `http.request` span
  let tp    := match map.get(req.headers, "traceparent") { Some(h) => h, None => "" }
  let scope := inst.http_begin(tp, req.path, "lex-web")

  # 2. logs emitted through the scope carry the span's ids automatically
  let _ := exporter.export_logs(cfg, [inst.info(scope, "lex-web", "request received")])

  let resp := route(req)

  # 3. tag status (5xx becomes a span error) and export the span
  let _ := exporter.export_spans(cfg, [inst.http_finish(scope, resp.status)])
  resp
}
```

To propagate context to a downstream call you make *inside* the handler,
forward `inst.outbound_header(scope)` as the `traceparent` header.

A complete, runnable version is `examples/traced_http_server.lex`.

## lex-agent: tracing A2A task dispatch

Every A2A task dispatch should open an `a2a.task` span and log its
lifecycle. The shape mirrors the HTTP path:

```lex
import "lex-log/instrument" as inst
import "lex-log/exporter" as exporter

fn dispatch(in_traceparent :: Str, task_id :: Str, capability :: Str) -> [random, time, net, io] Bool {
  let cfg   := exporter.stdout_config("lex-agent")
  let scope := inst.a2a_begin(in_traceparent, task_id, capability, "lex-agent")
  let _     := exporter.export_logs(cfg, [inst.info(scope, "lex-agent", "task received")])

  let ok := run_handler(capability, task_id)   # your handler

  let _ := exporter.export_logs(cfg, [inst.info(scope, "lex-agent", "response sent")])
  exporter.export_spans(cfg, [inst.a2a_finish(scope, ok)])
  ok
}
```

The span is named `a2a.task` and tagged with `a2a.task_id` and
`a2a.capability`; `a2a_finish(scope, false)` marks it a span error.

## Examples

```sh
# Metrics → stdout as OTLP JSON-lines
lex run --allow-effects net,io,time,random examples/metrics_counter.lex main

# Traced HTTP server (W3C propagation + span/log export)
lex run --allow-effects net,io,time,random examples/traced_http_server.lex main
# then, in another shell:
curl -H 'traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01' \
     http://127.0.0.1:8080/orders
curl http://127.0.0.1:8080/boom      # 500 → span status code 2 (error)
```

> The demos pull in the shared exporter graph, which includes the
> trace-id generator in `context.lex`, so they ask for `random` even
> when a given demo never traces. Grant only what your own service uses.

## Tests

```sh
lex pkg install          # clones the lex-schema dependency
lex check src/*.lex
lex fmt --check src/ examples/ tests/
lex test tests/          # OTLP payload shape, traceparent round-trip, stdout fallback
```

`tests/test_otel.lex` asserts the OTLP/HTTP JSON envelope (resource/scope
wrappers, hex ids, nanosecond timestamps, severity, monotonic-sum
counters), that `from_header` ∘ `to_header` round-trips a context, that a
malformed header is rejected, and that a child span chains to its inbound
parent.

## Dependency

The exporter serialises through `lex-schema`'s `Json` ADT. It's declared
as a git dependency in `lex.toml` so `lex pkg install` resolves it in CI;
for local hacking on both repos at once, swap in `{ path = "../lex-schema" }`.

## Effect surface

Everything stays as narrow as the work allows:

* ID minting (`context.new_root` / `child`) is `[random]`.
* Timestamps and span open/close are `[time]`.
* Building log/span/metric records and OTLP payloads is **pure**.
* Only the actual export crosses an effect boundary: `[net, io]`
  (plus `[time]` for the metrics timestamp).
