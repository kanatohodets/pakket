package Pakket::Web::App;
# ABSTRACT: The Pakket web application

use Dancer2 0.204001 'appname' => 'Pakket::Web'; # decode_json
use Log::Any qw< $log >;
use List::Util qw< first >;
use Path::Tiny ();
use Pakket::Web::Repo;
use constant {
    'PATHS' => [
        $ENV{'PAKKET_WEB_CONFIG'} || (),
        '~/.pakket-web.json',
        '/etc/pakket-web.json',
    ],
};

set content_type => 'application/json';

sub setup {
    my ( $class, $config_file ) = @_;

    $config_file //= first { Path::Tiny::path($_)->exists } @{ PATHS() }
        or die $log->fatal(
            'Please specify a config file: PAKKET_WEB_CONFIG, '
          . '~/.pakket-web.json, or /etc/pakket-web.json.',
        );

    my $config = decode_json( Path::Tiny::path($config_file)->slurp_utf8 );

    my @repos;
    foreach my $repo_config ( @{ $config->{'repositories'} } ) {
        my $repo = Pakket::Web::Repo->create($repo_config);
        push @repos, {'repo_config' => $repo_config, 'repo' => $repo};
    }

    get '/info' => sub {
        my @repositories =  map { { 'type' => $_->{'type'},
                                    'path' => $_->{'path'} } }
                                @{ $config->{'repositories'} };
        return encode_json({
                'version' => $Pakket::Web::App::VERSION,
                'repositories' => [@repositories],
                });
    };

    get '/info_detailes' => sub {
        my $packages;
        my @repo_ids;
        for my $repo (@repos) {
            my $repo_id = $repo->{'repo_config'}{'path'};
            push @repo_ids, $repo_id;
            my $ids = $repo->{'repo'}->all_object_ids();
            for my $package (@{$ids}) {
                $packages->{$package}{$repo_id}=1;
            }
        }
        for my $package (keys %{$packages}) {
            for my $repo (@repo_ids) {
                if (! exists $packages->{$package}{$repo}) {
                    $packages->{$package}{$repo} = 0;
                }
            }
        }

        return encode_json($packages);
    };

}

1;

__END__
