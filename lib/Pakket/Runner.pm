package Pakket::Runner;
# ABSTRACT: Run Pakket-based applications

use Moose;
use Types::Path::Tiny qw< AbsPath >;

has 'active_path' => (
    'is'       => 'ro',
    'isa'      => AbsPath,
    'coerce'   => 1,
    'required' => 1,
);

sub run {
    my ( $self, @args ) = @_;

    my $active_path = $self->active_path;

    local $ENV{'PATH'}            = "$active_path/bin:$ENV{PATH}";
    local $ENV{'PERL5LIB'}        = "$active_path/lib/perl5";
    local $ENV{'LD_LIBRARY_PATH'} = "$active_path/lib:$ENV{LD_LIBRARY_PATH}";

    # FIXME: Move to IPC::Open3, use the logger, etc.
    # XXX:   Should this just use the RunCommand role?
    system @args;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
