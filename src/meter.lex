# meter.lex — metrics: counters, gauges, histograms.
#
# Metrics are values collected at a point in time and exported as a batch.
#
# Usage:
#   let m := meter.counter("http.requests", 1, [("method", "POST"), ("status", "200")])
#   exporter.export_metrics(cfg, [m])

import "std.list" as list
import "std.time" as time

type Metric =
  | Counter(Str, Int, List[(Str, Str)])       # name, delta, attrs
  | Gauge(Str, Float, List[(Str, Str)])        # name, value, attrs
  | Histogram(Str, Float, List[(Str, Str)])    # name, value, attrs (backend buckets)

fn counter(name :: Str, delta :: Int, attrs :: List[(Str, Str)]) -> Metric {
  Counter(name, delta, attrs)
}

fn gauge(name :: Str, value :: Float, attrs :: List[(Str, Str)]) -> Metric {
  Gauge(name, value, attrs)
}

fn histogram(name :: Str, value :: Float, attrs :: List[(Str, Str)]) -> Metric {
  Histogram(name, value, attrs)
}

fn metric_name(m :: Metric) -> Str {
  match m {
    Counter(n, _, _)   => n,
    Gauge(n, _, _)     => n,
    Histogram(n, _, _) => n,
  }
}
