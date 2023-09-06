package Mast::AWS::Route53::Zone;

use v5.030;
use strictures 2;

use Moo;
use JSON::PP;

extends 'Mast::Base';

has [qw(domain private)] => (
  is => 'ro',
);

has [qw(_zone id)] => (
  is => 'lazy',
);

sub _build__zone {
  my ($self) = @_;

  my $aws = $self->aws;

  my $res = $aws->route53('list-hosted-zones-by-name', {
      'dns-name' => $self->domain,
      # There can be up to two zones for a given name: public and private
      'max-items' => 2,
  });

  my $qualifier = $self->private ? JSON::PP::true : JSON::PP::false;

  my ($zone) = grep { $_->{Config}->{PrivateZone} == $qualifier } @{$res->{HostedZones}};

  return $zone;
}

sub _build_id { shift->_zone->{Id} }

1;
