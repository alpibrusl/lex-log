# span.lex — distributed tracing spans.
#
# Usage:
#   let sp := span.start(ctx, "http.request", "lex-web")
#   let sp := span.set_attr(sp, "http.method", "POST")
#   let sp := span.set_attr(sp, "http.route", "/api/v1/orders")
#   let sp := span.finish(sp)
#   exporter.export_spans(cfg, [sp])

import "std.time" as time

import "std.list" as list

import "./context" as ctx

type SpanStatus = SpanOk | SpanError(Str)

type Span = { ctx :: ctx.TraceCtx, parent_id :: Str, name :: Str, service :: Str, attrs :: List[(Str, Str)], start_ms :: Int, end_ms :: Int, status :: SpanStatus }

fn start(trace_ctx :: ctx.TraceCtx, name :: Str, service :: Str) -> [time] Span {
  { ctx: trace_ctx, parent_id: "", name: name, service: service, attrs: [], start_ms: time.now_ms(), end_ms: 0, status: SpanOk }
}

fn start_child(parent :: ctx.TraceCtx, child_ctx :: ctx.TraceCtx, name :: Str, service :: Str) -> [time] Span {
  { ctx: child_ctx, parent_id: parent.span_id, name: name, service: service, attrs: [], start_ms: time.now_ms(), end_ms: 0, status: SpanOk }
}

fn finish(sp :: Span) -> [time] Span {
  { ctx: sp.ctx, parent_id: sp.parent_id, name: sp.name, service: sp.service, attrs: sp.attrs, start_ms: sp.start_ms, end_ms: time.now_ms(), status: sp.status }
}

# Pure record transform — set_attr/set_error are exercised end-to-end by
# the exporter integration tests; a literal Span example here would just
# restate the field copy.
fn set_attr(sp :: Span, key :: Str, value :: Str) -> Span {
  { ctx: sp.ctx, parent_id: sp.parent_id, name: sp.name, service: sp.service, attrs: list.concat(sp.attrs, [(key, value)]), start_ms: sp.start_ms, end_ms: sp.end_ms, status: sp.status }
}

fn set_error(sp :: Span, msg :: Str) -> Span {
  { ctx: sp.ctx, parent_id: sp.parent_id, name: sp.name, service: sp.service, attrs: sp.attrs, start_ms: sp.start_ms, end_ms: sp.end_ms, status: SpanError(msg) }
}

fn duration_ms(sp :: Span) -> Int
  examples {
    duration_ms({ ctx: { trace_id: "t", span_id: "s", sampled: true }, parent_id: "", name: "n", service: "svc", attrs: [], start_ms: 100, end_ms: 250, status: SpanOk }) => 150,
    duration_ms({ ctx: { trace_id: "t", span_id: "s", sampled: true }, parent_id: "", name: "n", service: "svc", attrs: [], start_ms: 100, end_ms: 0, status: SpanOk }) => 0
  }
{
  if sp.end_ms > 0 {
    sp.end_ms - sp.start_ms
  } else {
    0
  }
}

