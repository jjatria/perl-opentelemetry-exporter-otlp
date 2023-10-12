#!/usr/bin/env perl

use Log::Any::Adapter 'Stderr';
use Test2::V0 -target => 'OpenTelemetry::Exporter::OTLP';

use HTTP::Tiny;
use OpenTelemetry::Constants -trace_export, -span_kind, -span_status;
use OpenTelemetry::Trace::SpanContext;
use OpenTelemetry::SDK::Trace::Span::Readable;
use OpenTelemetry::SDK::Resource;
use OpenTelemetry::SDK::InstrumentationScope;
use OpenTelemetry::Trace::Span::Status;

my $guard = mock 'HTTP::Tiny' => override => [
    request => sub { +{ success => 1 } },
];

my $a_scope = OpenTelemetry::SDK::InstrumentationScope->new( name => 'A' );
my $b_scope = OpenTelemetry::SDK::InstrumentationScope->new( name => 'B' );

my $a_resource = OpenTelemetry::SDK::Resource->new( attributes => { name => 'A' } );
my $b_resource = OpenTelemetry::SDK::Resource->new( attributes => { name => 'B' } );

is CLASS->new->export([
    OpenTelemetry::SDK::Trace::Span::Readable->new(
        context               => OpenTelemetry::Trace::SpanContext->new,
        end_timestamp         => 100,
        instrumentation_scope => $a_scope,
        kind                  => SPAN_KIND_INTERNAL,
        name                  => 'A-A',
        resource              => $a_resource,
        start_timestamp       => 0,
        status                => OpenTelemetry::Trace::Span::Status->ok,
    ),
    OpenTelemetry::SDK::Trace::Span::Readable->new(
        context               => OpenTelemetry::Trace::SpanContext->new,
        end_timestamp         => 100,
        instrumentation_scope => $a_scope,
        kind                  => SPAN_KIND_INTERNAL,
        name                  => 'A-B',
        resource              => $b_resource,
        start_timestamp       => 0,
        status                => OpenTelemetry::Trace::Span::Status->ok,
    ),
    OpenTelemetry::SDK::Trace::Span::Readable->new(
        context               => OpenTelemetry::Trace::SpanContext->new,
        end_timestamp         => 100,
        instrumentation_scope => $b_scope,
        kind                  => SPAN_KIND_INTERNAL,
        name                  => 'B-A',
        resource              => $a_resource,
        start_timestamp       => 0,
        status                => OpenTelemetry::Trace::Span::Status->ok,
    ),
    OpenTelemetry::SDK::Trace::Span::Readable->new(
        context               => OpenTelemetry::Trace::SpanContext->new,
        end_timestamp         => 100,
        instrumentation_scope => $b_scope,
        kind                  => SPAN_KIND_INTERNAL,
        name                  => 'B-B',
        resource              => $b_resource,
        start_timestamp       => 0,
        status                => OpenTelemetry::Trace::Span::Status->ok,
    ),
]), TRACE_EXPORT_SUCCESS;

done_testing;
