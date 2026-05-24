# meter.lex — metrics: counters, gauges, histograms.
#
# Metrics are values collected at a point in time and exported as a batch.
#
# Usage:
#   let m := meter.counter("http.requests", 1, [("method", "POST"), ("status", "200")])
#   exporter.export_metrics(cfg, [m])

type Metric = Counter((Str, Int, List[(Str, Str)])) | Gauge((Str, Float, List[(Str, Str)])) | Histogram((Str, Float, List[(Str, Str)]))

fn counter(name :: Str, delta :: Int, attrs :: List[(Str, Str)]) -> Metric
  examples {
    counter("http.requests", 1, []) => Counter("http.requests", 1, []),
    counter("bytes", 4, [("dir", "in")]) => Counter("bytes", 4, [("dir", "in")])
  }
{
  Counter(name, delta, attrs)
}

fn gauge(name :: Str, value :: Float, attrs :: List[(Str, Str)]) -> Metric
  examples {
    gauge("cpu.load", 0.5, []) => Gauge("cpu.load", 0.5, [])
  }
{
  Gauge(name, value, attrs)
}

fn histogram(name :: Str, value :: Float, attrs :: List[(Str, Str)]) -> Metric
  examples {
    histogram("req.latency_ms", 12.5, []) => Histogram("req.latency_ms", 12.5, [])
  }
{
  Histogram(name, value, attrs)
}

fn metric_name(m :: Metric) -> Str
  examples {
    metric_name(Counter("c", 1, [])) => "c",
    metric_name(Gauge("g", 1.0, [])) => "g",
    metric_name(Histogram("h", 1.0, [])) => "h"
  }
{
  match m {
    Counter(n, _, _) => n,
    Gauge(n, _, _) => n,
    Histogram(n, _, _) => n,
  }
}

