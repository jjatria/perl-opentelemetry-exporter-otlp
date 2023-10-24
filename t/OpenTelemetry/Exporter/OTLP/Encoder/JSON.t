#!/usr/bin/env perl

use Test2::V0 -target => 'OpenTelemetry::Exporter::OTLP::Encoder::JSON';

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

is decode_json(CLASS->new->encode([
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
])), {
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
                droppedAttributesCount => 0,
            },
            schemaUrl => '',
            scopeSpans => array {
                prop size => 2;
                all_items {
                    scope => {
                        attributes             => [],
                        droppedAttributesCount => 0,
                        name                   => match qr/[AB]/,
                        version                => '',
                    },
                    spans => [
                        {
                            attributes             => [],
                            droppedAttributesCount => 0,
                            droppedEventsCount     => 0,
                            droppedLinksCount      => 0,
                            endTimeUnixNano        => E,
                            events                 => [],
                            kind                   => SPAN_KIND_INTERNAL,
                            links                  => [],
                            name                   => match qr/[AB]-[AB]/,
                            spanId                 => match qr/[0-9a-zA-Z=+]+/,
                            startTimeUnixNano      => E,
                            traceId                => match qr/[0-9a-zA-Z=+]+/,
                            traceState             => '',
                            status => {
                                code    => SPAN_STATUS_OK,
                                message => '',
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
