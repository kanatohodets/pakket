package Pakket::Repository::Backend::git;
# ABSTRACT: A git-based backend repository

use Moose;
use MooseX::StrictConstructor;
use Regexp::Common    qw< URI >;
use Log::Any          qw< $log >;
use File::chdir;

extends 'Pakket::Repository::Backend::file';

sub new_from_uri {
    my ( $class, $uri ) = @_;
    my $file_regex = $RE{'URI'}{'file'}{'-keep'};
    $file_regex =~ s/file/git/g;
    $uri =~ /$file_regex/xms
        or croak( $log->critical("URI '$uri' is not a proper file URI") );

    my $path = $3; # perldoc Regexp::Common::URI::file

    return $class->new( 'directory' => $path );
}

sub store_location {
    my ( $self, $id, $file_to_store ) = @_;
    my $rs = $self->SUPER::store_location($id, $file_to_store);
    $self->commit_changes("Store $id");
    return $rs;
}

sub remove_location {
    my ( $self, $id ) = @_;
    my $rs = $self->SUPER::remove_location($id);
    $self->commit_chnges("Remove $id");
    return $rs;
}

sub commit_changes {
    my ($self, $message) = @_;
    local $CWD = $self->directory;

    my $cmd= 'git add .';
    my $out = `$cmd`;
    $log->debug("$cmd: $out");

    $cmd = "git commit -m '$message'";
    $out = `$cmd`;
    $log->debug("$cmd: $out");

    if (`git remote`) {
        $cmd = "git pull -r";
        $out = `$cmd`;
        $log->debug("$cmd: $out");

        $cmd = "git push";
        $out = `$cmd`;
        $log->debug("$cmd: $out");
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

__END__

