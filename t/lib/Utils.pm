package t::lib::Utils;

use strict;
use warnings;
use Module::Faker;
use Path::Tiny qw< path >;
use Pakket::Log;
use Log::Any::Adapter;

Log::Any::Adapter->set(
    'Dispatch',
    'dispatcher' => Pakket::Log->arg_default_logger(),
);

sub generate_modules {
    my $fake_dist_dir = Path::Tiny->tempdir();

    Module::Faker->make_fakes(
        {
            'source' => path(qw< t corpus fake_perl_mods>),
            'dest'   => $fake_dist_dir,
        },
    );

    return $fake_dist_dir;
}

sub config {
    return +{
        'repositories' => {
            'spec'   => [ 'File' => ( 'directory' => Path::Tiny->tempdir() ) ],
            'source' => [ 'File' => ( 'directory' => Path::Tiny->tempdir() ) ],
            'parcel' => [ 'File' => ( 'directory' => Path::Tiny->tempdir() ) ],
        },
    };
}

1;
