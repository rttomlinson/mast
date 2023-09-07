package Mast::AWS::Route53::Change;

use v5.030;
use strictures 2;

use Moo;

extends 'Mast::Base';

has id => (
  is => 'ro',
  required => 1,
);

sub status {
  my ($self) = @_;

  my $res = $self->aws->route53('get-change', {
    id => $self->id,
  });

  return $res->{ChangeInfo}->{Status};
}

1;
