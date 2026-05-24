# lex_log.lex — public facade for lex-log.
#
# Import this file to get the full surface:
#   context, log, span, meter, exporter, instrument

import "./context" as context

import "./log" as log

import "./span" as span

import "./meter" as meter

import "./exporter" as exporter

import "./instrument" as instrument

type TraceCtx = context.TraceCtx

type LogRecord = log.LogRecord

type Span = span.Span

type SpanStatus = span.SpanStatus

type Metric = meter.Metric

type Level = log.Level

type Config = exporter.Config

type Scope = instrument.Scope

