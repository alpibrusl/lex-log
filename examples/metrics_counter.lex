# metrics_counter.lex — counters + a gauge emitted as OTLP JSON-lines.
#
# With an empty endpoint the exporter writes each batch to stdout as a
# single JSON line (the "otel.metrics " prefix marks the stream), so you
# can see the exact OTLP payload without standing up a collector.
#
# Run:
#   lex run --allow-effects net,io,time,random examples/metrics_counter.lex main
# (`random` is granted because the shared exporter graph pulls in the
# trace-id generator in context.lex, even though this demo never traces.)
#
# Point at a real collector instead by swapping stdout_config for
# otlp_config("http://otel-collector:4318", "metrics-demo").

import "../src/meter" as meter

import "../src/exporter" as exporter

fn main() -> [net, io, time] Unit {
  let cfg := exporter.stdout_config("metrics-demo")
  exporter.export_metrics(cfg, [meter.counter("http.requests", 1, [("method", "GET"), ("status", "200")]), meter.counter("http.requests", 1, [("method", "POST"), ("status", "201")]), meter.gauge("queue.depth", 7.0, [("queue", "emails")])])
}

