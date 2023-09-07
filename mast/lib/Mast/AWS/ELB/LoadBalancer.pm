package Mast::AWS::ELB::LoadBalancer;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Carp 'confess';
use JSON::PP;
use AWS::CLIWrapper;

use Mast::AWS::ELB::AccountLimits;
use Mast::AWS::ELB::Listener;
use Mast::AWS::ELB::ListenerRule;

sub new {
  my ($class, %params) = @_;

  my $aws_region = delete $params{aws_region};

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );

  # This is to avoid collisions with method name
  $params{listener_spec} = delete $params{listener};
  $params{listener_specs} = delete $params{listeners};

  $params{_lb} = delete $params{lb};

  my $self = bless { aws => $aws, %params, _rules => {} }, $class;

  $self;
}

sub describe {
  my ($self) = @_;

  $self->lb;
}

sub arn {
  my ($self) = @_;

  return $self->lb_arn;
}

sub id {
  my ($self) = @_;

  my $arn = $self->arn;

  return (split /:/, $arn)[-1];
}

sub hosted_zone_id { shift->lb->{CanonicalHostedZoneId} }
sub dns_name { shift->lb->{DNSName} }

# This is used to compute the special ID form for autoscaling policy
# that tracks ALBRequestCountPerTarget metric.
sub id_for_autoscaling {
  my ($self) = @_;

  my $id = $self->id;

  return ($id =~ s#^loadbalancer/##r);
}

sub listeners {
  my ($self,) = @_;

  my @mast_listeners = ();
  my @listeners = map { Mast::AWS::ELB::Listener->new(
    lb_arn => $self->lb_arn,
    lb_type => $self->type,
    listener_spec => $_,
    aws => $self->{aws},
    aws_region => $self->{aws_region}
  ) } @{$self->{listener_specs}};
  return \@listeners;

}

sub type {
  my ($self) = @_;

  return $self->{type};
}

sub lb {
  my ($self) = @_;

  my $lb = do {
    my $res = $self->{aws}->elbv2('describe-load-balancers', {
      names => [$self->{name}],
    });

    $res->{LoadBalancers}->[0];
  };

  return $lb;
}

sub lb_arn {
  my ($self) = @_;

  $self->lb->{LoadBalancerArn};
}

1;