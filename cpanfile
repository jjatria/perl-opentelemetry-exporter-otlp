requires 'Compress::Zlib';
requires 'File::Share';
requires 'Google::ProtocolBuffers::Dynamic';
requires 'Metrics::Any';
requires 'Object::Pad';
requires 'OpenTelemetry::SDK';
requires 'Path::Tiny';

on test => sub {
    requires 'Test2::V0';
};
