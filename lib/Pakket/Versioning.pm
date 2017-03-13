package Pakket::Versioning;
# ABSTRACT: A versioning class

use Moose;
use MooseX::StrictConstructor;
use Carp            qw< croak >;
use Log::Any        qw< $log >;
use Module::Runtime qw< require_module >;

has 'type' => (
    'is'       => 'ro',
    'isa'      => 'PakketVersioning',
    'coerce'   => 1,
    'required' => 1,
    'handles'  => [ 'compare' ],
);

sub parse_req_string {
    my ( $self, $req_string ) = @_;

    # A filter string is a comma-separated list of conditions
    # A condition is of the form "OP VER"
    # OP is >=, <=, !=, ==, >, <
    # VER is a version string valid for the version module
    # Whitespace is ignored
    my @conditions = split /,/xms, $req_string;
    my @filters;
    foreach my $condition (@conditions) {
        my @filter = $condition =~ /^\s*(>=|<=|==|!=|>|<)\s*(\S*)\s*$/xms;
        push @filters, \@filter;
    }

    return \@filters;
}

my %op_map = (
    '>=' => sub { $_[0] >= 0 },
    '<=' => sub { $_[0] <= 0 },
    '==' => sub { $_[0] == 0 },
    '!=' => sub { $_[0] != 0 },
    '>'  => sub { $_[0] >  0 },
    '<'  => sub { $_[0] <  0 },
);

sub filter_version {
    my ( $self, $req_string, $versions ) = @_;

    foreach my $filter ( @{ $self->parse_req_string($req_string) } ) {
        my ( $op, $req_version ) = @{$filter};

        @{$versions}
            = grep +( $op_map{$op}->( $self->compare( $_, $req_version ) ) ),
            @{$versions};
    }

    return;
}

sub latest {
    my ( $self, $req_string, @versions ) = @_;

    # Filter all @versions based on $req_string
    $self->filter_version( $req_string, \@versions );

    @versions
        or croak( $log->critical('No versions provided') );

    # latest_version
    my $latest;
    foreach my $version (@versions) {
        if ( !defined $latest ) {
            $latest = $version;
            next;
        }

        if ( $self->compare( $latest, $version ) < 0 ) {
            $latest = $version;
        }
    }

    return $latest;
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;
