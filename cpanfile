requires 'File::Share';
requires 'JSON::MaybeXS';
requires 'Metrics::Any';
requires 'Object::Pad';
requires 'Path::Tiny';

recommends 'Compress::Zlib';
recommends 'Google::ProtocolBuffers::Dynamic';

on test => sub {
    requires 'Test2::V0';
};
