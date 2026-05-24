# log.lex — structured log records.
#
# Every record carries the active trace context so logs correlate with spans
# in Grafana / Jaeger / any OTLP-compatible backend.
#
# Usage:
#   let r := log.info(ctx, "lex-web", "request received")
#   let r := log.with_attr(r, "http.method", "POST")
#   exporter.export_logs(cfg, [r])

import "std.time" as time

import "std.list" as list

import "./context" as ctx

type Level = Trace | Debug | Info | Warn | Error | Fatal

type LogRecord = { level :: Level, body :: Str, attrs :: List[(Str, Str)], trace_id :: Str, span_id :: Str, service :: Str, ts_ms :: Int }

fn level_num(l :: Level) -> Int
  examples {
    level_num(Trace) => 1,
    level_num(Info) => 9,
    level_num(Fatal) => 21
  }
{
  match l {
    Trace => 1,
    Debug => 5,
    Info => 9,
    Warn => 13,
    Error => 17,
    Fatal => 21,
  }
}

fn level_text(l :: Level) -> Str
  examples {
    level_text(Info) => "INFO",
    level_text(Error) => "ERROR"
  }
{
  match l {
    Trace => "TRACE",
    Debug => "DEBUG",
    Info => "INFO",
    Warn => "WARN",
    Error => "ERROR",
    Fatal => "FATAL",
  }
}

fn make(level :: Level, trace_ctx :: ctx.TraceCtx, service :: Str, body :: Str) -> [time] LogRecord {
  { level: level, body: body, attrs: [], trace_id: trace_ctx.trace_id, span_id: trace_ctx.span_id, service: service, ts_ms: time.now_ms() }
}

fn trace(trace_ctx :: ctx.TraceCtx, service :: Str, body :: Str) -> [time] LogRecord {
  make(Trace, trace_ctx, service, body)
}

fn debug(trace_ctx :: ctx.TraceCtx, service :: Str, body :: Str) -> [time] LogRecord {
  make(Debug, trace_ctx, service, body)
}

fn info(trace_ctx :: ctx.TraceCtx, service :: Str, body :: Str) -> [time] LogRecord {
  make(Info, trace_ctx, service, body)
}

fn warn(trace_ctx :: ctx.TraceCtx, service :: Str, body :: Str) -> [time] LogRecord {
  make(Warn, trace_ctx, service, body)
}

fn error(trace_ctx :: ctx.TraceCtx, service :: Str, body :: Str) -> [time] LogRecord {
  make(Error, trace_ctx, service, body)
}

fn fatal(trace_ctx :: ctx.TraceCtx, service :: Str, body :: Str) -> [time] LogRecord {
  make(Fatal, trace_ctx, service, body)
}

fn with_attr(r :: LogRecord, key :: Str, value :: Str) -> LogRecord
  examples {
    with_attr({ level: Info, body: "b", attrs: [], trace_id: "t", span_id: "s", service: "svc", ts_ms: 0 }, "http.method", "POST") => { level: Info, body: "b", attrs: [("http.method", "POST")], trace_id: "t", span_id: "s", service: "svc", ts_ms: 0 }
  }
{
  { level: r.level, body: r.body, attrs: list.concat(r.attrs, [(key, value)]), trace_id: r.trace_id, span_id: r.span_id, service: r.service, ts_ms: r.ts_ms }
}

