package Mast::Deploy::Service;

use v5.030;
use warnings;
no warnings 'uninitialized', 'unopened';

use Carp 'confess';

use parent 'Mast::Deploy::Base';

use JSON::PP;
use Mast::Cloud::Spec;
use Mast::AWS::ECS::Service;
use Mast::Deploy::ListenerRules;
use Mast::AWS::ApplicationAutoscaling::ScalingPolicy;
use Mast::AWS::ApplicationAutoscaling::ScalableTarget;

sub get_service_object {
  my ($self, %params) = @_;

  my $service_def = $self->spec
    ? $self->spec->ecs->{service}
    : { cluster => $self->{cluster}, name => $self->{service} };

  $self->{_service} = Mast::AWS::ECS::Service->new(
    aws_region => $self->aws_region,
    poll_interval => $self->{poll_interval},
    aws => $self->aws,
    %$service_def,
    %params,
  );
}

sub create_or_update_ecs_service {
  my ($self, %params) = @_;

  my ($task_definition_arn, $overrides)
    = @params{qw(task_definition_arn service_overrides)};
  my $service = $self->get_service_object;
  my $service_name = $service->name;

  say "Checking if ECS service $service_name already exists...";

  my $exists = !!$service->describe;
  my $aws_svc;

  if (not $exists) {
    say "Creating ECS service $service_name...";

    $aws_svc = $service->create(
      sub { say @_ },
      %$overrides,
      task_definition_arn => $task_definition_arn,
    );

    say "Successfully created ECS service $service_name with ARN: $aws_svc->{serviceArn}";
  }
  elsif ($service->{allowExisting}) {
    $aws_svc = $self->update_ecs_service(%params);
  }
  else {
    confess "ECS service $service_name already exists and service spec does not allow existing service";
  }

  return $aws_svc->{serviceArn};
}

sub update_ecs_service {
  my ($self, %params) = @_;

  return $self->update_and_restart_ecs_service_tasks_with_new_task_definition(%params)
    if $params{task_definition_arn};

  my $overrides = $params{service_overrides};  
  my $service = $self->get_service_object;
  my $service_name = $service->name;

  if (not %$overrides) {
    say "ECS service $service_name configuration is already up to date, nothing to do.";

    return $service->describe;
  }

  my $service_arn = $service->arn;
  
  say "Updating existing ECS service $service_name with new configuration...";

  $service->update(sub { say @_ }, %$overrides);

  $service->wait_running_count(sub { say @_ }) if defined $overrides->{desiredCount};
  $service->wait_steady_state(sub { say @_ });

  say "Successfully updated ECS service $service_name with ARN: $service_arn";

  return $service->describe;
}

sub get_current_task_count {
  my ($self) = @_;
  my $service = $self->get_service_object;
  # take the greater of runningCount and desiredCount
  my $running_count = $service->describe->{runningCount};
  my $desired_count = $service->describe->{desiredCount};
  return $running_count if($running_count > $desired_count);
  return $desired_count;
}

sub scale_task_count {
  my ($self, $desired_count, $current_active_service) = @_;
  # only use current_active_service if $desired_count is 'match'. Move this to execution spec step
  my $service = $self->get_service_object;
  my $service_name = $service->name;

  # Assign a value from service spec if $desired_count is undefined
  $desired_count //= $self->spec->ecs->{service}->{desiredCount};

  # If $desired_count value has not been provided explicitly and we cannot find it
  # in the service spec for some reason, bail out. Otherwise undefined value will be
  # coerced to zero with potential nasty consequences.
  confess "Cannot update ECS service $service_name, desiredCount is undefined"
    unless defined $desired_count;

  # handle the case that we have 'match'
  if ($desired_count =~ /match|auto/i) {
    # if match, but no current_active_service, then nothing to match on. fail scaling
    confess "Cannot use $desired_count scaling mode, current_active_service is undefined"
      unless defined $current_active_service;
    $desired_count = $current_active_service->get_current_task_count;
  }
 
  say "Updating ECS service $service_name to desired task count of $desired_count...";
  # TODO Handle auto scaling in the Execution spec
  $service->update(sub { say @_ }, desiredCount => $desired_count);
  $service->wait_running_count(sub { say @_ });
  $service->wait_steady_state(sub { say @_ });

  say "Successfully updated ECS service $service_name.";

  return 1;
}

sub delete_ecs_service {
  my ($self, %params) = @_;

  my $service = $self->get_service_object;
  my $service_name = $service->name;

  say "Preparing to delete ECS service $service_name...";

  say "Checking if ECS service $service_name exists...";

  my $exists = !!$service->describe;

  if (not $exists) {
    say "ECS service with name $service_name does not exist. Nothing to do. Continuing";
  } else {
    # Cannot use delete keyword
    $service->remove(sub { say @_ }, %params);

    say "Successfully deleted ECS service $service_name.";
  }
  
}

# We'll be doing both here since this should always happen together
sub register_service_as_scalable_target_and_attach_scaling_policy {
    my ($self) = @_;
    my $service_def = $self->spec->ecs->{service};

    # check if service exists
    my $my_service = $self->get_service_object;
    $my_service->describe;
    return "service not found" if(not(defined $my_service->{_service}));
    # first need to register the scalable target which is
    say "Register new deployment ecs service with Autoscaling";
    my $scalable_target = $service_def->{scalableTarget};
    return "scalable target config not found" if(not(defined $scalable_target));
    my $scalable_target_object = Mast::AWS::ApplicationAutoscaling::ScalableTarget->new(
      aws_region => $self->aws_region,
      resource_id => '',
      aws => $self->aws,
    );
    $scalable_target_object->create(
      cli_input_json => encode_json($scalable_target)
    );
    say "Applying task autoscaling policy for new deployment ecs service";
    my $scaling_policy = $service_def->{scalingPolicy};
    return "scaling policy config not found" if(not(defined $scaling_policy));

    my $scaling_policy_object = Mast::AWS::ApplicationAutoscaling::ScalingPolicy->new(
      aws_region => $self->aws_region,
      policy_name => '',
      aws => $self->aws,
    );
    
    $scaling_policy_object->create(
      scaling_policy => $scaling_policy,
    );

    return undef;
}

# logic for this is as follow:
# if the policy cannot be found, then assume it has been removed
# if the scalable target cannot be found, then assume it has been removed
sub deregister_service_as_scalable_target_and_delete_scaling_policy {
    my ($self) = @_;
    my $service_def = $self->spec->ecs->{service};

    #  do we actually care if the service exists or not? just check the policies
    # my $my_service = $self->get_service_object;
    # $my_service->describe;
    # return "service not found" if(not(defined $my_service->{_service})); #

    my $scaling_policy = $service_def->{scalingPolicy};
    # if defined, try to remove it
    if(defined $scaling_policy){
      # What happens when you try to delete a policy that doesn't exist?
      my %delete_scaling_policy_payload = %$scaling_policy{qw(ServiceNamespace ResourceId PolicyName ScalableDimension)};
      #  check if policy exists

      my $scaling_policy_object = Mast::AWS::ApplicationAutoscaling::ScalingPolicy->new(
        aws_region => $self->aws_region,
        policy_name => '',
        aws => $self->aws,
      );
      $scaling_policy_object->remove(
        cli_input_json => encode_json(\%delete_scaling_policy_payload)
      )
      
    }
    my $scalable_target = $service_def->{scalableTarget};
    if(defined $scalable_target){
      # what happens when you try to deregister a target that doesn't exist?
      my %deregister_scalable_target_payload = %$scalable_target{qw(ServiceNamespace ResourceId ScalableDimension)};
      my $scalable_target_object = Mast::AWS::ApplicationAutoscaling::ScalableTarget->new(
        aws_region => $self->aws_region,
        resource_id => '',
        aws => $self->aws,
      );
      $scalable_target_object->remove(
        cli_input_json => encode_json(\%deregister_scalable_target_payload)
      );
    }
    # Need to use Spec to enforce scaling policy use
    return undef;
}

sub tag_ecs_service {
  my ($self, %params) = @_;

  my $tags = $params{tags};
  my @svc_tags = map { +{ key => $_, value => $tags->{$_} } } keys %$tags;
  my $tag_json = encode_json(\@svc_tags);

  my $service = $self->get_service_object;
  my $service_name = $service->name;

  say "Checking if ECS service $service_name exists...";

  my $service_arn = $service->describe->{serviceArn};

  confess "Cannot update tags on ECS service $service_name, it does not exist"
    unless $service_arn;

  say "Adding tags to ECS service $service_name: " . encode_json $tags;

  $service->tag_resource(
    $service_arn,
    encode_json(\@svc_tags),
  );

  say "Successfully tagged ECS service $service_name";
}

sub update_current_active_service_tag_on_cluster {
  my ($self) = @_;

  my $cluster_name = $self->spec->ecs->{service}->{cluster};
  my $task_family = $self->spec->ecs->{taskDefinition}->{family};

  my $service_object = $self->get_service_object;
  my $cluster = $service_object->describe_cluster($cluster_name);
  # get image name and tag
  # We're going to assume the first is the image. Need to update the spec
  my $service_name = $service_object->name;

  my $tag = "active-$task_family";
  
  $service_object->tag_resource(
    $cluster->{clusterArn}, 
    encode_json([
      {
        'key' => $tag,
        'value' => $service_name
      }
    ]));
}

sub delete_current_active_service_tag_on_cluster {
  my ($self) = @_;

  my $cluster_name = $self->spec->ecs->{service}->{cluster};
  my $task_family = $self->spec->ecs->{taskDefinition}->{family};

  my $service_object = $self->get_service_object;
  my $cluster = $service_object->describe_cluster($cluster_name);
  # get image name and tag
  # We're going to assume the first is the image. Need to update the spec
  my $service_name = $service_object->name;

  my $tag = "active-$task_family";
  
  $service_object->untag_resource(
    $cluster->{clusterArn}, 
    encode_json([
        $tag,
    ]));
}

sub update_and_restart_ecs_service_tasks_with_new_task_definition {
  my ($self, %params) = @_;

  my $task_definition_arn = $params{task_definition_arn};

  my $service = $self->get_service_object;
  my $service_name = $service->name;

  confess "Cannot update ECS service $service_name with new task definition ARN, the service is not in a steady state"
    unless $service->is_in_steady_state();

  my $service_task_def_arn = $service->taskDefinitionArn;

  if ($task_definition_arn eq $service_task_def_arn) {
    say "ECS service $service_name has already been updated to task definition ARN $service_task_def_arn";

    return $service->describe;
  }

  say "Updating ECS service $service_name with new task definition ARN $task_definition_arn";

  my $printer = sub { say @_ };

  my @task_arns = $service->list_tasks($printer);

  # Updating a service with a new task definition ARN will start a deployment
  my $before_update = $service->update($printer,
    task_definition_arn => $task_definition_arn,
  );

  # If we kill the tasks above, the deployment caused by updating task definition ARN
  # will likely be still in progress.
  $service->wait_for_deployment($printer, $before_update);

  # Stopping a task takes a long time
  # $service->wait_for_task_status($printer, task_arns => [@task_arns], status => 'STOPPED');

  # Finally, confirm (and optionally wait for) the status is in steady state
  $service->wait_steady_state($printer);

  return $service->describe;
}

1;
