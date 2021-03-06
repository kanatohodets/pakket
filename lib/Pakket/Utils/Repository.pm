package Pakket::Utils::Repository;
# ABSTRACT: Repository utility functions

use strict;
use warnings;
use parent 'Exporter';

use Carp qw< croak >;
use Path::Tiny qw< path >;

our @EXPORT_OK = (qw< gen_repo_config >);

my %file_ext = (
    'spec'   => 'json',
    'source' => 'tar.gz',
    'parcel' => 'tar.gz',
);

sub gen_repo_config {
    my ( $self, $type, $directory ) = @_;
    $directory or return;

    if ( $directory =~ m{^(https?)://([^/:]+):?([^/]+)?(/.*)?$} ) {
        my ( $protocol, $host, $port, $base_path ) = ( $1, $2, $3, $4 );
        $port or $port = $protocol eq 'http' ? 80 : 443;

        return [
            'HTTP',
            'scheme'    => $protocol,
            'host'      => $host,
            'port'      => $port,
            'base_path' => $base_path,
        ];
    } else {
        my $path = path($directory);
        $path->exists && $path->is_dir
            or croak("Bad directory for $type repo: $path\n");

        return [
            'File',
            'directory'      => $directory,
            'file_extension' => $file_ext{$type},
        ];

    }

    return;
}

1;
__END__
