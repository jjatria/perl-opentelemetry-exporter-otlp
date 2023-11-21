use Object::Pad ':experimental(init_expr)';
# ABSTRACT: A JSON encoder for the OTLP exporter

package OpenTelemetry::Exporter::OTLP::Encoder::JSON;

our $VERSION = '0.013';

class OpenTelemetry::Exporter::OTLP::Encoder::JSON {
    use JSON::MaybeXS;
    use MIME::Base64;
    use OpenTelemetry::Constants 'INVALID_SPAN_ID';
    use Ref::Util 'is_arrayref';
    use Scalar::Util 'refaddr';

    method content_type () { 'application/json' }

    method serialise ($data) { encode_json $data }

    method encode_id ( $id ) {
        MIME::Base64::encode_base64( $id, '' )
    }

    method encode_single_value ( $v ) {
        { stringValue => $v }
    }

    method encode_value ( $v ) {
        is_arrayref $v
            ? { arrayValue => { values => [ map $self->encode_single_value($_), @$v ] } }
            : $self->encode_single_value($v)
    }

    method encode_attributes ( $hash ) {
        [
            map {
                {
                    key   => $_,
                    value => $self->encode_value($hash->{$_}),
                };
            } keys %$hash,
        ];
    }

    method encode_resource ( $resource ) {
        {
            attributes             => $self->encode_attributes( $resource->attributes ),
            droppedAttributesCount => $resource->dropped_attributes,
        };
    }

    method encode_event ( $event ) {
        {
            attributes             => $self->encode_attributes($event->attributes),
            droppedAttributesCount => $event->dropped_attributes,
            name                   => $event->name,
            timeUnixNano           => int($event->timestamp * 1_000_000_000),
        };
    }

    method encode_link ( $link ) {
        {
            attributes             => $self->encode_attributes($link->attributes),
            droppedAttributesCount => $link->dropped_attributes,
            spanId                 => $link->context->hex_span_id,
            traceId                => $link->context->hex_trace_id,
        };
    }

    method encode_status ( $status ) {
        {
            code    => $status->code,
            message => $status->description,
        };
    }

    method encode_span ( $span ) {
        my $data = {
            attributes             => $self->encode_attributes($span->attributes),
            droppedAttributesCount => $span->dropped_attributes,
            droppedEventsCount     => $span->dropped_events,
            droppedLinksCount      => $span->dropped_links,
            endTimeUnixNano        => int($span->end_timestamp * 1_000_000_000),
            events                 => [map $self->encode_event($_), $span->events],
            kind                   => $span->kind,
            links                  => [ map $self->encode_link($_),  $span->links  ],
            name                   => $span->name,
            spanId                 => $span->hex_span_id,
            startTimeUnixNano      => int($span->start_timestamp * 1_000_000_000),
            status                 => $self->encode_status($span->status),
            traceId                => $span->hex_trace_id,
            traceState             => $span->trace_state->to_string,
        };

        my $parent = $span->hex_parent_span_id;
        $data->{parent_span_id} = $span->hex_parent_span_id
          unless $parent eq INVALID_SPAN_ID;

        $data;
    }

    method encode_scope ( $scope ) {
        {
            attributes             => $self->encode_attributes( $scope->attributes ),
            droppedAttributesCount => $scope->dropped_attributes,
            name                   => $scope->name,
            version                => $scope->version,
        };
    }

    method encode_scope_spans ( $scope, $spans ) {
        {
            scope => $self->encode_scope($scope),
            spans => [ map $self->encode_span($_), @$spans ],
        };
    }

    method encode_resource_spans ( $resource, $spans ) {
        my %scopes;

        for (@$spans) {
            my $key = refaddr $_->instrumentation_scope;

            $scopes{ $key } //= [ $_->instrumentation_scope, [] ];
            push @{ $scopes{ $key }[1] }, $_;
        }

        {
            resource => $self->encode_resource($resource),
            scopeSpans => [
                map $self->encode_scope_spans(@$_), values %scopes,
            ],
            schemaUrl => $resource->schema_url,
        };
    }

    method encode ( $spans ) {
        my ( %request, %resources );

        for (@$spans) {
            my $key = refaddr $_->resource;
            $resources{ $key } //= [ $_->resource, [] ];
            push @{ $resources{ $key }[1] }, $_;
        }

        $self->serialise({
            resourceSpans => [
                map $self->encode_resource_spans(@$_), values %resources,
            ]
        });
    }
}
