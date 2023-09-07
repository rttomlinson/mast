package Mast::AWS::ELB::TargetGroup;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Carp 'confess';
use JSON::PP;
use AWS::CLIWrapper;

sub new {
  my ($class, %params) = @_;

  if ($params{target_group}) {
    my $tg = $params{tg} = delete $params{target_group};
    $params{name} = $tg->{TargetGroupName};

    # Target groups can only be associated with only one LB at this time
    my $lb_arn = $tg->{LoadBalancerArns}->[0];

    $params{lb_arn} = $lb_arn if $lb_arn;
  }
  elsif (not $params{arn}) {
    confess 'Target group name parameter "name" is required'
      unless length($params{name}) > 0;
  }

  my $aws_region = delete $params{aws_region};

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );

  my $self = bless { aws => $aws, %params }, $class;

  $self;
}

sub arn {
  my ($self) = @_;

  my $tg = $self->describe;

  return 'HASH' eq ref($tg) ? $tg->{TargetGroupArn} : undef;
}

sub name {
  my ($self) = @_;

  my $tg = $self->describe;

  return 'HASH' eq ref($tg) ? $tg->{TargetGroupName} : undef;
}

sub id {
  my ($self) = @_;

  my $arn = $self->arn;

  return (split /:/, $arn)[-1];
}

# This is used to compute the special ID form for autoscaling policy
# that tracks ALBRequestCountPerTarget metric. For a target group,
# this "special id" is the same as normal id, however for a load balancer
# it is different and we keep this a separate method for API similarity.
sub id_for_autoscaling {
  my ($self) = @_;

  return $self->id;
}

sub lb {
  my ($self) = @_;

  return $self->{lb} if $self->{lb};

  my ($aws, $lb_name, $lb_arn) = @$self{'aws', 'lb_name', 'lb_arn'};

  if (not $lb_name and not $lb_arn) {
    my $tg = $self->describe;

    $lb_arn = $tg->{loadBalancerArns}->[0] if @{$tg->{loadBalancerArns}} == 1;
  }

  confess "Load balancer name or ARN is required"
    if not $lb_name and not $lb_arn;

  my $lb = do {
    my $res = $aws->elbv2('describe-load-balancers', {
      $lb_name ? (names => [$lb_name]) : (),
      $lb_arn ? ('load-balancer-arns' => [$lb_arn]) : (),
    });

    $res->{LoadBalancers}->[0];
  };

  $self->{lb} = $lb;
}

sub lb_arn {
  my ($self) = @_;

  return $self->{lb_arn} if $self->{lb_arn};

  return $self->lb->{LoadBalancerArn};
}

sub describe {
  my ($self) = @_;

  return $self->{tg} if $self->{tg};

  my ($aws, $tg_arn, $tg_name) = @$self{'aws', 'arn', 'name'};

  my $tg = eval {
    my $res = $aws->elbv2('describe-target-groups', {
      $tg_arn ? ('target-group-arns' => [$tg_arn]) : (names => [$tg_name]),
      'max-items' => 1,
    });

    $res->{TargetGroups}->[0];
  };

  confess $@ if $@ and $@ !~ /TargetGroupNotFound/;

  $self->{tg} = $tg;
}

sub associated_load_balancer_arns {
  my ($self) = @_;

  my $tg = $self->describe;

  return $tg ? @{$tg->{LoadBalancerArns}} : undef;
}

# TODO: Add attributes (target group stickiness)

sub create {
  my ($self) = @_;

  confess "Target group with name $self->{name} already exists!"
    if $self->{tg};

  my ($aws, $proto, $port, $hc) = @$self{qw(aws protocol port healthCheck)}; # move to new function?

  confess "Protocol and port are required" if not $proto or not $port;

  my $vpc = $self->lb->{VpcId};
  
  my $params = {
    name => $self->{name},
    protocol => $proto,
    port => $port,
    # We only support IP target types at this moment
    'target-type' => 'ip',
    'vpc-id' => $vpc,

    # Health check parameters are optional
    !$hc ? () : (
      $hc->{protocol} ? ('health-check-protocol' => $hc->{protocol}) : (),
      $hc->{port} ? ('health-check-port' => $hc->{port}) : (),
      $hc->{path} ? ('health-check-path' => $hc->{path}) : (),
      defined($hc->{interval}) ? ('health-check-interval-seconds' => $hc->{interval}) : (),
      defined($hc->{timeout}) ? ('health-check-timeout-seconds' => $hc->{timeout}) : (),
      defined($hc->{healthyThreshold}) ? ('healthy-threshold-count' => $hc->{healthyThreshold}) : (),
      defined($hc->{unhealthyThreshold}) ? ('unhealthy-threshold-count' => $hc->{unhealthyThreshold}) : (),
      $hc->{matcher} ? (matcher => encode_json($hc->{matcher})) : (),
    ),
  };

  my $tg = do {
    my $res = $aws->elbv2('create-target-group', $params);

    $res->{TargetGroups}->[0];
  };

  $self->{tg} = $tg;
}

# Can't use 'delete'
sub remove {
  my ($self) = @_;

  $self->describe unless $self->{tg};

  my ($aws, $tg) = @$self{'aws', 'tg'};

  # No output is expected, if it doesn't throw then it's successful
  $aws->elbv2('delete-target-group', {
    'target-group-arn' => $tg->{TargetGroupArn},
  });
}

sub tag {
  my ($self, %tags) = @_;

  $self->describe unless $self->{tg};

  my ($aws, $tg) = @$self{'aws', 'tg'};

  my $tags_cli = join ' ', map { "Key=$_,Value=$tags{$_}" } keys %tags;

  # No output is expected
  $aws->elbv2('add-tags', {
    'resource-arns' => $tg->{TargetGroupArn},
    tags => $tags_cli,
  });
}

1;
