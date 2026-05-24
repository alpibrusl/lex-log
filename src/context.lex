# context.lex — trace context: IDs and W3C traceparent propagation.
#
# TraceCtx flows through every instrumented call so spans compose across
# service boundaries. Pass it in HTTP request headers via to_header/from_header.
#
# W3C traceparent format: "00-{32-hex trace_id}-{16-hex span_id}-{flags}"
# https://www.w3.org/TR/trace-context/

import "std.str" as str

import "std.crypto" as crypto

type TraceCtx = { trace_id :: Str, span_id :: Str, sampled :: Bool }

# A no-op context used when no parent context exists and sampling is off.
fn empty() -> TraceCtx {
  { trace_id: "00000000000000000000000000000000", span_id: "0000000000000000", sampled: false }
}

fn is_empty(ctx :: TraceCtx) -> Bool
  examples {
    is_empty(empty()) => true
  }
{
  ctx.trace_id == "00000000000000000000000000000000"
}

# Start a new root trace. 16 random bytes render to a 32-hex trace_id;
# 8 bytes to a 16-hex span_id — exactly the W3C field widths.
fn new_root() -> [random] TraceCtx {
  { trace_id: crypto.random_str_hex(16), span_id: crypto.random_str_hex(8), sampled: true }
}

# Derive a child span — same trace_id, new span_id.
fn child(parent :: TraceCtx) -> [random] TraceCtx {
  { trace_id: parent.trace_id, span_id: crypto.random_str_hex(8), sampled: parent.sampled }
}

# Serialise to W3C traceparent header value.
fn to_header(ctx :: TraceCtx) -> Str
  examples {
    to_header({ trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", sampled: true }) => "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
    to_header({ trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", sampled: false }) => "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00"
  }
{
  let flags := if ctx.sampled {
    "01"
  } else {
    "00"
  }
  str.concat("00-", str.concat(ctx.trace_id, str.concat("-", str.concat(ctx.span_id, str.concat("-", flags)))))
}

# Parse a W3C traceparent header value. Returns None if malformed.
#
# The header is fixed-width — "00-" + 32 + "-" + 16 + "-" + 2 = 55 bytes
# — so we slice by offset rather than splitting, and verify the three
# dash separators land where the spec says they do.
fn from_header(header :: Str) -> Option[TraceCtx]
  examples {
    from_header("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01") => Some({ trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", sampled: true }),
    from_header("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00") => Some({ trace_id: "0af7651916cd43dd8448eb211c80319c", span_id: "b7ad6b7169203331", sampled: false }),
    from_header("garbage") => None
  }
{
  if str.len(header) == 55 {
    let dash1 := str.slice(header, 2, 3)
    let dash2 := str.slice(header, 35, 36)
    let dash3 := str.slice(header, 52, 53)
    if dash1 == "-" and dash2 == "-" and dash3 == "-" {
      Some({ trace_id: str.slice(header, 3, 35), span_id: str.slice(header, 36, 52), sampled: str.slice(header, 53, 55) == "01" })
    } else {
      None
    }
  } else {
    None
  }
}

