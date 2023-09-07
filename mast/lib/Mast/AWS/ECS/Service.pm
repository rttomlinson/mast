package Mast::AWS::ECS::Service;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Carp 'confess';
use JSON::PP;
use AWS::CLIWrapper;

use Mast::AWS::ELB::TargetGroup;

sub new {
  my ($class, %params) = @_;

  if ($params{service}) {
    $params{_service} = delete $params{service};
    $params{cluster} //= $params{_service}->{clusterArn};
    $params{name} //= $params{_service}->{serviceName};
  }

  confess "ECS cluster name or ARN is required"
    unless defined $params{cluster};

  confess "ECS service name is required"
    unless defined $params{name};

  my $aws_region = delete $params{aws_region};
  my $poll_interval = delete $params{poll_interval} // 10;

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );

  bless { aws => $aws, poll_interval => $poll_interval, %params }, $class;
}

sub name { my $self = shift; return $self->{name} // $self->describe->{serviceName} }
sub arn { shift->describe->{serviceArn} }
# Not a typo, describe-service property is `taskDefinition`
# with the actual value being an ARN of that task definition
sub taskDefinitionArn { shift->describe->{taskDefinition} }

sub describe {
  my ($self, $force) = @_;

  return $self->{_service} if $self->{_service} and not $force;

  my $service = do {
    my $res = $self->{aws}->ecs('describe-services', {
      cluster => $self->{cluster},
      services => [$self->{name}],
    });

    $res->{services}->[0];
  };

  # Special case: if the service is in inactive status, consider it not existing
  undef $service if not $force and $service and $service->{status} eq 'INACTIVE';
  $self->{_service} = $service;
}

sub create {
  my ($self, $printer, %params) = @_;
  confess "ECS service $self->{name} already exists"
    if $self->describe;
  
  confess "ECS task definition ARN parameter is required"
    unless $params{task_definition_arn}; # should be moved to camelCase to fit other override conventions

  my @payload_keys = qw(
    cluster launchType desiredCount healthCheckGracePeriod
    enableExecuteCommand networkConfiguration
  );

  if ($params{loadBalancers}) {
    $printer->("Overwriting loadBalancers parameter...");
    @$self{'loadBalancers'} = $params{loadBalancers};
    # If healthCheckGracePeriod is an empty list
    if (scalar(@{@$self{'loadBalancers'}}) == 0) {
      $printer->("loadBalancers override found to be empty...");
      delete @$self{'healthCheckGracePeriod'};
      @payload_keys = grep {$_ ne 'healthCheckGracePeriod'} @payload_keys;
      # and remove from payload_keys
    }
  } else {
    # Health check grace period is only valid for services configured to use load balancers
    @payload_keys = grep {$_ ne 'healthCheckGracePeriod'} @payload_keys;
  }
  
  $printer //= sub {};

  my ($loadBalancers, $network) = @$self{'loadBalancers', 'networkConfiguration'};

  my @lbs;

  # Let's assume that we only support application load balancers at this time.
  # For ALBs, we only need target group arn, container name and port.
  for my $lb (@$loadBalancers) {
    my $tg_name = $lb->{targetGroup}->{name};
    my $target_group = Mast::AWS::ELB::TargetGroup->new(
      name => $tg_name,
      aws => $self->{aws}
    );

    my $tg = $target_group->describe;
    # Need to be able to find the target group because without it, we cannot even
    # assume that the target group has been associated with a load balancer
    confess "Cannot find target group $tg_name" unless $tg;

    push @lbs, {
      # Not a typo. create-service API call expects camelCased targetGroupArn
      # and ELBv2 API returns UppercasedCamelCase ARN property.
      targetGroupArn => $tg->{TargetGroupArn},
      containerName => $lb->{containerName},
      containerPort => $lb->{containerPort},
    };
  }

  my %payload = _params_to_cmd_args(
    (map { $_ => $self->{$_} } @payload_keys),
    loadBalancers => \@lbs,
    %params,
  );

  $printer->("ECS service payload:\n" . encode_json(\%payload) . "\n");

  $printer->("Creating ECS service $self->{name}...");

  $self->{_service} = do {
    my $res = $self->{aws}->ecs('create-service', {
      %payload,
      'service-name' => $self->{name},
    });

    $res->{service};
  };

  $self->wait_running_count($printer) if $payload{'desired-count'} > 0;
  $self->wait_steady_state($printer);

  return $self->{_service};
}

sub update {
  my ($self, $printer, %params) = @_;

  my $name = $self->{name};

  confess "Cannot update ECS service $name, no parameters given"
    unless keys %params;

  my $service = $self->describe(1);

  confess "Cannot update ECS service $name, it does not exist"
    unless $service;

  $printer //= sub {};

  my %payload = _params_to_cmd_args(
    %params,
    cluster => $self->{cluster},
  );

  $self->{_service} = do {
    my $res = $self->{aws}->ecs('update-service', {
      %payload,
      service => $self->{name},
    });

    $res->{service};
  };

  # We are returning the AWS ECS service object state before the update,
  # so that we could diff the past state with current state later if needed.
  return $service;
}

sub remove {
  my ($self, $printer, %params) = @_;

  confess "Cannot modify ECS service $self->{name}, it does not exist"
    unless $self->describe;
  
  $printer //= sub {};

  $printer->("Checking running task count for ECS service $self->{name}...");

  my $service = $self->describe;

  confess "Cannot delete ECS service $self->{name}, it has $service->{runningCount} tasks running"
    unless $service->{runningCount} == 0;
  
  my $task_def_arn = $service->{taskDefinition};
  
  $printer->("Deleting ECS service $self->{name}...");

  $self->{aws}->ecs('delete-service', {
    cluster => $self->{cluster},
    service => $self->{name},
  });

  # Deleting service is different from other operations in that we're waiting for it
  # to reach a certain status rather than a number of tasks or a steady state. In some cases
  # we don't want to wait, e.g. when we are sure that there is going to be no subsequent
  # redeployment and deletion of the service is final.
  # There's also no point in separating this loop into its own method since this code
  # is only used when deleting a service.
  if (not $params{no_wait_for_inactive} ) {
    while (1) {
      my $service = $self->describe(1);

      if ($service->{status} eq 'INACTIVE') {
        $printer->("ECS service $self->{name} has reached inactive status.");
        last;
      }

      $printer->("Waiting for service to reach inactive status...");

      sleep $self->{poll_interval};
    }
  }

  $printer->("Deregistering task definition with ARN $task_def_arn...");

  $self->{aws}->ecs('deregister-task-definition', {
    'task-definition' => $task_def_arn,
  });

  $printer->("Successfully deregistered task definition with ARN $task_def_arn.");

  undef $self->{_service};

  return 1;
}

sub list_tasks {
  my ($self, $printer) = @_;

  $printer //= sub {};

  my $task_arns = do {
    my $res = $self->{aws}->ecs('list-tasks', {
      cluster => $self->{cluster},
      "service-name" => $self->{name},
    });

    $res->{taskArns};
  };

  return @$task_arns;
}

sub stop_tasks {
  my ($self, $printer, %params) = @_;

  my $task_arns = $params{task_arns};

  $printer //= sub {};

  $printer->("Stopping ECS tasks: " . (join ", ", @$task_arns));

  for my $task_arn (@$task_arns) {
    $self->{aws}->ecs('stop-task', {
      cluster => $self->{cluster},
      "task" => $task_arn,
    });
  }
}

sub is_in_steady_state {
  my ($self, $service) = @_;

  $service //= $self->describe(1);

  my $deployments = $service->{deployments};

  return $service->{events}->[0]->{message} =~ /has reached a steady state/
     && @$deployments == 1
     && $deployments->[0]->{status} eq 'PRIMARY'
     && $deployments->[0]->{rolloutState} eq 'COMPLETED';
}

sub wait_running_count {
  my ($self, $printer) = @_;

  confess "Cannot wait for running task count, service $self->{name} does not exist!"
    unless $self->describe(1);

  $printer //= sub {};

  my $poll_interval = $self->{poll_interval};

  # Note that we are not handling timeouts. This is deliberate; this code is intended
  # to be used as part of a continuous deployment workflow, and the orchestrator should
  # implement its own step timeout mechanism.
  while (1) {
    my $service = $self->describe(1);

    my ($running, $desired) = @$service{'runningCount', 'desiredCount'};
      if ($running == $desired) {
        $printer->("Service $self->{name} has $running out of $desired tasks running.");

        return 1;
      }
      
    $printer->("$running of $desired tasks are running, waiting $poll_interval seconds...");

    sleep $poll_interval;
  }
}

sub wait_steady_state {
  my ($self, $printer) = @_;

  confess "Cannot wait for running task count, service $self->{name} does not exist!"
    unless $self->describe(1);

  my $poll_interval = $self->{poll_interval};

  $printer //= sub {};
  $printer->("Waiting for service to reach a steady state...");

  # Ditto for not handling timeouts, see above.
  while (1) {
    my $service = $self->describe(1);
    my $msg = $service->{events}->[0]->{message};
    
    if ($msg and $msg =~ /has reached a steady state/) {
      $printer->("Service $self->{name} has reached a steady state.");

      last;
    }
    
    $printer->("Waiting $poll_interval seconds for service to reach a steady state...");

    sleep $poll_interval;
  }
}

sub wait_for_task_status {
  my ($self, $printer, %params) = @_;

  my ($task_arns, $status) = @params{qw(task_arns status)};
  my $poll_interval = $self->{poll_interval};

  # Trying to describe-tasks below with an empty list of ARNs will throw an error.
  return unless @$task_arns;

  $printer //= sub {};

  while (1) {
    my $res = $self->{aws}->ecs('describe-tasks', {
      cluster => $self->{cluster},
      tasks => $task_arns,
    });

    my %statuses = map { $_->{taskArn} => $_->{lastStatus} } @{$res->{tasks}};
    my @not_yet = grep { $statuses{$_} ne $status } keys %statuses;

    if (not @not_yet) {
      $printer->("All ECS tasks have been stopped");
      last;
    }

    $printer->("ECS tasks not in desired status $status: " . (join ", ", @not_yet));
    $printer->("Waiting $poll_interval seconds...");

    sleep $poll_interval;
  }
}

sub wait_for_deployment {
  my ($self, $printer, $was_service) = @_;

  my $name = $self->name;
  my $poll_interval = $self->{poll_interval};

  my $was_deployment = $was_service->{deployments}->[0];
  
  while (1) {
    $printer->("Checking deployment status for ECS service $name...");

    my $service = $self->describe(1);
    my $deployments = $service->{deployments};

    my ($primary_deployment) = grep { $_->{status} eq 'PRIMARY' } @$deployments;

    confess "Primary deployment not found for ECS service $name"
      unless $primary_deployment;
    
    # Likely paranoia but...
    confess "Primary deployment id $primary_deployment->{id} is the same as previous primary " .
            "deployment id $was_deployment->{id} for ECS service $name"
              if $was_deployment->{id} eq $primary_deployment->{id};
    
    if ($primary_deployment->{rolloutState} eq 'COMPLETED') {
      $printer->("Primary deployment $primary_deployment->{id} rollout is complete ".
                 "for ECS service $name");
      
      return;
    }

    $printer->("Primary deployment $primary_deployment->{id} rollout is in " .
               "$primary_deployment->{rolloutState} state, waiting $poll_interval seconds");
    
    sleep $poll_interval;
  }
}

# Key is input param name, value is AWS CLI command line argument name.
# If the value is a sub, it will be called with the only argument which is
# the input value, and is expected to return a list with key => value
# corresponding to command line arguments.
# The service name parameter is not included in this list because
# it is not consistent across AWS CLI subcommand arguments, e.g.
# `create-service` expects `--service-name` argument, and `update-service`
# expects `--service` argument instead. It is easier to handle this in the
# respective methods.
my %_params_to_args = (
  cluster => 'cluster',
  task_definition_arn => 'task-definition',  # should be moved to camelCase to fit other override conventions
  launchType => 'launch-type',
  desiredCount => 'desired-count',
  healthCheckGracePeriod => 'health-check-grace-period-seconds',

  # This is a special case where if this value is "true" then it needs to be included
  # else it needs to be completely ommited
  enableExecuteCommand => sub { !!$_[0] ? ('enable-execute-command' => '') : () },
  forceNewDeployment => sub { !!$_[0] ? ('force-new-deployment' => '') : () },

  # These two need to be JSON encoded to work around some bugs in CLIWrapper
  loadBalancers => sub { ('load-balancers' => encode_json $_[0]) },
  networkConfiguration => sub { 'network-configuration' => encode_json $_[0] },
);

sub _params_to_cmd_args {
  my (%params) = @_;

  my %out;

  for my $key (keys %params) {
    my $value = $params{$key};

    confess "Cannot convert parameter $key to AWS CLI argument: not found"
      unless exists $_params_to_args{$key};
    
    my ($cmd_key, $cmd_value);
    
    if ('CODE' eq ref $_params_to_args{$key}) {
       ($cmd_key, $cmd_value) = $_params_to_args{$key}->($value);
    }
    else {
      ($cmd_key, $cmd_value) = ($_params_to_args{$key}, $value);
    }

    $out{$cmd_key} = $cmd_value if($cmd_key ne '');
  }

  return %out;
}

# Should move to a different package
sub describe_cluster {
  my ($self, $cluster_name,) = @_;

  my $cluster = do {
    my $res = $self->{aws}->ecs('describe-clusters', {
      clusters => [$cluster_name],
      include => ['TAGS'],
    });

    $res->{clusters}->[0];
  };
  return $cluster;
}

# Should also move to a different package
sub tag_resource {
  my ($self, $resource_arn, $tags) = @_;
  my $res = $self->{aws}->ecs('tag-resource', {
    'resource-arn' => $resource_arn,
    'tags' => $tags, #should already be json encoded
  });
}

sub untag_resource {
  my ($self, $resource_arn, $tag_keys) = @_;
  my $res = $self->{aws}->ecs('untag-resource', {
    'resource-arn' => $resource_arn,
    'tag-keys' => $tag_keys, #should already be json encoded
  });
}

1;
