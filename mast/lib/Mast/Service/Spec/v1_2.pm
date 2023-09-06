package Mast::Service::Spec::v1_2;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use parent 'Mast::Service::Spec::v1_1';

use Carp 'confess';


our @VERSION = (1.2, '1.2');

sub _normalize_spec {
  my ($self) = @_;

  $self->SUPER::_normalize_spec;
  $self->_normalize_route53;

}

sub _normalize_route53 {
  my ($self) = @_;

  my $route53 = $self->{spec}->{route53};

  # this section is optional
  return unless defined $route53;

  confess "route53 is not an array"
    unless 'ARRAY' eq ref $route53;

  my $i = 0;

  for my $entry (@$route53) {
    $self->_normalize_record($entry, $i);
    $i++;
  }
}

sub _normalize_record {
  my ($self, $record, $index) = @_;

  my ($domain, $name, $type, $value) = @$record{qw(domain name type value)};

  confess "Route53 DNS domain name is required in route53[$index], got '$domain'"
    unless $domain;
  
  confess "Route53 DNS record name is required in route53[$index], got '$name'"
    unless $name;

  $record->{type} = uc $type;

  if ('HASH' eq ref $value) {
    my $aliasType = $value->{aliasType};

    if ($aliasType =~ /^applicationloadbalancer$/i) {
      my $aliasTarget = $value->{aliasTarget};

      confess "Target alias for record $name in Route53 domain $domain should include ALB name"
        unless $aliasTarget->{loadBalancerName};
    }
  }
}

sub route53 { shift->{spec}->{aws}->{route53} }

1;