requires 'Feature::Compat::Try';
requires 'File::Share';
requires 'HTTP::Tiny';
requires 'JSON::MaybeXS';
requires 'Metrics::Any';
requires 'Object::Pad';
requires 'OpenTelemetry';
requires 'Path::Tiny';
requires 'Syntax::Keyword::Dynamically';
requires 'Syntax::Keyword::Match';
requires 'Time::Piece';

recommends 'Compress::Zlib';
recommends 'Google::ProtocolBuffers::Dynamic';

on test => sub {
    requires 'Test2::V0';
};
