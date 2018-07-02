package Pakket::Scaffolder::Perl;
# ABSTRACT: Scffolding Perl distributions

use Moose;
use MooseX::StrictConstructor;
use version 0.77;
use Carp ();
use Archive::Any;
use CPAN::DistnameInfo;
use CPAN::Meta;
use Parse::CPAN::Packages::Fast;
use JSON::MaybeXS       qw< decode_json encode_json >;
use Ref::Util           qw< is_arrayref is_hashref >;
use Path::Tiny          qw< path >;
use Types::Path::Tiny   qw< Path  >;
use Log::Any            qw< $log >;

use Pakket::Downloader::ByUrl;
use Pakket::Package;
use Pakket::Types;
use Pakket::Utils::Perl qw< should_skip_core_module >;
use Pakket::Constants   qw< PAKKET_PACKAGE_SPEC >;
use Pakket::Scaffolder::Perl::CPANfile;

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasSpecRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::CanApplyPatch
    Pakket::Role::Perl::BootstrapModules
    Pakket::Scaffolder::Perl::Role::Borked
    Pakket::Scaffolder::Role::Backend
    Pakket::Scaffolder::Role::Terminal
>;

has 'package' => (
    'is' => 'ro',
    'isa' => 'Pakket::PackageQuery',
);

has 'metacpan_api' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'lazy'    => 1,
    'builder' => '_build_metacpan_api',
);

has 'phases' => (
    'is'       => 'ro',
    'isa'      => 'ArrayRef[PakketPhase]',
    'required' => 1,
);

has 'modules' => (
    'is'  => 'ro',
    'isa' => 'HashRef',
);

has 'cache_dir' => (
    'is'        => 'ro',
    'isa'       => Path,
    'coerce'    => 1,
    'predicate' => '_has_cache_dir',
);

has 'file_02packages' => (
    'is'      => 'ro',
    'isa'     => 'Str',
);

has 'cpan_02packages' => (
    'is'      => 'ro',
    'isa'     => 'Parse::CPAN::Packages::Fast',
    'lazy'    => 1,
    'builder' => '_build_cpan_02packages',
);

has 'versioner' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Versioning',
    'lazy'    => 1,
    'builder' => '_build_versioner',
);

has 'no_deps' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'no_bootstrap' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'is_local' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'types' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub { [qw< requires recommends suggests >] },
);

has 'dist_name' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'meta_spec' => (
    'is'  => 'ro',
    'isa' => 'HashRef',
);

sub run {
    my ($self) = @_;
    my %failed;

    return if $self->_is_package_in_spec_repo($self->{package});

    $self->_bootstrap_toolchain;
    $self->_scaffold_package($self->package);
    $self->_scaffold_dependencies($self->package, \%failed);

    my $errors = keys %failed;
    if ($errors) {
        for my $f ( sort keys %failed ) {
            $log->errorf( "[FAILED] %s: %s", $f, $failed{$f} );
        }
    }
    return $errors;
}

sub _bootstrap_toolchain {
    my ($self) = @_;

    if ( !$self->no_bootstrap and !$self->no_deps ) {
        for my $package ( @{ $self->perl_bootstrap_modules } ) {
            $log->debugf( 'Bootstrapping toolchain: %s', $package );
            eval {
                Pakket::Scaffolder::Perl->new(
                    config  => $self->{config},
                    package => Pakket::PackageQuery->new_from_string('perl/' . $package),
                    phases  => $self->{phases},
                    no_bootstrap => 1,
                )->run;
                1;
            } or do {
                my $err = $@ || 'zombie error';
                Carp::croak("Cannot bootstrap toolchain module: $package ($err)\n");
            };
        }
    }
}

sub _scaffold_package {
    my ($self, $package) = @_;

    my $release_info = $self->_get_release_info_for_package($package);
    my $sources = $self->_fetch_source_for_package($package, $release_info);

    # we need to update release_info if sources are not got from cpan
    $self->_update_release_info($package, $release_info, $sources);
    $self->_merge_release_info($package, $release_info);

    $self->apply_patches($package, $sources);

    $log->infof('Working on %s', $package->full_name);
    $self->_add_spec_for_package($package);
    $self->_add_source_for_package($package, $sources);
    $log->infof('Done: %s', $package->full_name);
}

sub _merge_release_info {
    my ($self, $package, $release_info) = @_;

    $self->_filter_dependecies($package, $release_info->{prereqs});
    $package->{distribution} = $release_info->{distribution} if $release_info->{distribution};
    $package->{source} = $release_info->{download_url} if $release_info->{download_url};
    $package->{version} = $release_info->{version} if $release_info->{version};
}

sub _filter_dependecies {
    my ($self, $package, $prereqs) = @_;
    
    return unless $prereqs;
    for my $phase ( @{ $self->phases } ) { # phases: configure, develop, runtime, test
        for my $type ( @{ $self->types } ) { # type: requires, recommends
            my $dependency = $prereqs->{$phase}{$type};
            next unless is_hashref($dependency);

            for my $module ( sort keys %{ $dependency } ) {
                next if ($self->_skip_module($module));

                my $distribution = $self->_get_distribution($module);
                if (exists $self->known_incorrect_dependencies->{$package->name}{$distribution}) {
                    $log->debugf("skipping %s (known 'bad' dependency for %s)", $distribution, $package->name );
                    next;
                } else {
                    $log->debugf("Found module $module in distribution $distribution");
                    next if $package->{prereqs}{perl}{$phase}{$distribution};
                    $package->{prereqs}{perl}{$phase}{$distribution} = { version => ( $dependency->{$module} || 0 ) };
                }
            }
        }
    }
}

sub _scaffold_dependencies {
    my ($self, $package, $failed) = @_;

    return if ($self->no_deps);

    $log->debugf("Scaffold dependencies for %s", $package->full_name);
    for my $phase ( @{ $self->phases } ) {
        my $dependency = $package->{prereqs}{perl}{$phase};
        next unless is_hashref($dependency);

        for my $module ( sort keys %{ $dependency } ) {
            eval {
                Pakket::Scaffolder::Perl->new(
                    config       => $self->config,
                    package      => Pakket::PackageQuery->new_from_string("perl/$module=" . $dependency->{$module}{version}),
                    phases       => $self->phases,
                    dist_name    => $self->dist_name,
                    no_bootstrap => 1,
                )->run;
                1;
            } or do {
                my $err = $@ || 'zombie error';
                $failed->{$module} = $err;
            };
        }
    }
}

sub _is_package_in_spec_repo {
    my ($self, $package) = @_;

    my @versions = map { $_ =~ PAKKET_PACKAGE_SPEC(); "$3:$4" }
        @{ $self->spec_repo->all_object_ids_by_name($package->name, 'perl') };

    return 0 unless @versions; # there are no packages

    if ($self->versioner->is_satisfying($package->version.':'.$package->release, @versions)) {
        $log->debugf("Skipping %s, already have satisfying version: %s", $package->full_name, join(", ", @versions));
        return 1;
    }

    return 0; # spec has package, but version is not compatible
}

sub _get_release_info_for_package {
    my ($self, $package) = @_;

    # if is_local is set - generate info without upstream data
    if ( $self->is_local->{$package->name} ) {
        my $from_file = $self->_get_source_archive_path($package->name, $package->version, $package->release);
        return {
            'distribution' => $package->name,
            'download_url' => 'file://' . $from_file->absolute,
        };
    }

    # if source already set from meta
    return {
        'distribution' => $package->name,
        'download_url' => $package->source,
    } if $package->source && $package->source ne 'cpan';

    # check cpan for release info
    return $self->_get_release_info_cpan($package);
}

sub _fetch_source_for_package {
    my ($self, $package, $release_info) = @_;

    my $download_url = $self->_rewrite_download_url($release_info->{download_url});
    if ( !$download_url ) {
        Carp::croak( "Don't have download_url for %s", $package->name );
    }

    my $download = Pakket::Downloader::ByUrl::create($package->name, $download_url);
    return $download->to_dir;
}

sub _rewrite_download_url {
    my ($self, $download_url) = @_;
    my $rewrite = $self->config->{'perl'}{'metacpan'}{'rewrite_download_url'};
    return $download_url unless is_hashref($rewrite);
    my ( $from, $to ) = @{$rewrite}{qw< from to >};
    return ( $download_url =~ s/$from/$to/r );
}

sub _add_source_for_package {
    my ($self, $package, $sources) = @_;

    # check if we already have the source in the repo
    if ( $self->source_repo->has_object( $package->id ) ) {
        $log->debugf("Package %s already exists in source repo (skipping)", $package->full_name);
        return;
    }

    $self->_upload_sources($package, $sources);
}

sub _add_spec_for_package {
    my ($self, $package) = @_;

    if ( $self->spec_repo->has_object( $package->id ) ) {
        $log->debugf("Package %s already exists in spec repo (skipping)", $package->full_name);
        return;
    }

    $log->debugf("Creating spec for %s", $package->full_name);

    # we had PackageQuery in $package now convert it to Package
    my $final_package = Pakket::Package->new(%{$self->package});
    $self->spec_repo->store_package_spec($final_package);
}

sub _skip_module {
    my ($self, $module) = @_;

    if (should_skip_core_module($module)) {
        $log->debugf("%sSkipping %s (core module, not dual-life)", $self->spaces, $module);
        return 1;
    }

    if (exists $self->known_modules_to_skip->{$module}) {
        $log->debugf("%sSkipping %s (known 'bad' module for configuration)", $self->spaces, $module);
        return 1;
    }

    return 0;
}

sub _upload_sources {
    my ($self, $package, $dir) = @_;

    $log->debugf("Uploading %s into source repo from %s", $package->name, $dir);
    $self->source_repo->store_package_source($package, $dir);
}

sub _get_distribution {
    my ($self, $module_name) = @_;

    # check if we've already seen it
    exists $self->dist_name->{$module_name} and return $self->dist_name->{$module_name};

    my $dist_name;

    # check if we can get it from 02packages
    eval {
        my $url = $self->metacpan_api . "/package/" . $module_name;
        $log->debug("Requesting information about module $module_name ($url)");
        my $res = $self->ua->get($url);

        $res->{'status'} == 200
            or Carp::croak("Cannot fetch $url");

        my $content = decode_json $res->{'content'};
        $dist_name = $content->{'distribution'};
        1;
    } or do {
        my $error = $@ || 'Zombie error';
        $log->debug($error);
    };

    # fallback 1:  local copy of 02packages.details
    if ( ! $dist_name ) {
        my $mod = $self->cpan_02packages->package($module_name);
        $mod and $dist_name = $mod->distribution->dist;
    }

    # fallback 2: metacpan check
    if ( ! $dist_name ) {
        $module_name = $self->known_incorrect_name_fixes->{ $module_name }
            if exists $self->known_incorrect_name_fixes->{ $module_name };

        eval {
            my $mod_url  = $self->metacpan_api . "/module/$module_name";
            $log->debug("Requesting information about module $module_name ($mod_url)");
            my $response = $self->ua->get($mod_url);

            $response->{'status'} == 200
                or Carp::croak("Cannot fetch $mod_url");

            my $content = decode_json $response->{'content'};
            $dist_name  = $content->{'distribution'};
            1;
        } or do {
            my $error = $@ || 'Zombie error';
            $log->debug($error);
        };
    }

    # fallback 3: check if name matches a distribution name
    if ( ! $dist_name ) {
        eval {
            $dist_name = $module_name =~ s/::/-/rgsmx;
            my $url = $self->metacpan_api . '/release';
            $log->debug("Requesting information about distribution $dist_name ($url)");
            my $res = $self->ua->post( $url,
                                       +{ 'content' => $self->_get_is_dist_name_query($dist_name) }
                                   );
            $res->{'status'} == 200 or Carp::croak();

            my $res_body = decode_json $res->{'content'};
            $res_body->{'hits'}{'total'} > 0 or Carp::croak();

            1;
        } or do {
            $log->warn("Cannot find distribution for module $module_name. Trying to use $dist_name as fallback");
        };
    }

    $dist_name and
        $self->dist_name->{$module_name} = $dist_name;

    return $dist_name;
}

sub _update_release_info {
    my ($self, $package, $release_info, $sources) = @_;

    if ( $self->is_local->{$package->name} or $package->source) {
        my $prereqs;
        $self->_load_pakket_json($sources);
        if (!$self->no_deps and ($sources->child('META.json')->is_file or $sources->child('META.yml')->is_file)) {
            my $file = $sources->child('META.json')->is_file ? $sources->child('META.json') : $sources->child('META.yml');
            my $meta = CPAN::Meta->load_file($file);
            $prereqs = $meta->effective_prereqs->as_string_hash;
            $release_info->{prereqs} = $prereqs;
        } else {
            $log->warn("Can't find META.json or META.yml in sources");
        }
    }
}

sub _get_release_info_cpan {
    my ($self, $package) = @_;

    # try the latest
    my $latest = $self->_get_latest_release_info_for_distribution($package->name);
    if ($latest->{version} && defined $latest->{download_url}) {
        if ($self->versioner->is_satisfying($package->version.':'.$package->release, $latest->{version})) {
            return $latest;
        }
        $log->debugf("Latest version of %s is %s. Doesn't satisfy requirements. Checking other old versions.",
                        $package->name, $latest->{version});
    }

    # else: fetch all release versions for this distribution
    my $release_prereqs;
    my $version;
    my $download_url;

    my $all_dist_releases = $self->_get_all_releases_for_distribution($package->name);

    # get the matching version according to the spec

    my @valid_versions;
    for my $v ( keys %{$all_dist_releases} ) {
        eval {
            version->parse($v);
            push @valid_versions => $v;
            1;
        } or do {
            my $err = $@ || 'zombie error';
            $log->debugf( '[VERSION ERROR] distribution: %s, version: %s, error: %s', $package->name, $v, $err );
        };
    }

    @valid_versions = sort { version->parse($b) <=> version->parse($a) } @valid_versions;

    for my $v ( @valid_versions ) {
        if ($self->versioner->is_satisfying($package->version.':'.$package->release, $v)) {
            $version         = $v;
            $release_prereqs = $all_dist_releases->{$v}{'prereqs'} || {};
            $download_url    = $self->_rewrite_download_url( $all_dist_releases->{$v}{'download_url'} );
            last;
        }
    }

    $version = $self->known_incorrect_version_fixes->{ $package->name } // $version;

    if (!$version) {
        Carp::croak("Cannot find a suitable version for " . $package->full_name
                        . ", available: " . join(', ', @valid_versions));
    }

    return +{
        'distribution' => $package->name,
        'version'      => $version,
        'prereqs'      => $release_prereqs,
        'download_url' => $download_url,
    };
}

sub _get_all_releases_for_distribution {
    my ( $self, $distribution_name ) = @_;

    my $url = $self->metacpan_api . "/release";
    $log->debugf("Requesting release info for all old versions of $distribution_name ($url)");
    my $res = $self->ua->post( $url,
            +{ content => $self->_get_release_query($distribution_name) });
    if ($res->{'status'} != 200) {
        Carp::croak("Can't find any release for $distribution_name from $url, Status: "
                . $res->{'status'} . ", Reason: " . $res->{'reason'} );
    }
    my $res_body = decode_json $res->{'content'};
    is_arrayref( $res_body->{'hits'}{'hits'} )
        or Carp::croak("Can't find any release for $distribution_name");

    my %all_releases =
        map {
            my $v = $_->{'fields'}{'version'};
            ( is_arrayref($v) ? $v->[0] : $v ) => {
                'prereqs'       => $_->{'_source'}{'metadata'}{'prereqs'},
                'download_url'  => $_->{'_source'}{'download_url'},
            },
        }
        @{ $res_body->{'hits'}{'hits'} };

    return \%all_releases;
}

sub _get_latest_release_info_for_distribution {
    my ( $self, $package_name ) = @_;

    my $url = $self->metacpan_api . "/release/$package_name";
    $log->debugf("Requesting release info for latest version of %s (%s)", $package_name, $url);
    my $res = $self->ua->get( $url );
    if ($res->{'status'} != 200) {
        $log->debugf("Failed receive from $url, Status: %s, Reason: %s", $res->{'status'}, $res->{'reason'});
        return;
    }

    my $res_body= decode_json $res->{'content'};
    my $version = $res_body->{'version'};
    $version = $self->known_incorrect_version_fixes->{ $package_name } // $version;

    return +{
            'distribution' => $package_name,
            'version'      => $version,
            'download_url' => $res_body->{'download_url'},
            'prereqs'      => $res_body->{'metadata'}{'prereqs'},
        };
}

sub _get_is_dist_name_query {
    my ( $self, $name ) = @_;

    return encode_json(
        {
            'query'  => {
                'bool' => {
                    'must' => [
                        { 'term'  => { 'distribution' => $name } },
                    ]
                }
            },
            'fields' => [qw< distribution >],
            'size'   => 0,
        }
    );
}

sub _get_release_query {
    my ( $self, $dist_name ) = @_;

    return encode_json(
        {
            'query'  => {
                'bool' => {
                    'must' => [
                        { 'term'  => { 'distribution' => $dist_name } },
                        # { 'terms' => { 'status' => [qw< cpan latest >] } }
                    ]
                }
            },
            'fields'  => [qw< version >],
            '_source' => [qw< metadata.prereqs download_url >],
            'size'    => 999,
        }
    );
}

# parsing Pakket.json
# Packet.json should be in root directory of package, near META.json
# It keeps some settings which we are missing in META.json.
sub _load_pakket_json {
    my ($self, $dir) = @_;
    my $pakket_json = $dir->child('Pakket.json');

    $pakket_json->exists or return;

    $log->debug("Found Pakket.json in $dir");

    my $data = decode_json($pakket_json->slurp_utf8);

    # Section 'module_to_distribution'
    # Using to map module->distribution for local not-CPAN modules
    if ($data->{'module_to_distribution'}) {
        for my $module_name ( keys %{$data->{'module_to_distribution'}}  ) {
            my $dist_name = $data->{'module_to_distribution'}{$module_name};
            $self->dist_name->{$module_name} = $dist_name;
        }
    }
    return $data;
}

sub _get_source_archive_path {
    my ($self, $name, $ver, $rel) = @_;
    $rel //= 1;
    my @possible_paths = (
        path( $self->cache_dir, $name . '-' . $ver . '.' . $rel . '.tar.gz' ),
        path( $self->cache_dir, $name . '-' . $ver . '.tar.gz' ),
    );
    for my $path (@possible_paths) {
        if ($path->exists) {
            $log->debugf( 'Found archive %s', $path->stringify);
            return $path;
        }
    }
    Carp::croak("Can't find archive in:\n", join("\n", @possible_paths));
    return 0;
}

sub _build_metacpan_api {
    my $self = shift;
    return $ENV{'PAKKET_METACPAN_API'}
        || $self->config->{'perl'}{'metacpan_api'}
        || 'https://fastapi.metacpan.org';
}

sub _build_download_dir {
    my $self = shift;
    return Path::Tiny->tempdir( 'CLEANUP' => 1 );
}

sub _build_cpan_02packages {
    my $self = shift;
    my ( $dir, $file );

    if ( $self->file_02packages ) {
        $file = path( $self->file_02packages );
        $log->infof( "Using 02packages file: %s", $self->file_02packages );

    } else {
        $dir  = Path::Tiny->tempdir;
        $file = path( $dir, '02packages.details.txt' );
        $log->infof( "Downloading 02packages" );
        $self->ua->mirror( 'https://cpan.metacpan.org/modules/02packages.details.txt', $file );
    }

    return Parse::CPAN::Packages::Fast->new($file);
}

sub _build_versioner {
    return Pakket::Versioning->new( 'type' => 'Perl' );
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

__END__
