package Mast::AWS::ELB::AccountLimits;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Moo;

extends 'Mast::Base';

sub describe {
  my ($self) = @_;

  my $res = $self->aws->elbv2('describe-account-limits');

  return +{ map { $_->{Name} => $_->{Max} } @{$res->{Limits}} };
}

sub limit {
  my ($self, $limit_name) = @_;

  my $limits = $self->describe;

  return $limits->{$limit_name};
}

1;
