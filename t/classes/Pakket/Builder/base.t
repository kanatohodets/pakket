use strict;
use warnings;
use Test::More 'tests' => 3;
use Test::Fatal;
use lib '.'; use t::lib::Utils;
use Pakket::Builder;
use Pakket::Package;
use Path::Tiny qw< path >;
use Archive::Any;

sub create_builder {
    return Pakket::Builder->new( 'config' => t::lib::Utils::config() );
}

can_ok(
    Pakket::Builder::,
    qw<
        build bootstrap_build run_build snapshot_build_dir
        retrieve_new_files get_configure_flags
    >,
);

subtest 'Defaults' => sub {
    my $builder = create_builder();
    isa_ok( $builder, 'Pakket::Builder' );
    isa_ok( $builder->source_repo, 'Pakket::Repository::Source' );

    isa_ok(
        $builder->source_repo->backend,
        'Pakket::Repository::Backend::File',
    );
};

subtest 'Build simple module' => sub {
    my $builder       = create_builder();
    my $fake_dist_dir = t::lib::Utils::generate_modules();

    # Unpack each one
    foreach my $tarball ( $fake_dist_dir->children ) {
        my $archive = Archive::Any->new($tarball);
        ok( $archive->extract($fake_dist_dir), 'Extracted successfully' );

        # Import each one
        my ($dir_name) = "$tarball" =~ s{ \.tar \.gz $}{}rxms;
        my $source_dir = path($dir_name);
        ok( $source_dir->is_dir, 'Got directory' );

        my ($dist_name) = $source_dir->basename =~ s{ -0\.01 $}{}rxms;

        $builder->source_repo->store_package_source(
            Pakket::Package->new(
                'category' => 'perl',
                'name'     => $dist_name,
                'version'  => '0.01',
                'release'  => 1,
            ),
            $source_dir,
        );
    }
};
