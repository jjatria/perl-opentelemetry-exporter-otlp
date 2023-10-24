#!/usr/bin/env perl

use Test2::Require::Module 'Google::ProtocolBuffers::Dynamic';
use Test2::V0 -target => 'OpenTelemetry::Exporter::OTLP::Encoder::Protobuf';

use JSON::MaybeXS;
use OpenTelemetry::Constants -trace_export, -span_kind, -span_status;
use OpenTelemetry::Trace::SpanContext;
use OpenTelemetry::SDK::Trace::Span::Readable;
use OpenTelemetry::SDK::Resource;
use OpenTelemetry::SDK::InstrumentationScope;
use OpenTelemetry::Trace::Span::Status;

my $a_scope = OpenTelemetry::SDK::InstrumentationScope->new( name => 'A' );
my $b_scope = OpenTelemetry::SDK::InstrumentationScope->new( name => 'B' );

my $a_resource = OpenTelemetry::SDK::Resource->new( attributes => { name => 'A' } );
my $b_resource = OpenTelemetry::SDK::Resource->new( attributes => { name => 'B' } );


my $encoded = CLASS->new->encode([
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
]);

my $decoded = OpenTelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest->decode($encoded);

is decode_json($decoded->encode_json), {
    resourceSpans => array {
        prop size => 2;
        all_items {
            resource => {
                attributes => array {
                    all_items {
                        key   => T,
                        value => in_set(
                            { stringValue => T },
                            { arrayValue  => T },
                        ),
                    };
                    etc; # attributes
                },
            },
            scopeSpans => array {
                prop size => 2;
                all_items {
                    scope => {
                        name                     => match qr/[AB]/,
                    },
                    spans => [
                        {
                            endTimeUnixNano       => E,
                            kind                     => 'SPAN_KIND_INTERNAL',
                            name                     => match qr/[AB]-[AB]/,
                            spanId                  => match qr/[0-9a-zA-Z=+]+/,
                            traceId                 => match qr/[0-9a-zA-Z=+]+/,
                            status => {
                                code    => 'STATUS_CODE_OK',
                            },
                        },
                    ],
                };
                etc; # scope_spans
            },
        };
        etc; # resource_spans
    },
};

done_testing;
