# lex-log — integration tests.
#
# Covers the three guarantees issue #1 asks for:
#   1. OTLP/HTTP JSON export format matches the spec (resource/scope
#      envelope, hex trace/span ids, nano timestamps, severity).
#   2. W3C traceparent round-trips through to_header / from_header.
#   3. The stdout JSON-lines fallback runs when no endpoint is set.
#
# Pure assertions need no policy; the stdout-export case carries
# [net, io, time]. `lex test` runs `run_all` with a permissive policy.

import "std.str" as str

import "std.list" as list

import "std.io" as io

import "lex-schema/json_value" as jv

import "../src/context" as context

import "../src/meter" as meter

import "../src/exporter" as exporter

import "../src/instrument" as instrument

# ---- Helpers -----------------------------------------------------
fn valid_json(s :: Str) -> Result[Unit, Str] {
  match jv.parse(s) {
    Ok(_) => Ok(()),
    Err(_) => Err(str.concat("not valid JSON: ", s)),
  }
}

# ---- 2. W3C traceparent round-trip -------------------------------
fn t_traceparent_roundtrip() -> Result[Unit, Str] {
  let c := { trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", sampled: true }
  match context.from_header(context.to_header(c)) {
    None => Err("from_header returned None for a header we just serialised"),
    Some(back) => if back.trace_id == c.trace_id and back.span_id == c.span_id and back.sampled == c.sampled {
      Ok(())
    } else {
      Err("traceparent round-trip changed the context")
    },
  }
}

fn t_traceparent_rejects_garbage() -> Result[Unit, Str] {
  match context.from_header("not-a-traceparent") {
    Some(_) => Err("from_header accepted a malformed header"),
    None => Ok(()),
  }
}

# ---- 1. OTLP/HTTP JSON export format -----------------------------
fn t_logs_payload_shape() -> Result[Unit, Str] {
  let rec := { level: Info, body: "request received", attrs: [("http.method", "POST")], trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", service: "lex-web", ts_ms: 1700000000000 }
  let payload := exporter.logs_payload("lex-web", [rec])
  if str.contains(payload, "resourceLogs") and str.contains(payload, "scopeLogs") and str.contains(payload, "\"severityText\":\"INFO\"") and str.contains(payload, "\"traceId\":\"0af7651916cd43dd8448eb211c80319c\"") and str.contains(payload, "1700000000000000000") {
    valid_json(payload)
  } else {
    Err(str.concat("logs payload missing OTLP fields: ", payload))
  }
}

fn t_traces_payload_shape() -> Result[Unit, Str] {
  let sp := { ctx: { trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", sampled: true }, parent_id: "00f067aa0ba902b7", name: "http.request", service: "lex-web", attrs: [("http.route", "/orders")], start_ms: 1700000000000, end_ms: 1700000000150, status: SpanOk }
  let payload := exporter.traces_payload("lex-web", [sp])
  if str.contains(payload, "resourceSpans") and str.contains(payload, "\"name\":\"http.request\"") and str.contains(payload, "\"parentSpanId\":\"00f067aa0ba902b7\"") and str.contains(payload, "\"code\":1") {
    valid_json(payload)
  } else {
    Err(str.concat("traces payload missing OTLP fields: ", payload))
  }
}

fn t_metrics_payload_shape() -> Result[Unit, Str] {
  let metrics := [meter.counter("http.requests", 2, [("method", "GET")]), meter.gauge("queue.depth", 5.0, [])]
  let payload := exporter.metrics_payload("svc", metrics, 1700000000000)
  if str.contains(payload, "resourceMetrics") and str.contains(payload, "\"asInt\":\"2\"") and str.contains(payload, "\"isMonotonic\":true") and str.contains(payload, "\"asDouble\":") and str.contains(payload, "queue.depth") {
    valid_json(payload)
  } else {
    Err(str.concat("metrics payload missing OTLP fields: ", payload))
  }
}

# ---- 3. stdout JSON-lines fallback runs --------------------------
fn t_stdout_export_runs() -> [net, io, time] Result[Unit, Str] {
  let cfg := exporter.stdout_config("svc")
  let rec := { level: Info, body: "stdout fallback", attrs: [], trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", service: "svc", ts_ms: 1700000000000 }
  let __lex_discard_1 := exporter.export_logs(cfg, [rec])
  let __lex_discard_2 := exporter.export_metrics(cfg, [meter.counter("x", 1, [])])
  Ok(())
}

# ---- instrument: traceparent propagation through a Scope ---------
fn t_instrument_propagates_parent() -> [random, time] Result[Unit, Str] {
  let parent := { trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", sampled: true }
  let sc := instrument.begin(context.to_header(parent), "http.request", "lex-web")
  if sc.ctx.trace_id == parent.trace_id and sc.span.parent_id == parent.span_id {
    if sc.ctx.span_id == parent.span_id {
      Err("child span_id should differ from parent span_id")
    } else {
      Ok(())
    }
  } else {
    Err("instrument.begin did not chain the child span to the inbound parent")
  }
}

fn t_instrument_roots_without_header() -> [random, time] Result[Unit, Str] {
  let sc := instrument.begin("", "http.request", "lex-web")
  if sc.span.parent_id == "" {
    Ok(())
  } else {
    Err("instrument.begin should start a root span (empty parent_id) when no header is present")
  }
}

# ---- Suite -------------------------------------------------------
fn suite() -> [net, io, time, random] List[Result[Unit, Str]] {
  [t_traceparent_roundtrip(), t_traceparent_rejects_garbage(), t_logs_payload_shape(), t_traces_payload_shape(), t_metrics_payload_shape(), t_stdout_export_runs(), t_instrument_propagates_parent(), t_instrument_roots_without_header()]
}

fn run_all() -> [net, io, time, random] Unit {
  let failures := list.fold(suite(), 0, fn (n :: Int, r :: Result[Unit, Str]) -> [io] Int {
    match r {
      Ok(_) => n,
      Err(m) => {
        let __lex_discard_3 := io.print(str.concat("FAIL: ", m))
        n + 1
      },
    }
  })
  if failures == 0 {
    ()
  } else {
    let __fail := 1 / 0
    ()
  }
}

