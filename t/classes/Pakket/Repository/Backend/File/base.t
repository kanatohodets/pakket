use strict;
use warnings;
use Test::More 'tests' => 4;
use Test::Fatal;
use Path::Tiny qw< path >;
use Pakket::Repository::Backend::File;

can_ok(
    Pakket::Repository::Backend::File::,
    qw< directory file_extension index_file >,
);

my $index_dir = path( qw< t corpus indexes > );

like(
    exception { Pakket::Repository::Backend::File->new() },
    qr{^ Attribute \s \(directory\) \s is \s required \s at \s constructor}xms,
    'directory is required to create a new File backend class',
);

is(
    exception {
        Pakket::Repository::Backend::File->new(
            'directory' => $index_dir->stringify,
        );
    },
    undef,
    'directory attribute can be a string',
);

is(
    exception {
        Pakket::Repository::Backend::File->new( 'directory' => $index_dir );
    },
    undef,
    'directory attribute can be a Path::Tiny object',
);
