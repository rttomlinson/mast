package Mast::AWS::ELB::Listener;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Carp 'confess';

use AWS::CLIWrapper;

use Mast::AWS::ELB::ListenerRule;

sub new {
  my ($class, %params) = @_;
  my $aws_region = delete $params{aws_region};

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );
  
  $params{protocol} = $params{listener_spec}->{protocol};
  $params{port} = $params{listener_spec}->{port};

  if ($params{lb_type} eq 'application') {
    $params{rule_specs} = $params{listener_spec}->{rules};
  }
  
  my $self = bless { aws => $aws, %params, _rules => {} }, $class;

  $self;
}

sub describe {
  my ($self,) = @_;

  my $proto = $self->{protocol};
  my $port = $self->{port};


  my @listeners = do {
    my $res = $self->{aws}->elbv2('describe-listeners', {
      'load-balancer-arn' => $self->lb_arn,
    });
    @{ $res->{Listeners} };
  };


  my ($listener) = grep { $_->{Port} == $port && $_->{Protocol} eq $proto } @listeners;

  confess "Cannot find $proto listener at port $port for load balancer $self->{name}!"
    unless $listener;
  
  return $listener;
}

sub arn {
  my ($self) = @_;

  $self->describe->{ListenerArn};
}

# default action is an array but only one is ever found
sub default_action {
  my ($self) = @_;

  return $self->describe->{DefaultActions}->[0];
}

sub target_group_name {
  my ($self) = @_;
  confess "target_group_name function for ELB types other than network are not supported at this time. You provided $self->{lb_type}" if ($self->{lb_type} ne 'network');
  return $self->{listener_spec}->{action}->{targetGroupName};

}


sub create {
  my ($self, %params) = @_;
  confess "create function for ELB types other than network are not supported at this time. You provided $self->{lb_type}" if ($self->{lb_type} ne 'network');

  my ($target_group_arn) = @params{qw(target_group_arn)};
  my @listeners = do {
    my $res = $self->{aws}->elbv2('create-listener', {
      'load-balancer-arn' => $self->lb_arn,
      'protocol' => $self->protocol,
      'port' => $self->port,
      'default-actions' => [{
        Type => 'forward',
        TargetGroupArn => $target_group_arn,
      }] # only assume 1 action
    });

    @{ $res->{Listeners} };
  };
  # only expect 1 listener to ever be created
  return $listeners[0];

}

sub modify {
  my ($self, %params) = @_;
  confess "modify function for ELB types other than network are not supported at this time. You provided $self->{lb_type}" if ($self->{lb_type} ne 'network');

  my $port = $self->port;
  my $protocol = $self->protocol;
  my $target_group_arn = $params{target_group_arn};
  my $res;

  # Let the error be thrown here as well since we want to fail on unsuccessful listener modification
  my @listeners = do {
    $res = $self->{aws}->elbv2('modify-listener', {
      'listener-arn' => $self->arn,
      'protocol' => $protocol,
      'port' => $port,
      'default-actions' => [{
        Type => 'forward',
        TargetGroupArn => $target_group_arn,
      }] # only assume 1 action
    });

    say qq|Successfully updated existing listener forwarding traffic to $target_group_arn.|;
    @{ $res->{Listeners} };
  };
  return $listeners[0];
}

sub delete {
  my ($self,) = @_;
  confess "delete function for ELB types other than network are not supported at this time. You provided $self->{lb_type}" if ($self->{lb_type} ne 'network');

  my $listener_arn = $self->arn;
  my @listeners = do {
    $self->{aws}->elbv2('delete-listener', {
      'listener-arn' => $listener_arn,
    });
  };
  return undef;
}

sub protocol {
  my ($self) = @_;

  $self->{protocol};
}

sub port {
  my ($self) = @_;

  $self->{port};
}

sub lb_arn {
  my ($self) = @_;

  $self->{lb_arn};
}

sub rules {
  my ($self) = @_;
  confess "rules function for ELB types other than application are not supported at this time. You provided $self->{lb_type}" if ($self->{lb_type} ne 'application');

  my @listener_rules = map { Mast::AWS::ELB::ListenerRule->new(
    rule_spec => $_,
    listener => $self,
    aws => $self->{aws},
    aws_region => $self->{aws_region}
  ) } @{$self->{rule_specs}};

  return \@listener_rules;
}

1;