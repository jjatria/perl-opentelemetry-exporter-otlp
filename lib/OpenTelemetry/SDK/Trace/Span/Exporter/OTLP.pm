use Object::Pad ':experimental(init_expr)';
# ABSTRACT: An OpenTelemetry Protocol span exporter

package OpenTelemetry::SDK::Trace::Span::Exporter::OTLP;

our $VERSION = '0.001';

class OpenTelemetry::SDK::Trace::Span::Exporter::OTLP :does(OpenTelemetry::SDK::Trace::Span::Exporter) {
    use Compress::Zlib;
    use Future::AsyncAwait;
    use HTTP::Tiny;
    use OpenTelemetry::Common 'config';
    use OpenTelemetry::Constants -trace_export;
    use OpenTelemetry::Proto;
    use OpenTelemetry::X;
    use OpenTelemetry;
    use Ref::Util 'is_arrayref';
    use Scalar::Util 'refaddr';
    use URL::Encode 'url_decode';

    use Metrics::Any '$metrics', strict => 0;
    my $logger = OpenTelemetry->logger;

    field $stopped;
    field $ua;
    field $endpoint;
    field $compression :param = undef;

    ADJUSTPARAMS ($params) {
        $endpoint = delete $params->{endpoint}
            // config('EXPORTER_OTLP_TRACES_ENDPOINT');

        $endpoint //= do {
            my $base = config('EXPORTER_OTLP_ENDPOINT');
            $base
                ? ( ( $base =~ s|/+$||r ) . '/v1/traces' )
                : 'http://localhost:4318/v1/traces';
        };

        $compression
            //= config(qw( EXPORTER_OTLP_TRACES_COMPRESSION EXPORTER_OTLP_COMPRESSION ))
            // 'gzip';

        my $timeout = delete $params->{timeout}
            // config(qw( EXPORTER_OTLP_TRACES_TIMEOUT EXPORTER_OTLP_TIMEOUT ))
            // 10;

        my $headers = delete $params->{headers}
            // config(qw( EXPORTER_OTLP_TRACES_HEADERS EXPORTER_OTLP_HEADERS ))
            // {};

        $headers = {
            map {
                my ( $k, $v ) = map url_decode($_), split '=', $_, 2;
                $k =~ s/^\s+|\s+$//g;
                $v =~ s/^\s+|\s+$//g;
                $k => $v;
            } split ',', $headers
        } unless ref $headers;

        die OpenTelemetry::X->create(
            Invalid => "invalid url for OTLP exporter $endpoint"
        ) unless "$endpoint" =~ m|^https?://|;

        die OpenTelemetry::X->create(
            Invalid => "unsupported compression key $compression"
        ) unless $compression =~ /^(?:gzip|none)$/;

        $ua = HTTP::Tiny->new(
            timeout         => $timeout,
            default_headers => {
                %$headers,
                'Content-Type' => 'application/x-protobuf',
            },
        );
    }

    my sub as_otlp_single_value ( $v ) {
        { string_value => $v }
    }

    my sub as_otlp_value ( $v ) {
        is_arrayref $v
            ? { array_value => { values => [ map as_otlp_single_value($_), @$v ] } }
            : as_otlp_single_value($v)
    }

    my sub as_otlp_attributes ( $hash ) {
        [
            map {
                {
                    key   => $_,
                    value => as_otlp_value($hash->{$_}),
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

    my sub make_request ( $spans ) {
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

    method $send_request ( $data, $timeout ) {
        # TODO: timeouts, redirection, more error handling, and retries

        my %request = ( content => $data->encode );

        $metrics->report_distribution(
            'otel.otlp_exporter.message.uncompressed_size',
            length $request{content},
        );

        if ( $compression eq 'gzip' ) {
            $request{headers}{'Content-Encoding'} = 'gzip';
            $request{content} = Compress::Zlib::memGzip($request{content})
                or die "Error comnpressing data: $gzerrno";

            $metrics->report_distribution(
                'otel.otlp_exporter.message.compressed_size',
                length $request{content},
            );
        }

        use Data::Dumper;
        my $res = $ua->post( $endpoint, \%request );
        warn Dumper $res;

        return TRACE_EXPORT_SUCCESS;
    }

    async method export ( $spans, $timeout = undef ) {
        return TRACE_EXPORT_FAILURE if $stopped;

        my $request = make_request($spans);
        $self->$send_request( $request, $timeout );
    }

    async method shutdown ( $timeout = undef ) {
        $stopped = 1;
        TRACE_EXPORT_SUCCESS;
    }

    async method force_flush ( $timeout = undef ) {
        TRACE_EXPORT_SUCCESS;
    }
}
