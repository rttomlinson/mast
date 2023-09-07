package Mast::Service::Spec::v1_0;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use parent 'Mast::Service::Spec::v0';

use Carp 'confess';
use Scalar::Util 'looks_like_number';

our @VERSION = (1.0, '1.0');

sub _validate_top_keys {
  my ($self) = @_;

  $self->SUPER::_validate_top_keys;

  my $spec = $self->{spec};
  my $aws_spec = $spec->{aws};

  confess "elb configuration should be placed under `aws` top key"
    if defined $spec->{elb} and not defined $aws_spec->{elb};
  
  confess "ecs configuration should be placed under `aws` top key"
    if defined $spec->{ecs} and not defined $aws_spec->{ecs};
}

sub _validate_aws_elb_type {
  my ($self, $lb) = @_;

  confess "unsupported type '$lb->{type}' in load balancer $lb->{name}: " .
          "expected 'application' or 'network'"
    unless $lb->{type} =~ /^(application|network)$/;
}

sub _normalize_elb_load_balancer_listener_protocol {
  my ($self, $listener, $lb) = @_;

  $listener->{protocol} = uc $self->stringify($listener->{protocol});

  if ($lb->{type} eq 'network') {
    confess "Invalid listener protocol in $lb->{type} load balancer $lb->{name}: " .
            "only TCP is supported at this time, got $listener->{protocol}"
      unless $listener->{protocol} =~ /^TCP$/;
  }
  elsif ($lb->{type} eq 'application') {
    confess "Invalid listener protocol in $lb->{type} load balancer $lb->{name}: " .
            "should be HTTP or HTTPS, got $listener->{protocol}"
      unless $listener->{protocol} =~ /^HTTPS?$/;
  }
}

sub _normalize_elb_load_balancer_listener_ruleset {
  my ($self, $listener, $lb) = @_;

  my $listener_rules = $listener->{rules};

  # Only application load balancers support routing rules
  if ($lb->{type} ne 'application') {
    confess "listener.rules is not supported for $lb->{type} load balancer $lb->{name}"
      if $listener_rules;
  
    return;
  }
  
  $self->SUPER::_normalize_elb_load_balancer_listener_ruleset($listener, $lb);
}

sub _normalize_elb_target_group_protocol {
  my ($self, $tg, $lb) = @_;

  if ($lb->{type} eq 'network') {
    confess "Invalid target group protocol in $lb->{type} load balancer $lb->{name}: " .
            "only TCP is supported at this time, got $tg->{protocol}"
      unless $tg->{protocol} =~ /^TCP$/;
  }
  elsif ($lb->{type} eq 'application') {
    confess "Invalid target group protocol in $lb->{type} load balancer $lb->{name}: " .
            "should be HTTP or HTTPS, got $tg->{protocol}"
      unless $tg->{protocol} =~ /^HTTPS?$/;
  }
}

sub _normalize_elb_target_group_health_check_protocol {
  my ($self, $hc, $tg) = @_;

  $hc->{protocol} = uc $self->stringify($hc->{protocol});

  if ($tg->{protocol} =~ /^TCP$/) {
    confess "Invalid health check protocol in ELB target group $tg->{name}: " .
            "must be TCP, HTTP, or HTTPS, got $hc->{protocol}"
      unless ($hc->{protocol} =~ /^(?:TCP|HTTPS?)$/);
  }

  if ($tg->{protocol} =~ /^HTTPS?$/) {
    confess "Invalid health check protocol in ELB target group $tg->{name}: " .
            "must be HTTP or HTTPS, got $hc->{protocol}"
      unless $hc->{protocol} =~ /^HTTPS?$/;
  }
}

sub elb { shift->{spec}->{aws}->{elb} }
sub ecs { shift->{spec}->{aws}->{ecs} }

1;