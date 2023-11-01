package OpenTelemetry::Proto;
# ABSTRACT: foo

our $VERSION = '0.010';

use experimental 'signatures';

use File::Share 'dist_file';
use Path::Tiny 'path';
use Google::ProtocolBuffers::Dynamic;

my $g = Google::ProtocolBuffers::Dynamic->new('proto');

# Generated with
#
#     find . -name "*.proto" | while read proto; do
#        protoc --experimental_allow_proto3_optional -Iproto -o "$( echo ${proto%%.proto}.pb | sed -re 's/^\.\/proto/share/' )" $proto;
#     done
for my $proto (qw(
    opentelemetry/proto/common/v1/common.pb
    opentelemetry/proto/resource/v1/resource.pb
    opentelemetry/proto/trace/v1/trace.pb
    opentelemetry/proto/metrics/v1/metrics.pb
    opentelemetry/proto/logs/v1/logs.pb

    opentelemetry/proto/collector/logs/v1/logs_service.pb
    opentelemetry/proto/collector/metrics/v1/metrics_service.pb
    opentelemetry/proto/collector/trace/v1/trace_service.pb
)) {
    my $path = dist_file(
        'OpenTelemetry-Exporter-OTLP',
        $proto,
    );

    # my $path = "share/$proto";

    $g->load_serialized_string( path($path)->slurp );

    my @parts = split '/', $proto;
    pop @parts;

    $g->map({
        package => join('.', @parts ),
        prefix  => join( '::', map ucfirst, @parts ) =~ s/^Opente/OpenTe/r,
    });
}

1;
