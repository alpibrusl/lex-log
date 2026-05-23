# exporter.lex — OTLP/HTTP export + stdout JSON-lines fallback.
#
# Sends logs, spans, and metrics to an OpenTelemetry collector via the
# OTLP/HTTP JSON protocol (no gRPC dependency).
#
# Endpoints (from Config.endpoint):
#   logs:    POST {endpoint}/v1/logs
#   traces:  POST {endpoint}/v1/traces
#   metrics: POST {endpoint}/v1/metrics
#
# If endpoint is "" the payload is written to stdout as a single JSON line.
#
# OTLP JSON spec: https://opentelemetry.io/docs/specs/otlp/

import "std.http" as http
import "std.bytes" as bytes
import "std.str" as str
import "std.int" as int
import "std.float" as float
import "std.list" as list
import "std.io" as io
import "lex-schema/json_value" as jv
import "./log" as log
import "./span" as span
import "./meter" as meter

type Config = {
  endpoint :: Str,   # "http://otel-collector:4318" or "" for stdout
  service  :: Str,   # resource attribute service.name
}

fn stdout_config(service :: Str) -> Config { { endpoint: "", service: service } }
fn otlp_config(endpoint :: Str, service :: Str) -> Config { { endpoint: endpoint, service: service } }

# ---- JSON helpers ---------------------------------------------------

fn kv_str(key :: Str, value :: Str) -> jv.Json {
  JObj([("key", JStr(key)), ("value", JObj([("stringValue", JStr(value))]))])
}

fn kv_int(key :: Str, value :: Int) -> jv.Json {
  JObj([("key", JStr(key)), ("value", JObj([("intValue", JStr(int.to_str(value)))]))])
}

fn attrs_json(attrs :: List[(Str, Str)]) -> jv.Json {
  JArr(list.map(attrs, fn (pair :: (Str, Str)) -> jv.Json { kv_str(pair.0, pair.1) }))
}

fn resource_json(service :: Str) -> jv.Json {
  JObj([("attributes", JArr([kv_str("service.name", service)]))])
}

fn scope_json() -> jv.Json {
  JObj([("name", JStr("lex-log")), ("version", JStr("0.1.0"))])
}

fn ms_to_nano_str(ms :: Int) -> Str {
  int.to_str(ms * 1000000)
}

# ---- Logs -----------------------------------------------------------

fn log_record_json(r :: log.LogRecord) -> jv.Json {
  JObj([
    ("timeUnixNano",   JStr(ms_to_nano_str(r.ts_ms))),
    ("severityNumber", JInt(log.level_num(r.level))),
    ("severityText",   JStr(log.level_text(r.level))),
    ("body",           JObj([("stringValue", JStr(r.body))])),
    ("attributes",     attrs_json(r.attrs)),
    ("traceId",        JStr(r.trace_id)),
    ("spanId",         JStr(r.span_id)),
  ])
}

fn logs_payload(service :: Str, records :: List[log.LogRecord]) -> Str {
  jv.stringify(JObj([
    ("resourceLogs", JArr([JObj([
      ("resource",  resource_json(service)),
      ("scopeLogs", JArr([JObj([
        ("scope",      scope_json()),
        ("logRecords", JArr(list.map(records, fn (r :: log.LogRecord) -> jv.Json { log_record_json(r) }))),
      ])]))
    ])]))
  ]))
}

# ---- Traces ---------------------------------------------------------

fn span_status_json(s :: span.SpanStatus) -> jv.Json {
  match s {
    SpanOk       => JObj([("code", JInt(1))]),
    SpanError(m) => JObj([("code", JInt(2)), ("message", JStr(m))]),
  }
}

fn span_json(sp :: span.Span) -> jv.Json {
  JObj([
    ("traceId",           JStr(sp.ctx.trace_id)),
    ("spanId",            JStr(sp.ctx.span_id)),
    ("parentSpanId",      JStr(sp.parent_id)),
    ("name",              JStr(sp.name)),
    ("startTimeUnixNano", JStr(ms_to_nano_str(sp.start_ms))),
    ("endTimeUnixNano",   JStr(ms_to_nano_str(sp.end_ms))),
    ("attributes",        attrs_json(sp.attrs)),
    ("status",            span_status_json(sp.status)),
  ])
}

fn traces_payload(service :: Str, spans :: List[span.Span]) -> Str {
  jv.stringify(JObj([
    ("resourceSpans", JArr([JObj([
      ("resource",   resource_json(service)),
      ("scopeSpans", JArr([JObj([
        ("scope", scope_json()),
        ("spans", JArr(list.map(spans, fn (sp :: span.Span) -> jv.Json { span_json(sp) }))),
      ])]))
    ])]))
  ]))
}

# ---- Metrics --------------------------------------------------------

fn datapoint_json(attrs :: List[(Str, Str)], ts_ms :: Int) -> jv.Json {
  JObj([
    ("attributes",    attrs_json(attrs)),
    ("timeUnixNano",  JStr(ms_to_nano_str(ts_ms))),
  ])
}

fn metric_json(m :: meter.Metric, ts_ms :: Int) -> jv.Json {
  match m {
    Counter(name, delta, attrs) => JObj([
      ("name", JStr(name)),
      ("sum", JObj([
        ("dataPoints",   JArr([JObj([("asInt", JStr(int.to_str(delta))), ("attributes", attrs_json(attrs)), ("timeUnixNano", JStr(ms_to_nano_str(ts_ms)))])])),
        ("isMonotonic",  JBool(true)),
        ("aggregationTemporality", JInt(2)),
      ])),
    ]),
    Gauge(name, value, attrs) => JObj([
      ("name", JStr(name)),
      ("gauge", JObj([
        ("dataPoints", JArr([JObj([("asDouble", JFloat(value)), ("attributes", attrs_json(attrs)), ("timeUnixNano", JStr(ms_to_nano_str(ts_ms)))])])),
      ])),
    ]),
    Histogram(name, value, attrs) => JObj([
      ("name", JStr(name)),
      ("histogram", JObj([
        ("dataPoints", JArr([JObj([("sum", JFloat(value)), ("count", JStr("1")), ("attributes", attrs_json(attrs)), ("timeUnixNano", JStr(ms_to_nano_str(ts_ms)))])])),
        ("aggregationTemporality", JInt(2)),
      ])),
    ]),
  }
}

fn metrics_payload(service :: Str, metrics :: List[meter.Metric], ts_ms :: Int) -> Str {
  jv.stringify(JObj([
    ("resourceMetrics", JArr([JObj([
      ("resource",     resource_json(service)),
      ("scopeMetrics", JArr([JObj([
        ("scope",   scope_json()),
        ("metrics", JArr(list.map(metrics, fn (m :: meter.Metric) -> jv.Json { metric_json(m, ts_ms) }))),
      ])]))
    ])]))
  ]))
}

# ---- Transport ------------------------------------------------------

fn post_otlp(endpoint :: Str, path :: Str, body :: Str) -> [net] Unit {
  let url := str.concat(endpoint, path)
  let _   := http.post(url, bytes.from_str(body), "application/json")
  unit
}

fn print_line(label :: Str, body :: Str) -> [io] Unit {
  io.print(str.concat(label, body))
}

# ---- Public API -----------------------------------------------------

fn export_logs(cfg :: Config, records :: List[log.LogRecord]) -> [net, io] Unit {
  if list.is_empty(records) {
    unit
  } else {
    let payload := logs_payload(cfg.service, records)
    if str.is_empty(cfg.endpoint) {
      print_line("otel.logs ", payload)
    } else {
      post_otlp(cfg.endpoint, "/v1/logs", payload)
    }
  }
}

fn export_spans(cfg :: Config, spans :: List[span.Span]) -> [net, io] Unit {
  if list.is_empty(spans) {
    unit
  } else {
    let payload := traces_payload(cfg.service, spans)
    if str.is_empty(cfg.endpoint) {
      print_line("otel.traces ", payload)
    } else {
      post_otlp(cfg.endpoint, "/v1/traces", payload)
    }
  }
}

fn export_metrics(cfg :: Config, metrics :: List[meter.Metric]) -> [net, io, time] Unit {
  if list.is_empty(metrics) {
    unit
  } else {
    let ts      := time.now_ms()
    let payload := metrics_payload(cfg.service, metrics, ts)
    if str.is_empty(cfg.endpoint) {
      print_line("otel.metrics ", payload)
    } else {
      post_otlp(cfg.endpoint, "/v1/metrics", payload)
    }
  }
}
