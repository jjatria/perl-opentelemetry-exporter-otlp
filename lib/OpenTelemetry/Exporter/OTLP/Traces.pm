use Object::Pad ':experimental(init_expr)';
# ABSTRACT: An OpenTelemetry Protocol span exporter

package OpenTelemetry::Exporter::OTLP::Traces;

our $VERSION = '0.016002';

class OpenTelemetry::Exporter::OTLP::Traces :isa(OpenTelemetry::Exporter::OTLP) {}
