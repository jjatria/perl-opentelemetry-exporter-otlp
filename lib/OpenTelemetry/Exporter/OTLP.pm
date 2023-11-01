use Object::Pad ':experimental(init_expr)';
# ABSTRACT: An OpenTelemetry Protocol span exporter

package OpenTelemetry::Exporter::OTLP;

our $VERSION = '0.010';

class OpenTelemetry::Exporter::OTLP :does(OpenTelemetry::Exporter) {
    use Feature::Compat::Try;
    use HTTP::Tiny;
    use OpenTelemetry::Common 'config';
    use OpenTelemetry::Constants -trace_export;
    use OpenTelemetry::Context;
    use OpenTelemetry::Trace;
    use OpenTelemetry::X;
    use OpenTelemetry;
    use Syntax::Keyword::Dynamically;
    use URL::Encode 'url_decode';

    my $PROTOCOL = eval {
        require 'Google::ProtocolBuffers::Dynamic';
        'http/protobuf';
    } // 'http/json';

    my $COMPRESSION = eval {
        require 'Compress::Zlib';
        'gzip';
    } // 'none';

    use Metrics::Any '$metrics', strict => 0;
    my $logger = OpenTelemetry->logger;

    field $stopped;
    field $ua;
    field $endpoint;
    field $compression :param = undef;
    field $encoder;

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
            // $COMPRESSION;

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
            Invalid => "invalid URL for OTLP exporter: $endpoint"
        ) unless "$endpoint" =~ m|^https?://|;

        die OpenTelemetry::X->create(
            Unsupported => "unsupported compression key for OTLP exporter: $compression"
        ) unless $compression =~ /^(?:gzip|none)$/;

        $headers->{'Content-Encoding'} = $compression unless $compression eq 'none';

        $encoder = do {
            my $protocol = delete $params->{protocol}
                // config('EXPORTER_OTLP_PROTOCOL')
                // $PROTOCOL;

            die OpenTelemetry::X->create(
                Unsupported => "unsupported protocol for OTLP exporter: $protocol",
            ) unless $protocol =~ /^http\/(protobuf|json)$/;

            my $class = 'OpenTelemetry::Exporter::OTLP::Encoder::';
            $class .= 'Protobuf' if $1 eq 'protobuf';
            $class .= 'JSON'     if $1 eq 'json';

            try {
                Module::Runtime::require_module $class;
                $class->new;
            }
            catch ($e) {
                $logger->warn(
                    'Could not load OTLP encoder class. Defaulting to JSON',
                    { class => $class, error => $e },
                );

                require OpenTelemetry::Exporter::OTLP::Encoder::JSON;
                OpenTelemetry::Exporter::OTLP::Encoder::JSON->new;
            }
        };

        $ua = HTTP::Tiny->new(
            timeout         => $timeout,
            default_headers => {
                %$headers,
                'Content-Type' => $encoder->content_type,
            },
        );
    }

    method $send_request ( $data, $timeout ) {
        # TODO: timeouts, redirection, more error handling, and retries

        my %request = ( content => $data );

        $metrics->report_distribution(
            'otel.otlp_exporter.message.uncompressed_size',
            length $request{content},
        );

        if ( $compression eq 'gzip' ) {
            require Compress::Zlib;
            $request{content} = Compress::Zlib::memGzip($request{content});

            unless ($request{content}) {
                OpenTelemetry->handle_error(
                    message => "Error compressing data: $Compress::Zlib::gzerrno"
                );

                $metrics->inc_counter(
                    'otel.otlp_exporter.failure',
                    { reason => 'zlib_error' },
                );

                return TRACE_EXPORT_FAILURE;
            }

            $metrics->report_distribution(
                'otel.otlp_exporter.message.compressed_size',
                length $request{content},
            );
        }

        my $res = $ua->post( $endpoint, \%request );

        return TRACE_EXPORT_SUCCESS if $res->{success};

        if ( $res->{status} == 404 ) {
            OpenTelemetry->handle_error(
                message => "OTLP exporter received HTTP code 404 Not Found for URI: '$endpoint'",
            );
        }

        $metrics->inc_counter(
            'otel.otlp_exporter.failure',
            { reason => $res->{status} },
        );

        return TRACE_EXPORT_FAILURE;
    }

    method export ( $spans, $timeout = undef ) {
        return TRACE_EXPORT_FAILURE if $stopped;

        dynamically OpenTelemetry::Context->current
            = OpenTelemetry::Trace->untraced_context;

        my $request = $encoder->encode($spans);
        $self->$send_request( $request, $timeout );
    }

    method shutdown ( $timeout = undef ) {
        $stopped = 1;
        TRACE_EXPORT_SUCCESS;
    }

    method force_flush ( $timeout = undef ) {
        TRACE_EXPORT_SUCCESS;
    }
}
