package Pakket::Role::Builder;

# ABSTRACT: A role for all builders

use Moose::Role;

with qw< Pakket::Role::RunCommand >;

requires qw< build_package >;

has 'exclude_packages' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub { [] },
);

no Moose::Role;

1;
