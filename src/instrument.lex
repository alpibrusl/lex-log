# instrument.lex — request/task instrumentation helpers.
#
# This is the surface a host framework wires lex-log into. It packages
# the three things every instrumented unit of work needs:
#
#   1. a trace context (inherited from an inbound W3C traceparent, or a
#      fresh root when there isn't one),
#   2. a span that brackets the work, and
#   3. logs that automatically carry that context's trace_id / span_id.
#
# `Scope` bundles the active context with its span so callers thread a
# single value through the request instead of two.
#
# lex-web middleware (MwTracing):
#   let sc  := instrument.http_begin(req_traceparent, req.path, "lex-web")
#   let _   := exporter.export_logs(cfg, [instrument.info(sc, "lex-web", "request received")])
#   ... handle ...
#   let sp  := instrument.http_finish(sc, resp.status)
#   exporter.export_spans(cfg, [sp])
#
# lex-agent A2A dispatch:
#   let sc := instrument.a2a_begin(in_traceparent, task_id, capability, "lex-agent")
#   ... dispatch to handler ...
#   exporter.export_spans(cfg, [instrument.a2a_finish(sc, ok)])

import "std.int" as int

import "./context" as ctx

import "./span" as span

import "./log" as log

type Scope = { ctx :: ctx.TraceCtx, span :: span.Span }

# Open a span under the inbound traceparent. A present, well-formed
# header makes the new span a child of the caller's; anything else
# (absent / malformed) starts a fresh root trace. This is the core of
# W3C context propagation across a service boundary.
fn begin(traceparent :: Str, name :: Str, service :: Str) -> [random, time] Scope {
  match ctx.from_header(traceparent) {
    Some(parent) => {
      let c := ctx.child(parent)
      { ctx: c, span: span.start_child(parent, c, name, service) }
    },
    None => {
      let root := ctx.new_root()
      { ctx: root, span: span.start(root, name, service) }
    },
  }
}

# Pure scope transform — no examples block: a Scope literal would just
# restate span.set_attr, which is exercised by the exporter tests.
fn set_attr(sc :: Scope, key :: Str, value :: Str) -> Scope {
  { ctx: sc.ctx, span: span.set_attr(sc.span, key, value) }
}

# The W3C traceparent to forward to a downstream call made from inside
# this scope (so the next hop's span chains to ours).
fn outbound_header(sc :: Scope) -> Str {
  ctx.to_header(sc.ctx)
}

# Correlated logs: every record emitted through these carries the
# scope's trace_id / span_id, so logs and spans line up in the backend.
fn info(sc :: Scope, service :: Str, body :: Str) -> [time] log.LogRecord {
  log.info(sc.ctx, service, body)
}

fn warn(sc :: Scope, service :: Str, body :: Str) -> [time] log.LogRecord {
  log.warn(sc.ctx, service, body)
}

fn error(sc :: Scope, service :: Str, body :: Str) -> [time] log.LogRecord {
  log.error(sc.ctx, service, body)
}

# ---- HTTP (lex-web MwTracing) ---------------------------------------
fn http_begin(traceparent :: Str, route :: Str, service :: Str) -> [random, time] Scope {
  set_attr(begin(traceparent, "http.request", service), "http.route", route)
}

# Tag the response status, mark 5xx as a span error, and close the span
# ready for export.
fn http_finish(sc :: Scope, status_code :: Int) -> [time] span.Span {
  let tagged := set_attr(sc, "http.status_code", int.to_str(status_code))
  let sp := if status_code >= 500 {
    span.set_error(tagged.span, "server error")
  } else {
    tagged.span
  }
  span.finish(sp)
}

# ---- A2A task dispatch (lex-agent) ----------------------------------
fn a2a_begin(traceparent :: Str, task_id :: Str, capability :: Str, service :: Str) -> [random, time] Scope {
  let base := begin(traceparent, "a2a.task", service)
  let with_id := set_attr(base, "a2a.task_id", task_id)
  set_attr(with_id, "a2a.capability", capability)
}

fn a2a_finish(sc :: Scope, ok :: Bool) -> [time] span.Span {
  let sp := if ok {
    sc.span
  } else {
    span.set_error(sc.span, "task failed")
  }
  span.finish(sp)
}

