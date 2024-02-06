package Mast::Deploy::Step;

use v5.030;
use warnings;
no warnings 'uninitialized';
use Carp 'confess';
use Exporter 'import';
use JSON::PP;
use Scalar::Util 'looks_like_number';

use Mast::Cloud::Spec;
use Mast::Cloud::Metadata;
use Mast::Cloud::Verification;
use Mast::Deploy::Listeners;
use Mast::Deploy::ExecutionPlan;
use Mast::Deploy::TaskDefinition;
use Mast::Deploy::DNS;

use Mast::AWS::ECS::TaskDefinition;
use Mast::AWS::ECS::Task;
use Mast::AWS::ECS::Service;

our @EXPORT = qw(
    get_image_configuration_from_cloud_spec_url
    get_cloud_spec_from_cloud_spec_url
    validate_cloud_spec
    get_cloud_spec_from_active_service_cluster_tag
    check_if_active_service_found_on_cluster_for_given_task_definition_family_name
    check_blue_green_readiness
    check_ecs_service_rolling_deploy_readiness
    create_ecs_task_definition
    create_elb_target_groups
    update_elb_listener_rules
    update_elb_listeners
    create_or_update_ecs_service
    tag_ecs_service
    scale_ecs_service
    scale_ecs_service_down_for_deletion
    verify_service
    register_service_as_scalable_target_and_attach_scaling_policy
    tag_elb_target_groups
    update_current_active_service_tag_on_cluster
    delete_elb_listeners
    delete_elb_listener_rules
    delete_elb_target_groups
    deregister_service_as_scalable_target_and_delete_scaling_policy
    run_test
    run_ecs_task
    create_route53_records
    delete_route53_records
);

sub get_image_configuration_from_cloud_spec_url {
    my %params = @_;

    return Mast::Cloud::Metadata::get_image_configuration_from_spec_url(
        $params{cloud_spec_url},
        %params,
    );
}

sub get_cloud_spec_from_cloud_spec_url {
    my %params = @_;

    return Mast::Cloud::Metadata::get_cloud_spec_from_url(
        $params{cloud_spec_url},
        %params,
    );
}

sub validate_cloud_spec {
    my $spec = Mast::Cloud::Spec->new(@_);

    return $spec;
}

sub get_cloud_spec_from_ecs_service {
    my %params = @_;

    my $meta = Mast::Cloud::Metadata->new(aws_region => $params{aws_region});

    return $meta->get_cloud_spec_from_task_definition_tag_using_ecs_service_name(%params);
}

# This one expects that the `active-<family-name>` tag on the cluster is a ecs service name
# this ecs service name value is then used to look up the `cloud_spec_url` tag on the corresponding
# task definition (including revision) for where to find the actual service spec that was used to create
# these resources. url is either docker:// or github:// at the time of this writing
sub get_cloud_spec_from_active_service_cluster_tag {
    my %params = @_;

    my ($contexts, $cloud_spec_json) = @params{qw(contexts cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $cluster_name = $cloud_spec->ecs->{service}->{cluster};
    my $task_family = $cloud_spec->ecs->{taskDefinition}->{family};
    my $metadata_service = Mast::Cloud::Metadata->new(
        aws_region => $cloud_spec->aws_region,
    );

    my ($current_active_cloud_spec_json, $spec_url) = $metadata_service->get_cloud_spec_from_active_service_cluster_tag(
        cluster_name => $cluster_name,
        task_family => $task_family,
        %params,
    );

    return ($current_active_cloud_spec_json, $spec_url);
}

sub check_if_active_service_found_on_cluster_for_given_task_definition_family_name {
    my %params = @_;

    my ($cloud_spec_json,)
        = @params{qw(cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $cluster_name = $cloud_spec->ecs->{service}->{cluster};
    my $task_family = $cloud_spec->ecs->{taskDefinition}->{family};
    my $metadata_service = Mast::Cloud::Metadata->new(
        aws_region => $cloud_spec->aws_region,
    );

    return $metadata_service->check_if_tag_exists_on_cluster(
        cluster_name => $cluster_name,
        tag_name => "active-$task_family",
    );
}


sub check_ecs_service_rolling_deploy_readiness {
    my %params = @_;
    my ($cloud_spec_json) = @params{qw(contexts cloud_spec_json)};

    # confess "contexts not found. this is required for this workflow." unless defined $contexts;
    confess "cloud_spec not found. this is required for this workflow." unless defined $cloud_spec_json;

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $plan = Mast::Deploy::ExecutionPlan->new(
        aws_region => $cloud_spec->aws_region,
        cloud_spec => $cloud_spec,
    );
    my $potential_errors = $plan->check_ecs_service_rolling_deploy_readiness;
    my %potential_errors = %{$potential_errors};
    my @keys = keys %potential_errors;
    if(scalar(@keys) > 0){
    # inform user of potential errors then exit
        say "We found some potential errors for this type of workflow.";
        for(@keys){
            say "Potential error with: $_. Condition found is: $potential_errors{$_}.";
        }
        confess "throwing error in check_ecs_service_rolling_deploy_readiness";
    }
}

sub check_blue_green_readiness {
    my %params = @_;
    
    my ($contexts, $cloud_spec_json, $current_active_cloud_spec_json)
        = @params{qw(contexts cloud_spec_json current_active_cloud_spec_json)};

    $contexts //= [];
    confess "cloud_spec not found. this is required for this workflow." unless defined $cloud_spec_json;
    confess "current_active_cloud_spec_json not found. this is required for this workflow." unless defined $current_active_cloud_spec_json;

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $plan = Mast::Deploy::ExecutionPlan->new(
        aws_region => $cloud_spec->aws_region,
        cloud_spec => $cloud_spec,
    );

    my $potential_errors = $plan->check_ecs_service_blue_green_deployment_readiness($current_active_cloud_spec_json, $contexts);
    my %potential_errors = %{$potential_errors};

    my @keys = keys %potential_errors;
    if(scalar(@keys) > 0){
    # inform user of potential errors then exit
        say "We found some potential errors for this type of workflow.";
        for(@keys){
            say "Potential error with: $_. Condition found is: $potential_errors{$_}.";
        }
        confess "throwing error in check_blue_green_readiness";
    }
}

sub check_if_service_and_target_groups_already_exist {
    my %params = @_;

    my ($contexts, $cloud_spec_json) = @params{qw(contexts cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $plan = Mast::Deploy::ExecutionPlan->new(
        aws_region => $cloud_spec->aws_region,
        cloud_spec => $cloud_spec,
    );

    my ($errors, $output) = $plan->check_if_service_and_target_groups_already_created;

    if (scalar(keys %$errors) > 0){
    # inform user of potential errors then exit
        for (keys %$errors){
            say "Potential error with: $_. Condition found is: $errors->{$_}.";
        }
        die "Spec condition violations found, exiting with an error.\n";
    }

    return $output;
}

sub create_ecs_task_definition {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $cloud_spec_url)
        = @params{qw(contexts cloud_spec_json cloud_spec_url)};
    
    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::TaskDefinition->new(
        cloud_spec => $cloud_spec,
    );

    # TODO: validate url formats
    my $task_definition_arn = $deploy_step->create_task_definition(
        cloud_spec_url => $cloud_spec_url,
    );

    return $task_definition_arn;
}

sub create_elb_target_groups {
    my %params = @_;

    my ($contexts, $cloud_spec_json)
        = @params{qw(contexts cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::TargetGroups->new(
        cloud_spec => $cloud_spec,
    );

    my @created = $deploy_step->create_target_groups;
    my @output
        = map { +{ TargetGroupName => $_->{TargetGroupName}, TargetGroupArn => $_->{TargetGroupArn} } }
                @created;

    return encode_json \@output;
}

sub tag_elb_target_groups {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $tags)
        = @params{qw(contexts cloud_spec_json tags)};
    
    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::TargetGroups->new(
        cloud_spec => $cloud_spec,
    );

    return $deploy_step->tag_target_groups(tags => $tags);
}

sub update_elb_listener_rules {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $rule_role)
        = @params{qw(contexts cloud_spec_json rule_role)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::ListenerRules->new(
        cloud_spec => $cloud_spec,
    );

    return $deploy_step->update_listener_rules($rule_role);
}

sub update_elb_listeners {
    my %params = @_;

    my ($contexts, $cloud_spec_json)
        = @params{qw(contexts cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => $contexts,
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Listeners->new(
        cloud_spec => $cloud_spec,
    );

    return $deploy_step->update_listeners;
}

sub delete_elb_listeners {
    my %params = @_;

    my ($contexts, $cloud_spec_json)
        = @params{qw(contexts cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Listeners->new(
        cloud_spec => $cloud_spec,
    );

    return $deploy_step->delete_listeners;
}

sub create_or_update_ecs_service {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $task_definition_arn,
        $overrides, $poll_interval)
        = @params{qw(contexts cloud_spec_json task_definition_arn
                     overrides poll_interval)};

    $poll_interval = $poll_interval // 10;

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    return $deploy_step->create_or_update_ecs_service(
        task_definition_arn => $task_definition_arn,
        service_overrides => $overrides,
    );
}

sub tag_ecs_service {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $tags)
        = @params{qw(contexts cloud_spec_json tags)};
    
    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
    );

    return $deploy_step->tag_ecs_service(tags => $tags);
}

sub scale_ecs_service {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $desired_count,
        $current_active_cloud_spec_json, $poll_interval)
        = @params{qw(contexts cloud_spec_json desired_count
                     current_active_cloud_spec_json poll_interval)};
    
    $poll_interval = $poll_interval // 10;

    undef $current_active_cloud_spec_json if $current_active_cloud_spec_json eq '';
    undef $desired_count unless looks_like_number $desired_count;

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $current_active_service = undef;

    if(defined $current_active_cloud_spec_json){
        my $current_active_cloud_spec = Mast::Cloud::Spec->new(
            contexts => [],
            cloud_spec_json => $current_active_cloud_spec_json,
        );

        $current_active_service = Mast::Deploy::Service->new(
            cloud_spec => $current_active_cloud_spec,
            poll_interval => $poll_interval,
        );
    }

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    # TODO - we pass in the current active service until we have the execution spec
    # The execution spec will just contain the number of tasks. It will resolve 'match'
    my $service_arn = $deploy_step->scale_task_count($desired_count, $current_active_service);

    return $service_arn;
}

sub scale_ecs_service_down_for_deletion {
    my %params = @_;

    my ($contexts, $cloud_spec_json,
        $current_active_cloud_spec_json, $poll_interval)
        = @params{qw(contexts cloud_spec_json
                     current_active_cloud_spec_json poll_interval)};
    
    $poll_interval = $poll_interval // 10;

    undef $current_active_cloud_spec_json if $current_active_cloud_spec_json eq '';

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $current_active_service = undef;

    if(defined $current_active_cloud_spec_json){
        my $current_active_cloud_spec = Mast::Cloud::Spec->new(
            contexts => [],
            cloud_spec_json => $current_active_cloud_spec_json,
        );

        $current_active_service = Mast::Deploy::Service->new(
            cloud_spec => $current_active_cloud_spec,
            poll_interval => $poll_interval,
        );
    }

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    # If service does not exist OR is INACTIVE, we consider it already deleted and a success of this specific function
    # This returns undefined if service does not exist or is INACTIVE
    my $ecs_service = $deploy_step->get_service_object->describe;
    if(defined $ecs_service) {
        my $desired_count = 0;
        # TODO - we pass in the current active service until we have the execution spec
        # The execution spec will just contain the number of tasks. It will resolve 'match'
        my $service_arn = $deploy_step->scale_task_count($desired_count, $current_active_service);

        return $service_arn;
    } else {
        # Do nothing
        return;
    }
}

sub verify_service {
    my %params = @_;
    my ($contexts, $cloud_spec_json) = @params{'contexts', 'cloud_spec_json'};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $verificator = Mast::Cloud::Verification->new(
        cloud_spec => $cloud_spec,
    );

    $verificator->verify_service;
}

sub register_service_as_scalable_target_and_attach_scaling_policy {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $poll_interval)
        = @params{qw(contexts cloud_spec_json poll_interval)};

    $poll_interval //= 10;

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    my $code = $deploy_step->register_service_as_scalable_target_and_attach_scaling_policy;
    if(defined $code){
        if($code =~ /scalable target config not found/) {
            say "scalable target config not found. continuing."
        } elsif($code =~ /scaling policy config not found/) {
            say "scaling policy config not found. continuing."
        } else {
            confess "Error message: $code.";
        }
    }
}

sub update_current_active_service_tag_on_cluster {
    my %params = @_;
    my ($contexts, $cloud_spec_json)
        = @params{qw(contexts cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
    );

    # TODO: More descriptive type of tagging
    $deploy_step->update_current_active_service_tag_on_cluster;
}

sub delete_elb_listener_rules {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $rule_role)
        = @params{qw(contexts cloud_spec_json rule_role)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::ListenerRules->new(
        cloud_spec => $cloud_spec,
    );

    return $deploy_step->delete_listener_rules($rule_role);
}

sub delete_elb_target_groups {
    my %params = @_;

    my ($contexts, $cloud_spec_json)
        = @params{qw(contexts cloud_spec_json)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::TargetGroups->new(
        cloud_spec => $cloud_spec,
    );

    return $deploy_step->delete_target_groups_with_spec;
}

sub deregister_service_as_scalable_target_and_delete_scaling_policy {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $poll_interval)
        = @params{qw(contexts cloud_spec_json poll_interval)};

    $poll_interval = $poll_interval // 10;

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    my $code = $deploy_step->deregister_service_as_scalable_target_and_delete_scaling_policy;
    if(defined $code){
        confess "Error message: $code.";
    }
}

sub delete_ecs_service {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $poll_interval)
        = delete @params{qw(contexts cloud_spec_json poll_interval)};

    confess "service spec not found. this is required for this step."
        unless defined $cloud_spec_json and $cloud_spec_json ne '';

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    return $deploy_step->delete_ecs_service(%params);
}

sub run_test {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $test_name, $poll_interval)
        = @params{qw(contexts cloud_spec_json test_name poll_interval)};
    
    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $test = $cloud_spec->tests->{$test_name};

    confess "Cannot find test definition for $test_name"
        unless $test;
    
    my $ecs_task = $test->{ecsTask};
    
    return execute_ecs_task(
        aws_region => $cloud_spec->aws_region,
        ecs_task => $ecs_task,
        poll_interval => $poll_interval,
    );
}

sub run_ecs_task {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $task_name, $poll_interval)
        = @params{qw(contexts cloud_spec_json task_name poll_interval)};
    
    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $task_spec = $cloud_spec->ecs->{tasks}->{$task_name};

    confess "Cannot find ECS task specification for $task_name"
        unless $task_spec;
    
    return execute_ecs_task(
        aws_region => $cloud_spec->aws_region,
        ecs_task => $task_spec,
        poll_interval => $poll_interval,
    );
}

sub execute_ecs_task {
    my %params = @_;

    my ($aws_region, $ecs_task, $poll_interval)
        = @params{qw(aws_region ecs_task poll_interval)};

    say "Creating ECS task definition...";

    my $task_def = Mast::AWS::ECS::TaskDefinition->new(
        aws_region => $aws_region,
        cluster => $ecs_task->{cluster},
        %{$ecs_task->{taskDefinition}},
    );
    
    my $task_def_arn = $task_def->create;

    say "Successfully created ECS task definition with ARN $task_def_arn";

    my $task_executor = Mast::AWS::ECS::Task->new(
        aws_region => $aws_region,
        poll_interval => $poll_interval,
        cluster => $ecs_task->{cluster},
        task_definition_arn => $task_def_arn,
        desired_count => $ecs_task->{desiredCount},
        launch_type => $ecs_task->{launchType},
        network_configuration => $ecs_task->{networkConfiguration},
    );

    $task_executor->execute(sub { say @_ });
    $task_executor->watch_logs(sub { say @_ });

    say "All ECS tasks has stopped, deregistering ECS task definition with ARN $task_def_arn";

    $task_def->remove;

    say "Successfully deregistered ECS task definition";

    $task_executor->print_container_exit_codes(sub { say @_ });

    my $worst = $task_executor->get_container_with_highest_exit_code;

    if ($worst) {
        my $exit_code = $worst->{exitCode};

        say "Essential container $worst->{name} in task id $worst->{taskId} " .
            "exited with code $exit_code, using this as overall test suite exit code.";

        # If something went wrong and there is no defined exit code
        # for a container, we want this to attract some attention.
        return $exit_code // 1;
    }
    else {
        # In case there is an error and we couldn't find any exit codes,
        # this would definitely need attention so let's exit with an error.
        confess "Could not find exit code for any essential containers!";
    }
}

sub update_ecs_service {
    my %params = @_;

    my ($contexts, $cloud_spec_json, $poll_interval)
        = delete @params{qw(contexts cloud_spec_json poll_interval)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::Service->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    $deploy_step->update_ecs_service(%params);
}

sub create_route53_records { modify_route53_records('create_dns_records', @_) }
sub delete_route53_records { modify_route53_records('delete_dns_records', @_) }

sub modify_route53_records {
    my ($step_action, %params) = @_;

    my ($cloud_spec_json, $poll_interval)
        = delete @params{qw(cloud_spec_json poll_interval)};

    my $cloud_spec = Mast::Cloud::Spec->new(
        contexts => [],
        cloud_spec_json => $cloud_spec_json,
    );

    my $deploy_step = Mast::Deploy::DNS->new(
        cloud_spec => $cloud_spec,
        poll_interval => $poll_interval,
    );

    $deploy_step->$step_action;
}

1;
