# traced_http_server.lex — an HTTP server with W3C trace propagation
# and OTLP export, the way a lex-web service wires lex-log in.
#
# For each request the handler:
#   1. reads the inbound `traceparent` header (if any),
#   2. opens a child span under it — or a fresh root trace when absent,
#   3. emits a request-received log that carries the span's trace_id /
#      span_id (so logs and the span line up in the backend),
#   4. tags the span with the response status and exports both the log
#      and the span on the way out.
#
# Export goes to stdout as OTLP JSON-lines here; set
# exporter.otlp_config("http://otel-collector:4318", "lex-web") to ship
# to a real collector instead.
#
# Run:
#   lex run --allow-effects net,io,time,random examples/traced_http_server.lex main
# Then, in another terminal:
#   curl -H 'traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01' \
#        http://127.0.0.1:8080/orders
#   curl http://127.0.0.1:8080/boom        # 500 — span is marked an error

import "std.net" as net

import "std.map" as map

import "../src/instrument" as instrument

import "../src/exporter" as exporter

type Request = { method :: Str, path :: Str, query :: Str, body :: Str, headers :: Map[Str, Str], path_params :: Map[Str, Str] }

type Response = { body :: Str, status :: Int }

# Mocked routing: /boom fails so the example shows a 5xx span error.
fn route_status(path :: Str) -> Int
  examples {
    route_status("/orders") => 200,
    route_status("/boom") => 500,
    route_status("/health") => 200
  }
{
  match path {
    "/boom" => 500,
    _ => 200,
  }
}

fn inbound_traceparent(req :: Request) -> Str {
  match map.get(req.headers, "traceparent") {
    Some(h) => h,
    None => "",
  }
}

fn handle(req :: Request) -> [random, time, net, io] Response {
  let cfg := exporter.stdout_config("lex-web")
  let scope := instrument.http_begin(inbound_traceparent(req), req.path, "lex-web")
  let __lex_discard_1 := exporter.export_logs(cfg, [instrument.info(scope, "lex-web", "request received")])
  let status := route_status(req.path)
  let resp := { body: "{\"ok\":true}", status: status }
  let __lex_discard_2 := exporter.export_spans(cfg, [instrument.http_finish(scope, resp.status)])
  resp
}

fn main() -> [net] Nil {
  net.serve(8080, "handle")
}

