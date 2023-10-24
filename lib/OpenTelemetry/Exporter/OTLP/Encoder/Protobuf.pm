use Object::Pad ':experimental(init_expr)';
# ABSTRACT: An OpenTelemetry Protocol span exporter

package OpenTelemetry::Exporter::OTLP::Encoder::Protobuf;

our $VERSION = '0.001';

class OpenTelemetry::Exporter::OTLP::Encoder::Protobuf
    :isa(OpenTelemetry::Exporter::OTLP::Encoder::JSON) {

    use OpenTelemetry::Constants 'INVALID_SPAN_ID';
    use OpenTelemetry::Proto;
    use Ref::Util 'is_arrayref';
    use Scalar::Util 'refaddr';

    method content_type () { 'application/x-protobuf' }

    method serialise ($data) {
        OpenTelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest
            ->new_and_check({ resource_spans => $data->{resourceSpans} })->encode;
    }

    method encode_single_value ( $v ) {
        { string_value => $v }
    }

    method encode_value ( $v ) {
        is_arrayref $v
            ? { array_value => { values => [ map $self->encode_single_value($_), @$v ] } }
            : $self->encode_single_value($v)
    }

    method encode_resource ( $resource ) {
        {
            attributes               => $self->encode_attributes( $resource->attributes ),
            dropped_attributes_count => $resource->dropped_attributes,
        };
    }

    method encode_event ( $event ) {
        {
            attributes               => $self->encode_attributes($event->attributes),
            dropped_attributes_count => $event->dropped_attributes,
            name                     => $event->name,
            time_unix_nano           => $event->timestamp * 1_000_000_000,
        };
    }

    method encode_link ( $link ) {
        {
            attributes               => $self->encode_attributes($link->attributes),
            dropped_attributes_count => $link->dropped_attributes,
            span_id                  => $self->encode_id( $link->context->span_id ),
            trace_id                 => $self->encode_id( $link->context->trace_id ),
        };
    }

    method encode_span ( $span ) {
        my $data = {
            attributes               => $self->encode_attributes($span->attributes),
            dropped_attributes_count => $span->dropped_attributes,
            dropped_events_count     => $span->dropped_events,
            dropped_links_count      => $span->dropped_links,
            end_time_unix_nano       => $span->end_timestamp   * 1_000_000_000,
            events                   => [ map $self->encode_event($_), $span->events ],
            kind                     => $span->kind,
            links                    => [ map $self->encode_link($_),  $span->links  ],
            name                     => $span->name,
            span_id                  => $self->encode_id( $span->span_id ),
            start_time_unix_nano     => $span->start_timestamp * 1_000_000_000,
            status                   => $self->encode_status($span->status),
            trace_id                 => $self->encode_id( $span->trace_id ),
            trace_state              => $span->trace_state->to_string,
        };

        my $parent = $span->parent_span_id;
        $data->{parent_span_id} = encode_id($parent)
            unless $parent eq INVALID_SPAN_ID;

        $data;
    }

    method encode_scope ( $scope ) {
        {
            attributes               => $self->encode_attributes( $scope->attributes ),
            dropped_attributes_count => $scope->dropped_attributes,
            name                     => $scope->name,
            version                  => $scope->version,
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
            scope_spans => [
                map $self->encode_scope_spans(@$_), values %scopes,
            ],
            schema_url => $resource->schema_url,
        };
    }
}
