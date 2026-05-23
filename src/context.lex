# context.lex — trace context: IDs and W3C traceparent propagation.
#
# TraceCtx flows through every instrumented call so spans compose across
# service boundaries. Pass it in HTTP request headers via to_header/from_header.
#
# W3C traceparent format: "00-{32-hex trace_id}-{16-hex span_id}-{flags}"
# https://www.w3.org/TR/trace-context/

import "std.str" as str
import "std.crypto" as crypto
import "std.list" as list

type TraceCtx = {
  trace_id :: Str,   # 32 lowercase hex chars
  span_id  :: Str,   # 16 lowercase hex chars
  sampled  :: Bool,
}

# A no-op context used when no parent context exists and sampling is off.
fn empty() -> TraceCtx {
  { trace_id: "00000000000000000000000000000000", span_id: "0000000000000000", sampled: false }
}

fn is_empty(ctx :: TraceCtx) -> Bool {
  str.eq(ctx.trace_id, "00000000000000000000000000000000")
}

fn strip_dashes(s :: Str) -> Str {
  str.join(str.split(s, "-"), "")
}

# Start a new root trace.
fn new_root() -> [crypto] TraceCtx {
  {
    trace_id: strip_dashes(crypto.uuid()),
    span_id:  str.take(strip_dashes(crypto.uuid()), 16),
    sampled:  true,
  }
}

# Derive a child span — same trace_id, new span_id.
fn child(parent :: TraceCtx) -> [crypto] TraceCtx {
  {
    trace_id: parent.trace_id,
    span_id:  str.take(strip_dashes(crypto.uuid()), 16),
    sampled:  parent.sampled,
  }
}

# Serialise to W3C traceparent header value.
fn to_header(ctx :: TraceCtx) -> Str {
  let flags := if ctx.sampled { "01" } else { "00" }
  str.concat("00-", str.concat(ctx.trace_id, str.concat("-", str.concat(ctx.span_id, str.concat("-", flags)))))
}

# Parse a W3C traceparent header value. Returns None if malformed.
fn from_header(header :: Str) -> Option[TraceCtx] {
  let parts := str.split(header, "-")
  match parts {
    [_version, trace_id, span_id, flags | _] =>
      if str.length(trace_id) == 32 && str.length(span_id) == 16 {
        Some({
          trace_id: trace_id,
          span_id:  span_id,
          sampled:  str.eq(flags, "01"),
        })
      } else {
        None
      },
    _ => None,
  }
}
