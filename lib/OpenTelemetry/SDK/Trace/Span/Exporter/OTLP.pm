use Object::Pad ':experimental(init_expr)';
# ABSTRACT: An OpenTelemetry Protocol span exporter

package OpenTelemetry::SDK::Trace::Span::Exporter::OTLP;

our $VERSION = '0.001';

class OpenTelemetry::SDK::Trace::Span::Exporter::OTLP :does(OpenTelemetry::SDK::Trace::Span::Exporter) {
    use Future::AsyncAwait;

    use Scalar::Util 'refaddr';
    use OpenTelemetry;
    use OpenTelemetry::Proto;
    use OpenTelemetry::Constants -trace_export;

    my $logger = OpenTelemetry->logger;

    field $stopped;

    my sub as_otlp_attributes ( $hash ) {
        [
            map {
                {
                    key   => $_,
                    value => {
                        string_value => $hash->{$_},
                    },
                };
            } keys %$hash,
        ];
    }

    my sub as_otlp_resource ( $resource ) {
        {
            attributes               => as_otlp_attributes( $resource->attributes ),
            dropped_attributes_count => 0,
        };
    }

    my sub as_otlp_event ( $event ) {
        {
            time_unix_nano           => $event->timestamp * 1_000_000_000,
            name                     => $event->name,
            attributes               => as_otlp_attributes($event->attributes),
            dropped_attributes_count => 0,
        };
    }

    my sub as_otlp_link ( $link ) {
        {
            trace_id                 => $link->context->trace_id,
            span_id                  => $link->context->span_id,
            attributes               => as_otlp_attributes($link->attributes),
            dropped_attributes_count => 0,
        };
    }

    my sub as_otlp_status ( $status ) {
        {
            code    => $status->code,
            message => $status->description,
        };
    }

    my sub as_otlp_span ( $span ) {
        {
            trace_id                 => $span->trace_id,
            span_id                  => $span->span_id,
            trace_state              => $span->trace_state->to_string,
            parent_span_id           => $span->parent_span_id,
            name                     => $span->name,
            kind                     => $span->kind,
            start_time_unix_nano     => $span->start_timestamp * 1_000_000_000,
            end_time_unix_nano       => $span->end_timestamp   * 1_000_000_000,
            attributes               => as_otlp_attributes($span->attributes),
            events                   => [ map as_otlp_event($_), $span->events ],
            links                    => [ map as_otlp_link($_),  $span->links  ],
            status                   => as_otlp_status($span->status),
            dropped_attributes_count => 0,
            dropped_events_count     => 0,
            dropped_links_count      => 0,
        };
    }

    my sub as_otlp_scope ( $scope ) {
        {
            name                     => $scope->name,
            version                  => $scope->version,
            attributes               => as_otlp_attributes( $scope->attributes ),
            dropped_attributes_count => 0,
        };
    }

    method $send_bytes ( $data, $timeout ) {
        $logger->trace('Boop beep boop, sending bytes');
        $logger->trace($data->encode_json);
        return TRACE_EXPORT_SUCCESS;
    }

    method $encode ( $spans ) {
        my ( %request, %resources );

        for (@$spans) {
            my $key = refaddr $_->resource;
            $resources{ $key } //= [ $_->resource, [] ];
            push @{ $resources{ $key }[1] }, $_;
        }

        for ( keys %resources ) {
            my ( $resource, $spans ) = @{ $resources{$_} };

            my %scopes;

            for (@$spans) {
                my $key = refaddr $_->instrumentation_scope;

                $scopes{ $key } //= [ $_->instrumentation_scope, [] ];
                push @{ $scopes{ $key }[1] }, $_;
            }

            push @{ $request{resource_spans} //= [] }, {
                resource => as_otlp_resource($resource),
                scope_spans => [
                    map {
                        my ( $scope, $spans ) = @$_;
                        {
                            scope => as_otlp_scope($scope),
                            spans => [ map as_otlp_span($_), @$spans ],
                        };
                    } values %scopes,
                ],
                schema_url => $resource->schema_url,
            };
        }

        OpenTelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest
            ->new_and_check(\%request);
    }

    async method export ( $spans, $timeout = undef ) {
        return TRACE_EXPORT_FAILURE if $stopped;
        $self->$send_bytes( $self->$encode($spans), $timeout );
    }

    async method shutdown ( $timeout = undef ) {
        $stopped = 1;
        TRACE_EXPORT_SUCCESS;
    }

    async method force_flush ( $timeout = undef ) {
        TRACE_EXPORT_SUCCESS;
    }
}
