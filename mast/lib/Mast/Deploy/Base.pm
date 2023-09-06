package Mast::Deploy::Base;

use v5.030;
use strictures 2;

use Moo;

extends 'Mast::Base';

has spec => (
  is => 'ro',
  required => 1,
  init_arg => 'service_spec',
  isa => sub {
    die 'Expected Mast::Service::Spec object as "service_spec" parameter'
      unless ref($_[0]) and $_[0]->isa('Mast::Service::Spec');
  },
);

has poll_interval => (
  is => 'ro',
  default => 10,
);

around BUILDARGS => sub {
  my ($method, $class, @params) = @_;

  my %args = scalar @params == 1 && 'HASH' eq ref($params[0]) ? %{$params[0]} : @params;

  if (not $args{aws_region}) {
    $args{aws_region} = $args{service_spec}->aws_region;
  }

  return $class->$method(%args);
};

1;
