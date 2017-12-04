## no critic
use strict;
use warnings;
use Test::More 'tests' => 5;
use Pakket::Package;
use Pakket::Repository::Spec;
use lib '.'; use t::lib::Utils;

my $config = t::lib::Utils::config();
my $repo;

subtest 'Setup' => sub {
    isa_ok( $config, 'HASH' );
    my $spec_params;
    ok( $spec_params = $config->{'repositories'}{'spec'},
        'Got spec repo params' );

    isa_ok(
        $repo = Pakket::Repository::Spec->new( 'backend' => $spec_params ),
        'Pakket::Repository::Spec',
    );
};

# FIXME: Add release test too
my @versions = qw<
    1.0
    1.2
    1.2.1
    1.2.2
    1.2.3
    2.0
    2.0.1
    3.1
>;

subtest 'Add packages' => sub {
    foreach my $version (@versions) {
        $repo->store_package_spec(
            Pakket::Package->new(
                'name'     => 'My-Package',
                'category' => 'perl',
                'version'  => $version,
                'release'  => 1,
            ),
        );
    }

    my @all_objects = sort @{ $repo->all_object_ids };
    is_deeply(
        \@all_objects,
        [
            'perl/My-Package=1.0:1',
            'perl/My-Package=1.2:1',
            'perl/My-Package=2.0:1',
            'perl/My-Package=3.1:1',
            'perl/My-Package=v1.2.1:1',
            'perl/My-Package=v1.2.2:1',
            'perl/My-Package=v1.2.3:1',
            'perl/My-Package=v2.0.1:1',
        ],
        'All packages added correctly',
    );
};

subtest 'Find latest version' => sub {
    my ($ver_rel) = $repo->latest_version_release(
        'perl', 'My-Package', '>= 2.0',
    );

    is_deeply( $ver_rel, [ '3.1', '1' ], 'Latest version and release' );
};

subtest 'Find latest versions (with range)' => sub {
    my ($ver_rel) = $repo->latest_version_release(
        'perl', 'My-Package', '>= 2.0, < 3.0',
    );

    is_deeply( $ver_rel, [ 'v2.0.1', '1' ], 'Latest version and release' );
};

subtest 'Find latest versions (with range and NOT)' => sub {
    my ($ver_rel) = $repo->latest_version_release(
        'perl', 'My-Package', '>= 2.0, < 3.0, != 2.0.1',
    );

    is_deeply( $ver_rel, [ '2.0', '1' ], 'Latest version and release' );
};
