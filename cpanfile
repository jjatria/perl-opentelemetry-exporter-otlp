requires 'isa'; # To support perls older than 5.32
requires 'Feature::Compat::Try';
requires 'Future::AsyncAwait', '0.38'; # Object::Pad compatibility
requires 'File::Share';
requires 'HTTP::Tiny';
requires 'JSON::MaybeXS';
requires 'Metrics::Any';
requires 'Object::Pad', '0.74'; # For //= field initialisers
requires 'OpenTelemetry', '0.010';
requires 'Path::Tiny';
requires 'Syntax::Keyword::Dynamically';
requires 'Syntax::Keyword::Match';
requires 'Time::Piece';

recommends 'Compress::Zlib';
recommends 'Google::ProtocolBuffers::Dynamic';

on test => sub {
    requires 'Test2::V0';
};
