package Mast::AWS::Route53::Record;

use v5.030;
use strictures 2;

use Moo;
use Carp 'confess';
use JSON::PP;

use Mast::AWS::ELB::LoadBalancer;
use Mast::AWS::Route53::Change;

extends 'Mast::Base';

has id => (
  is => 'ro',
  required => !1,
);

has zone => (
  is => 'ro',
  required => 1,
  isa => sub {
    die "Expected Mast::AWS::Route53::Zone, got " . ref($_[0])
      unless ref($_[0]) and $_[0]->isa('Mast::AWS::Route53::Zone');
  },
);

has [qw(name type value)] => (
  is => 'ro',
  required => 1,
);

has allowExisting => (
  is => 'ro',
);

has [qw(fqdn recordset _record)] => (
  is => 'lazy',
);

sub exists {
  my ($self) = @_;

  my $record = eval { $self->_record };

  return !!$record;
}

sub create {
  my ($self) = @_;

  return $self->_action($self->allowExisting ? 'UPSERT' : 'CREATE');
}

sub upsert { shift->_action('UPSERT', @_) }
sub remove { shift->_action('DELETE', @_) }

sub _build__record {
  my ($self) = @_;

  my $zone_id = $self->zone->id;
  my $fqdn = $self->fqdn;

  my $res = $self->aws->route53('list-resource-record-sets', {
      'hosted-zone-id' => $zone_id,
      query => qq|ResourceRecordSets[?Name == '$fqdn']|,
  });

  confess "FQDN $fqdn was not found"
    unless $res && $res->[0] && $res->[0]->{Name} eq $fqdn;

  return $res->[0];
}

sub _build_fqdn {
  my ($self) = @_;

  my $host = $self->name;
  my $domain = $self->zone->domain;

  return "$host.$domain.";
};

sub _build_recordset {
  my ($self) = @_;

  my $value = $self->value;

  my $set = {
    Name => $self->fqdn,
    Type => $self->type,
  };

  if ('HASH' eq ref $value) {
    $set->{AliasTarget} = $self->_resolve_alias($value);
  }

  return $set;
}

sub _action {
  my ($self, $action) = @_;

  my $changeset = {
    Changes => [{
      Action => $action,
      ResourceRecordSet => $self->recordset,
    }],
  };

  my $res = $self->aws->route53('change-resource-record-sets', {
    'hosted-zone-id' => $self->zone->id,
    'change-batch' => encode_json $changeset,
  });

  return Mast::AWS::Route53::Change->new(
    aws => $self->aws,
    id => $res->{ChangeInfo}->{Id}
  );
}

sub _resolve_alias {
  my ($self, $alias) = @_;

  my ($type, $target) = @$alias{qw(aliasType aliasTarget)};

  if ($type =~ /^applicationloadbalancer$/i) {
    my $alb_name = $target->{loadBalancerName};
    my $alb = Mast::AWS::ELB::LoadBalancer->new(
      aws => $self->aws,
      name => $alb_name,
    );

    return {
      # This is *ALB* zone id, not the Route 53 domain zone id
      HostedZoneId => $alb->hosted_zone_id,
      DNSName => $alb->dns_name,
      EvaluateTargetHealth => $target->{evaluateTargetHealth},
    };
  }
  else {
    confess "aliasType $type is not supported";
  }
}

1;
