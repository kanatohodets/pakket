package Pakket::Package;
# ABSTRACT: An object representing a package

use Moose;
use MooseX::StrictConstructor;

with qw< Pakket::Role::PrintableNames >;

has 'name' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'category' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'version' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'is_bootstrap' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

has [qw<build_opts bundle_opts>] => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { return +{} },
);

# FIXME: GH #73 will make this more reasonable
has 'configure_prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_configure_prereqs',
);

has 'test_prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_test_prereqs',
);

has 'runtime_prereqs' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_runtime_prereqs',
);

sub _build_configure_prereqs {
    my $self    = shift;
    return $self->phase_prereqs('configure');
}

sub _build_test_prereqs {
    my $self    = shift;
    return $self->phase_prereqs('test');
}

sub _build_runtime_prereqs {
    my $self    = shift;
    return $self->phase_prereqs('runtime');
}

sub phase_prereqs {
    my ( $self, $phase ) = @_;
    my $prereqs = $self->prereqs;
    return +{
        map { $_ => $prereqs->{$_}{$phase} }
            keys %{$prereqs},
    };
}

sub config {
    my $self = shift;

    return +{
        'Package' => {
            # This is so we don't see is_bootstrap in config
            # if not required -- SX
            ( 'is_bootstrap' => 1 )x!! $self->is_bootstrap,

            map +( $_ => $self->$_ ), qw<category name version>,
        },

        'Prereqs' => $self->prereqs,

        map +( $_ => $self->$_ ), qw<build_opts bundle_opts>,
    };
}

sub new_from_config {
    my ( $class, $config ) = @_;

    my %package_details = (
        %{ $config->{'Package'} },
        'prereqs'      => $config->{'Prereqs'}    || {},
        'build_opts'   => $config->{'build_opts'} || {},
        'is_bootstrap' => !!$config->{'is_bootstrap'},
    );

    return $class->new(%package_details);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
