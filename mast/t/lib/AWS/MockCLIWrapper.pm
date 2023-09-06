package AWS::MockCLIWrapper;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Exporter 'import';
use Carp 'confess';
use Data::Dumper;
use UUID::Random;
use Clone 'clone';

use parent 'AWS::CLIWrapper';

sub new {
  my ($class, %params) = @_;

  my $aws_region = delete $params{aws_region};
  $aws_region //= 'us-east-1';

  my $mock_aws_state = delete $params{mock_aws_state} // {};

  # would look like
  # {
  #   ecs => {
  #     'describe-services' => sub {}
  #   }
  # }
  my $service_actors_override
    =  delete $params{service_actors_override}
    // delete $params{actors}
    // {};

  bless { aws_region => $aws_region, aws_state => $mock_aws_state, service_actors_override => $service_actors_override}, $class;
}

sub region { shift->{aws_region} }

my %ecs_actors = (
    'describe-services' => \&ecs_describe_services,
    'create-service' => \&ecs_create_service,
    'update-service' => \&ecs_update_service,
    'delete-service' => \&ecs_delete_service,
    'deregister-task-definition' => \&ecs_deregister_task_definition,
    'describe-task-definition' => \&ecs_describe_task_definition,
    'register-task-definition' => \&ecs_create_task_definition,
    'describe-tasks' => \&ecs_describe_tasks,
    'run-task' => \&ecs_run_task,
    'list-tasks' => \&ecs_list_tasks,
    'stop-task' => \&ecs_stop_task,
    'describe-clusters' => \&ecs_describe_clusters,
    'tag-resource' => \&ecs_tag_resource,
);

sub ecs_describe_services {
  my ($self, $args, %additional_params) = @_;
  say $self->{aws_state}->{service};
  if($self->{aws_state}->{service} eq $args->{services}->[0]){
    my $service = $self->{aws_state}->{services_data}->{services}->[0];

    if ($service->{_mock_counter}-- == 0) {
      if ($service->{_mock_state} eq 'deployment') {
        pop @{$service->{deployments}};
        $service->{deployments}->[0]->{rolloutState} = 'COMPLETED';
        unshift @{$service->{events}}, { message => 'has reached a steady state' };
        delete $service->{_mock_state};
      }
    }

    return clone $self->{aws_state}->{services_data};
  } else {
    return undef;
  }
}
sub ecs_create_service {
  my ($self, $args, %additional_params) = @_;
  say $args->{'service-name'};
  $self->{aws_state}{service} = $args->{'service-name'};
  $self->{aws_state}{services_data} = {
      "services" => 
      [{
        _mock_counter => -1,
        "taskDefinition" => "arn:aws:ecs:us-west-2:123456789012:task-definition/amazon-ecs-sample:1",
        "serviceArn" => "arn:aws:ecs:us-west-2:123456789012:service/my-http-service",
        "runningCount" => 0,
        "desiredCount" => 0,
        "events" => [
          {"message" => "has reached a steady state"}
        ],
        deployments => [{
            id => 'ecs-svc/foo',
            status => 'PRIMARY',
            rolloutState => 'COMPLETED',
        }],
        "status" => "HELLO"
      }]
    };

  return clone $self->{aws_state}{services_data};
}
sub ecs_update_service {
  my ($self, $args, %additional_params) = @_;

  my $service = $self->{aws_state}->{services_data}->{services}->[0];

  if ($args->{'task-definition'} ne $service->{taskDefinition}) {
    $service->{_mock_state} = 'deployment';
    $service->{_mock_counter} = 2;

    unshift @{$service->{events}}, { message => 'has begun draining connections' };

    $service->{deployments}->[0]->{status} = 'ACTIVE';

    unshift @{$service->{deployments}}, {
      id => "ecs-svc/" . uc(UUID::Random::generate =~ s/-//gr),
      status => 'PRIMARY',
      rolloutState => 'IN_PROGRESS',
    };
  }

  return {
    services => [clone $service],
  };
}
sub ecs_delete_service {
  my ($self, $args, %additional_params) = @_;

  $self->{aws_state}{services_data}{services}->[0]{status} = "INACTIVE";

  return;
}
sub ecs_deregister_task_definition {
  my ($self, $args, %additional_params) = @_;
  return;
}
sub ecs_describe_task_definition {
  my ($self, $args, %additional_params) = @_;
  if($self->{aws_state}){
    return $self->{aws_state}->{task_definition};
  }else {
    return undef;
  }
}
sub ecs_create_task_definition {
  my ($self, $args, %additional_params) = @_;
  $self->{aws_state}{task_definition} = {
      "taskDefinition" => 
      {
          "taskDefinitionArn" => "arn:aws:ecs:us-west-2:123456789012:task-definition/hello_world:8",
          "containerDefinitions" => [
            {
                "environment"=> [],
                "name"=> "wordpress",
                "links"=> [
                    "mysql"
                ],
                "mountPoints"=> [],
                "image"=> "wordpress",
                "essential"=> \1,
                "portMappings"=> [
                    {
                        "containerPort"=> 80,
                        "hostPort"=> 80
                    }
                ],
                "memory"=> 500,
                "cpu"=> 10,
                "volumesFrom"=> []
            },
            {
                "environment"=> [
                    {
                        "name"=> "MYSQL_ROOT_PASSWORD",
                        "value"=> "password"
                    }
                ],
                "name"=> "mysql",
                "mountPoints"=> [],
                "image"=> "mysql",
                "cpu"=> 10,
                "portMappings"=> [],
                "memory"=> 500,
                "essential"=> \1,
                "volumesFrom"=> []
            }
        ],
        "family"=> "hello_world",
        "revision"=> 8,
      }
    };

  return $self->{aws_state}{task_definition};
}
sub ecs_describe_tasks {
  my ($self, $args, %additional_params) = @_;
  return;
}
sub ecs_run_task {
  my ($self, $args, %additional_params) = @_;

  return {
    tasks => []
  };
}
sub ecs_list_tasks {
  my ($self, $args, %additional_params) = @_;

  return {
    taskArns => []
  };
}
sub ecs_stop_task {
  my ($self, $args, %additional_params) = @_;

  return {
    task => {arn => "wer"}
  };
}

sub ecs_describe_clusters {
  my ($self, $args, %additional_params) = @_;

  return {
    clusters => [{arn => "wer"}]
  };
}
sub ecs_tag_resource {
  my ($self, $args, %additional_params) = @_;

  return;
}

sub ecs {
  my $self = shift;
  my $action = shift;

  my $actor = $self->{service_actors_override}->{ecs}->{$action} // $ecs_actors{$action};
    
  die "mock action of $action not found or not implemented\n" unless $actor;

  return $actor->($self, @_);
}

my %logs_actors = (
    'get-log-events' => \&get_log_events,
);
sub get_log_events {
  my ($self, $args, %additional_params) = @_;
  return;
}
sub logs {
    my $self = shift;
    my $action = shift;
    my $actor = $logs_actors{$action};
    
    die "mock action of $action not found or not implemented\n" unless $actor;
    
    return $actor->($self, @_);
    
}

my %elb_actors = (
  'describe-load-balancers' => \&elb_describe_load_balancers,
  'describe-listeners' => \&elb_describe_listeners,
  'describe-rules' => \&elb_describe_rules,
  'describe-target-groups' => \&elb_describe_target_groups,
  'create-rule' => \&elb_create_listener_rule,
  'modify-rule' => \&elb_modify_listener_rule,
  'delete-rule' => \&elb_delete_listener_rule,
  'create-target-group' => \&elb_create_target_group,
  'delete-target-group' => \&elb_delete_target_group,
  'create-listener' => \&elb_create_listener,
  'modify-listener' => \&elb_modify_listener,
  'delete-listener' => \&elb_delete_listener,
  'add-tags' => \&elb_tag_target_groups, # this will likely need to support more than just target groups, but would need to validate against arn name i.e. something like "this doesn't look like a target group arn..."
);

sub elb_tag_target_groups {
  my ($self, $args, %additional_params) = @_;
  warn "We only support target group tagging right now. You need to implement the other resource tagging mocks";
  if($self->{aws_state}->{target_groups}){
    if(defined $args->{'target-group-arns'}){
      my @x = map { 
        my $l = $_;
        my @matches = grep( /^$l->{TargetGroupArn}$/, @{$args->{'target-group-arns'}});
        if (scalar @matches) {
          $l->{Tags} = $args->{"tags"}
        }
        $l
      } @{$self->{aws_state}->{target_groups}->{TargetGroups}};

    } elsif(defined $args->{'names'}) {

      my @x = map { 
        my $l = $_;
        my @matches = grep( /^$l->{TargetGroupName}$/, @{$args->{'names'}});
        if (scalar @matches) {
          $l->{Tags} = $args->{"tags"}
        }
        $l
      } @{$self->{aws_state}->{target_groups}->{TargetGroups}};
    }
  }
  return undef;
}

sub elb_describe_load_balancers {
  my ($self, $args, %additional_params) = @_;

  if (defined $self->{aws_state}->{load_balancers}) {
    if (defined $args->{names}) {
      my @matching_lbs = grep { my $lb = $_; grep( /^$lb->{LoadBalancerName}$/, @{$args->{names}}) } @{$self->{aws_state}->{load_balancers}->{LoadBalancers}};
      return {
        LoadBalancers => \@matching_lbs
      };
    } else {
      return $self->{aws_state}->{load_balancers}
    }
  }
}

sub elb_describe_listeners {
  my ($self, $args, %additional_params) = @_;
  if (defined $self->{aws_state}->{listeners}) {
    if (defined $args->{"load-balancer-arn"}) {

      my $load_balancer_arn_arg = $args->{"load-balancer-arn"};
      my @lb_listeners = grep { my $l = $_; $l->{LoadBalancerArn} =~ /^$load_balancer_arn_arg$/ } @{$self->{aws_state}->{listeners}->{Listeners}};
      return {
        Listeners => \@lb_listeners
      };

    } else {
      return $self->{aws_state}->{listeners};
    }
  } else {
    return {
        Listeners => []
      };
  }
}
sub elb_describe_rules {
  my ($self, $args, %additional_params) = @_;
  if (defined $self->{aws_state}->{listener_rules}) {
    if (defined $args->{"listener-arn"}) {
      my $listener_arn = $args->{"listener-arn"};

      my @lb_listener_rules = grep { my $l = $_; $l->{ListenerArn} =~ /$listener_arn/ } @{$self->{aws_state}->{listener_rules}->{Rules}};

      return {
        Rules => \@lb_listener_rules
      };
    } else {
      return $self->{aws_state}->{listener_rules};
    }
  };
}
sub elb_describe_target_groups {
  my ($self, $args, %additional_params) = @_;
  if($self->{aws_state}->{target_groups}){
    if(defined $args->{'target-group-arns'}){
      my @x = grep { my $l = $_; grep( /^$l->{TargetGroupArn}$/, @{$args->{'target-group-arns'}}) } @{$self->{aws_state}->{target_groups}->{TargetGroups}};

      return {
        TargetGroups => \@x
      };
    } elsif(defined $args->{'names'}) {

      my @x = grep { my $l = $_; grep( /^$l->{TargetGroupName}$/, @{$args->{'names'}}) } @{$self->{aws_state}->{target_groups}->{TargetGroups}};

      return {
        TargetGroups => \@x
      };
    } else {
      return $self->{aws_state}->{target_groups};
    }
  } else {
    return undef;
  }
}
sub elb_create_listener_rule {
  my ($self, $args, %additional_params) = @_;
  my $arn_suffix .= sprintf "%08X", rand(0xffffffff);
  my %new_listener_rule = (
    RuleArn => "$args->{'listener-arn'}$arn_suffix",
    ListenerArn => $args->{"listener-arn"},
    Priority => $args->{"priority"},
    Conditions => $args->{"conditions"},
    Actions => $args->{"actions"},
  );
  if ($self->{aws_state}->{listener_rules}) {
    push(@{$self->{aws_state}->{listener_rules}->{Rules}}, \%new_listener_rule);

  } else {
    $self->{aws_state}->{listener_rules} = {
      Rules => [\%new_listener_rule]
    };
  }
  return {
    Rules => [\%new_listener_rule]
  };
}
sub elb_modify_listener_rule {
  my ($self, $args, %additional_params) = @_;
  confess "listener with arn: $args->{'rule-arn'} not found" unless grep { $_->{RuleArn} eq $args->{'rule-arn'} } @{$self->{aws_state}->{listener_rules}->{Rules}};
  my @rule = grep { $_->{RuleArn} eq $args->{'rule-arn'} } @{$self->{aws_state}->{listener_rules}->{Rules}};
  my $values = $rule[0];
  $values->{Conditions} = $args->{"conditions"} if $args->{"conditions"};
  $values->{Actions} = $args->{"actions"};
  return $self->{aws_state}->{listener_rules};
}
sub elb_delete_listener_rule {
  my ($self, $args, %additional_params) = @_;
  if ($self->{aws_state}->{listener_rules}) {
    my @remaining_rules = grep { !($_->{RuleArn} =~ /$args->{"rule-arn"}/) } @{$self->{aws_state}->{listener_rules}->{Rules}};
    $self->{aws_state}->{listener_rules}->{Rules} = \@remaining_rules;
  }
  return;
}
sub elb_create_target_group {
  my ($self, $args, %additional_params) = @_;
  if (defined $self->{aws_state}->{target_groups}) {
    my %new_target_group = (
      TargetGroupArn => $args->{name},
      TargetGroupName => $args->{name},
    );
    push(@{$self->{aws_state}->{target_groups}->{TargetGroups}}, \%new_target_group);
  } else {
    $self->{aws_state}->{target_groups} = {
      TargetGroups => [{
        TargetGroupArn => $args->{name},
        TargetGroupName => $args->{name},
      }]
    };
  }
  return $self->{aws_state}->{target_groups};
}
sub elb_delete_target_group {
  my ($self, $args, %additional_params) = @_;

  my $target_groups = $self->{aws_state}->{target_groups}->{TargetGroups};

  my @updated_target_groups = grep {
    !($_->{TargetGroupArn} eq $args->{"target-group-arn"})
  } @$target_groups;

  return $self->{aws_state}->{target_groups} = {
    TargetGroups => \@updated_target_groups
  };
}
sub elb_create_listener {
  my ($self, $args, %additional_params) = @_;
  my %new_listener = (
    ListenerArn => $args->{"load-balancer-arn"},
    LoadBalancerArn => $args->{"load-balancer-arn"},
    Port => $args->{port},
    Protocol => $args->{protocol},
    DefaultActions => [{
      Type => "forward",
      TargetGroupArn => $args->{"default-actions"}->[0]->{TargetGroupArn},
      ForwardConfig => {
        TargetGroups => [{
          TargetGroupArn => $args->{"default-actions"}->[0]->{TargetGroupArn},
        }]
      },
    }],
  );
  if (defined $self->{aws_state}->{listeners}) {
    push(@{$self->{aws_state}->{listeners}->{Listeners}}, \%new_listener);
    return $self->{aws_state}->{listeners};
  } else {
    return $self->{aws_state}->{listeners} = {
      Listeners => [
        \%new_listener
      ]
    };
  };
}

sub elb_modify_listener {
  my ($self, $args, %additional_params) = @_;
  confess "no listeners" unless defined $self->{aws_state}->{listeners};
  my $listeners = $self->{aws_state}->{listeners}->{Listeners};
  my $target_arn = $args->{'listener-arn'};

  my @listener = grep {$_->{ListenerArn} eq $target_arn} @$listeners;

  my @updated_listeners = map {
    if ($_->{ListenerArn} eq $args->{"listener-arn"}) {
      my %updated_listener = (
        ListenerArn => $args->{"listener-arn"},
        LoadBalancerArn => $args->{"listener-arn"},
        Port => $args->{port},
        Protocol => $args->{protocol},
        DefaultActions => [{
          Type => "forward",
          TargetGroupArn => $args->{"default-actions"}->[0]->{TargetGroupArn},
          ForwardConfig => {
            TargetGroups => [{
              TargetGroupArn => $args->{"default-actions"}->[0]->{TargetGroupArn},
            }]
          },
        }],
      );
      \%updated_listener;

    } else {
      $_;
    }

  } @$listeners;

  return $self->{aws_state}->{listeners} = {
    Listeners => \@updated_listeners
  };
}

sub elb_delete_listener{
  my ($self, $args, %additional_params) = @_;
  confess "no listeners" unless defined $self->{aws_state}->{listeners};
  my $listeners = $self->{aws_state}->{listeners}->{Listeners};

  my @updated_listeners = grep {
    !($_->{ListenerArn} eq $args->{"listener-arn"})
  } @$listeners;

  return $self->{aws_state}->{listeners} = {
    Listeners => \@updated_listeners
  };
}

sub elbv2 {
    my $self = shift;
    my $action = shift;
    my $actor = $self->{service_actors_override}->{elbv2}->{$action} // $elb_actors{$action};
    
    die "mock action of $action not found or not implemented\n" unless $actor;
    
    return $actor->($self, @_);
    
}
my %application_autoscaling_actors = (
  'describe-scalable-targets' => \&application_autoscaling_describe_scalable_targets,
  'register-scalable-target' => \&application_autoscaling_register_scalable_targets,
  'deregister-scalable-target' => \&application_autoscaling_deregister_scalable_targets,
  'describe-scaling-policies' => \&application_autoscaling_describe_scaling_policies,
  'put-scaling-policy' => \&application_autoscaling_put_scaling_policy,
  'delete-scaling-policy' => \&application_autoscaling_delete_scaling_policy,
);

sub application_autoscaling_describe_scalable_targets {
  my ($self, $args, %additional_params) = @_;
  return {
    ScalableTargets => [{
      ResourceId => "yooooo"
    }]
  };
}
sub application_autoscaling_register_scalable_targets {
  my ($self, $args, %additional_params) = @_;
  return {
    ScalableTargets => [{
      ResourceId => "yooooo"
    }]
  };
}
sub application_autoscaling_deregister_scalable_targets {
  my ($self, $args, %additional_params) = @_;
  return {
    ScalableTargets => [{
      ResourceId => "yooooo"
    }]
  };
}
sub application_autoscaling_describe_scaling_policies {
  my ($self, $args, %additional_params) = @_;
  return {
    ScalingPolicies => [{
      PolicyName => "yooooo"
    }]
  };
}
sub application_autoscaling_put_scaling_policy {
  my ($self, $args, %additional_params) = @_;
  return {
    PolicyName => "yooooo"
  };
}
sub application_autoscaling_delete_scaling_policy {
  my ($self, $args, %additional_params) = @_;
  return {
    PolicyName => "yooooo"
  };
}

sub application_autoscaling {
    my $self = shift;
    my $action = shift;
    my $actor =
      $self->{service_actors_override}->{application_autoscaling}->{$action}
      // $application_autoscaling_actors{$action};
    
    die "mock action of $action not found or not implemented\n" unless $actor;
    
    return $actor->($self, @_);
    
}

sub route53 {
  my $self = shift;
  my $action = shift;
  my $actor = $self->{service_actors_override}->{route53}->{$action};
  
  die "mock action of $action not found or not implemented\n" unless $actor;
  
  return $actor->($self, @_);
}

1;