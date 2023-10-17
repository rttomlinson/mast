package Mast::Service::Spec::v1_0;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use parent 'Mast::Service::Spec';

use Carp 'confess';
use Scalar::Util 'looks_like_number';
use Mast::AWS::Fargate 'cpu_to_number', 'memory_to_number';

our @VERSION = (1.0, '1.0');

sub _normalize_spec {
  my ($self) = @_;

  $self->_validate_top_keys;

  # Values are normalized in situ
  $self->_normalize_elb;
  $self->_normalize_ecs;
  $self->_normalize_verification;
  $self->_normalize_tests;
  $self->_normalize_route53;

}

sub _normalize_route53 {
  my ($self) = @_;

  my $route53 = $self->{spec}->{route53};

  # this section is optional
  return unless defined $route53;

  confess "route53 is not an array"
    unless 'ARRAY' eq ref $route53;

  my $i = 0;

  for my $entry (@$route53) {
    $self->_normalize_record($entry, $i);
    $i++;
  }
}

sub _normalize_record {
  my ($self, $record, $index) = @_;

  my ($domain, $name, $type, $value) = @$record{qw(domain name type value)};

  confess "Route53 DNS domain name is required in route53[$index], got '$domain'"
    unless $domain;
  
  confess "Route53 DNS record name is required in route53[$index], got '$name'"
    unless $name;

  $record->{type} = uc $type;

  if ('HASH' eq ref $value) {
    my $aliasType = $value->{aliasType};

    if ($aliasType =~ /^applicationloadbalancer$/i) {
      my $aliasTarget = $value->{aliasTarget};

      confess "Target alias for record $name in Route53 domain $domain should include ALB name"
        unless $aliasTarget->{loadBalancerName};
    }
  }
}

sub route53 { shift->{spec}->{aws}->{route53} }

sub _validate_top_keys {
  my ($self) = @_;

  my $aws_spec = $self->{spec}->{aws};

  confess "AWS region is not defined"
    unless $aws_spec && length $aws_spec->{region} > 1;
}

sub _normalize_ecs {
  my ($self) = @_;

  my $ecs = $self->ecs;

  # This configuration is optional
  return unless defined $ecs;

  confess "ecs is not an object" unless 'HASH' eq ref $ecs;

  my ($service, $task_def, $ecs_tasks) = @$ecs{'service', 'taskDefinition', 'tasks'};

  $self->_normalize_ecs_service($service);
  $self->_normalize_ecs_task_definition($task_def);

  if(defined $ecs_tasks) {
    # Tasks are optional

    confess "ecs.tasks is not an object"
      unless 'HASH' eq ref $ecs_tasks;

    $self->_normalize_ecs_tasks($ecs_tasks);
  }
  
  return $ecs;
}

sub _normalize_ecs_tasks {
  my ($self, $ecs_tasks) = @_;

  for my $task_name (keys %$ecs_tasks) {
    $self->_normalize_ecs_task($task_name, $ecs_tasks->{$task_name});
  }
}

sub _normalize_ecs_task_definition {
  my ($self, $task_def) = @_;

  return unless defined $task_def;

  confess "taskDefinition is not an object" unless 'HASH' eq ref $task_def;

  my $container_defs = $task_def->{containerDefinitions};

  confess "containerDefinitions is not an array in ECS taskDefinition"
    unless 'ARRAY' eq ref $container_defs;
  
  {
    my $i = 0;

    for my $container (@$container_defs) {
      $self->_normalize_container($container, $i);
      $i++;
    }
  }

  # AWS API is very particular about the input types for cpu and memory task definition
  # parameters. These should be strings.
  $task_def->{cpu} = cpu_to_number($task_def->{cpu}) . "";
  $task_def->{memory} = memory_to_number($task_def->{memory}) . "";
}

sub _normalize_container {
  my ($self, $container, $index) = @_;

  confess "container configuration is not an object at containerDefinitions index $index"
    unless 'HASH' eq ref $container;

  my $container_name = $container->{name};

  # We require container name to avoid guessing at target group verification.
  # Note that we are NOT checking for definedness since "0" not a valid container name.
  confess "Container name is required at containerDefinitions index $index"
    unless $container_name;
  confess "Container image is required in container definition $container_name"
    unless $container->{image};

  # Command is optional
  if (defined (my $command = $container->{command})) {
    if ('ARRAY' eq ref $command) {
      $self->stringify($_) for @$command;
    }
  }

  my $env = $container->{environment};

  if (defined $env) {
    confess "environment is not an array in container definition $container_name"
      unless 'ARRAY' eq ref $env;
    
    my $i = 0;

    for my $env_var (@$env) {
      $self->_check_env_var($container, $env_var, $i);
      $i++;
    }
  }
  
  my $user = $container->{user};

  if (defined $user) {
    $container->{user} .= "";
  }

  if (defined (my $secrets = $container->{secrets})) {
    confess "secrets not an array in container definition $container_name"
      unless 'ARRAY' eq ref $secrets;
    
    my $i = 0;

    for my $secret (@$secrets) {
      $self->_check_secret($container, $secret, $i, $env);
    }
  }

  # Finally, we need to make sure the portMappings data types are correct.
  # AWS API is very specific about those.
  if (defined (my $ports = $container->{portMappings})) {
    confess "portMappings is not an array in container definition $container_name"
      unless 'ARRAY' eq ref $ports;

    my $i = 0;    

    for my $pm (@$ports) {
      confess "portMappings entry at index $i is not an object in container definition $container_name"
        unless 'HASH' eq ref $pm;
      
      $pm->{hostPort} = int $pm->{hostPort} if exists $pm->{hostPort};
      $pm->{containerPort} = int $pm->{containerPort} if exists $pm->{containerPort};
      $pm->{protocol} = lc $self->stringify($pm->{protocol}) if exists $pm->{protocol};
      $i++;
    }
  }

  if (defined (my $logConfig = $container->{logConfiguration})) {
    confess "logConfiguration is not an object in container definition $container_name"
      unless 'HASH' eq ref $logConfig;

    if (defined (my $options = $logConfig->{options})) {
      confess "logConfiguration.options is not an object in container definition $container_name"
        unless 'HASH' eq ref $options;
      
      $options->{Port} = "" . $options->{Port} if exists $options->{Port};
    }
  }
}

sub _check_env_var {
  my ($self, $container, $var, $index) = @_;

  confess q|Expected an object with "name" and "value" keys | .
          "for environment entry at index $index in container definition " .
          $container->{name}
    unless 'HASH' eq ref($var) and defined($var->{name}) and
      (defined($var->{value}) or defined($var->{valueFrom}));
  
  # AWS APIs are very specific: both name and value should be strings
  $var->{name} = $self->stringify($var->{name});
  $var->{value} = $self->stringify($var->{value}) if exists $var->{value};
  $var->{valueFrom} = $self->stringify($var->{valueFrom}) if exists $var->{valueFrom};
}

sub _check_secret {
  my ($self, $container, $secret, $index, $env) = @_;

  confess q|Expected an object with "name" and "valueFrom" keys | .
          "for secrets entry at index $index in container definition " .
          $container->{name}
    unless 'HASH' eq ref($secret) and defined($secret->{name})
           and defined $secret->{valueFrom};
  
  confess qq|Secret variable name "$secret->{name}" collides with environment | .
          qq|variable "$secret->{name}" in container definition $container->{name}|
    if grep { $_->{name} eq $secret->{name} } @$env;
  
  $secret->{name} = $self->stringify($secret->{name});
  $secret->{valueFrom} = $self->stringify($secret->{valueFrom});
}

sub _normalize_ecs_service {
  my ($self, $service) = @_;

  return unless defined $service;

  confess "ecs.service is not an object" unless 'HASH' eq ref $service;

  my $service_name = $service->{name};

  my $network = $service->{networkConfiguration};

  confess "networkConfiguration is not an object in ECS service $service_name"
    unless 'HASH' eq ref $network;

  $self->_normalize_ecs_network_configuration($network);
  $self->_normalize_ecs_service_load_balancers($service);
  $self->_normalize_ecs_scaling_policies_and_target($service);
}

sub _normalize_ecs_service_load_balancers {
  my ($self, $service) = @_;

  my $lbs = $service->{loadBalancers};

  # loadBalancers is not required for ecs services
  return unless defined $lbs;

  confess "loadBalancers is not an array in ECS service $service->{name}"
    unless 'ARRAY' eq ref $lbs;

  my $i = 0;

  for my $lb (@$lbs) {
    $self->_normalize_ecs_service_lb($service, $lb, $i);
    $i++;
  }
}

sub _normalize_ecs_network_configuration {
  my ($self, $network) = @_;

  if (defined (my $awsvpc = $network->{awsvpcConfiguration})) {
    $awsvpc->{securityGroups} = [$awsvpc->{securityGroups}]
      unless 'ARRAY' eq ref $awsvpc->{securityGroups};
    
    $awsvpc->{subnets} = [$awsvpc->{subnets}]
      unless 'ARRAY' eq ref $awsvpc->{subnets};
  }
}

sub _normalize_ecs_service_lb {
  my ($self, $service, $lb, $index) = @_;

  my $elb = $self->elb;

  return unless $elb;

  confess "loadBalancers entry at index $index is not an object " .
          "in ECS service $service->{name}"
    unless 'HASH' eq ref $lb;

  my ($container_name, $container_port) = @$lb{'containerName', 'containerPort'};

  confess "loadBalancers entry at index $index is expected to have " .
          "targetGroup property as an object with 'name' property in it"
    if 'HASH' ne ref($lb->{targetGroup}) or not exists $lb->{targetGroup}->{name};

  my $tg_name = $lb->{targetGroup}->{name};
  my $found;

  # This data structure has been validated before we reach this point
  for my $elb_tg (@{ $elb->{targetGroups} }) {
    if ($tg_name eq $elb_tg->{name} && $container_port == $elb_tg->{port}) {
      $found = 1;
      last;
    }
  }

  confess "Cannot find matching ELB target group configuration for container name $container_name"
    unless $found;
}

# Go ahead and do both here since we're introducing a soft dependency between the two. We can break them apart if needed
sub _normalize_ecs_scaling_policies_and_target {
  my ($self, $service) = @_;

  my $scaling_policy = $service->{scalingPolicy};

  return unless defined $scaling_policy;

  confess "scalingPolicy is not an object in ECS service $service->{name}"
    unless 'HASH' eq ref $scaling_policy;
  
  $self->_validate_ecs_scaling_policy($service);

  my $scalable_target = $service->{scalableTarget};

  confess "scalableTarget is not an object in ECS service $service->{name}"
    unless 'HASH' eq ref $scalable_target;

  my ($cluster_name, $name) = @$service{'cluster', 'name'};

  # Expect that ResourceId of each both follow the pattern of
  # `service/<cluster_name>/<service_name>`
  my $expected_resource_id = "service/$cluster_name/$name";
  my $scalable_target_resource_id = $scalable_target->{ResourceId};
  my $scaling_policy_target_resource_id = $scaling_policy->{ResourceId};

  confess "Scalable Target ResourceId is expected to match the pattern " .
          "'service/\$cluster_name/\$service_name' in ECS service $service->{name}"
    unless $scalable_target_resource_id =~ /^$expected_resource_id$/;

  confess "Scaling Policy ResourceId is expected to match the pattern " .
          "'service/\$cluster_name/\$service_name' in ECS service $service->{name}"
    unless $scaling_policy_target_resource_id =~ /^$expected_resource_id$/;
}

sub _validate_ecs_scaling_policy {
  my ($self, $service) = @_;

  my $scaling_policy = $service->{scalingPolicy};
  my $policy_type = $scaling_policy->{PolicyType};

  return unless $policy_type eq 'TargetTrackingScaling';

  return unless 'HASH' eq ref($scaling_policy->{TargetTrackingScalingPolicyConfiguration})
            and 'HASH' eq ref($scaling_policy->{TargetTrackingScalingPolicyConfiguration}->{PredefinedMetricSpecification});

  my $predefined_metric_specification
    = $scaling_policy->{TargetTrackingScalingPolicyConfiguration}->{PredefinedMetricSpecification};
  
  my $predefined_metric_type = $predefined_metric_specification->{PredefinedMetricType};

  if ($predefined_metric_type eq 'ALBRequestCountPerTarget') {
    my $resource_label = $predefined_metric_specification->{ResourceLabel};

    confess "Scaling policy for ECS service $service->{name} is configured for ".
            "tracking ALBRequestCountPerTarget metric. The policy is expected to have " .
            "TargetTrackingScalingPolicyConfiguration.PredefinedMetricSpecification.ResourceLabel " .
            "property as an object with loadBalancerName and targetGroupName properties in it"
      unless 'HASH' eq ref($resource_label)
          and defined $resource_label->{loadBalancerName}
          and $resource_label->{targetGroupName};
  }
}

sub _normalize_elb {
  my ($self) = @_;

  my $elb = $self->elb;
  # worker type won't have an elb
  return unless $elb;

  confess "elb is not an object" unless 'HASH' eq ref $elb;
  # Target groups need to be normalized first since load balancer routing rule validation
  # involves looking up a target group by name.
  $self->_normalize_elb_target_groups($elb);
  $self->_normalize_elb_load_balancers($elb);
}

sub _normalize_elb_load_balancers {
  my ($self, $elb) = @_;
  
  my $lbs = $elb->{loadBalancers};

  confess "Missing elb.loadBalancers configuration in elb section" unless defined $lbs;
  confess "elb.loadBalancers is not an array" unless 'ARRAY' eq ref $lbs;
    
  for my $lb (@$lbs) {

    $self->_normalize_elb_load_balancer($lb);
  }

  $self->_validate_elb_load_balancers($lbs);
}

sub _normalize_elb_load_balancer {
  my ($self, $lb) = @_;

  confess "loadBalancer is not an object" unless 'HASH' eq ref $lb;
  confess "elb.loadBalancer value requires a name keyword" unless exists $lb->{name};
  confess "elb.loadBalancer value requires a type keyword" unless exists $lb->{type};
  $self->_validate_elb_load_balancer($lb);
  $self->_validate_aws_elb_name($lb->{name});
  $self->_validate_aws_elb_type($lb);



  if ($lb->{securityGroups} && not ('ARRAY' eq ref $lb->{securityGroups})) {
    $lb->{securityGroups} = [$lb->{securityGroups}];
  }

  my $listeners = $lb->{listeners};
  confess "elb.listeners is not an array in $lb->{type} load balancer $lb->{name}"
    unless 'ARRAY' eq ref $listeners;
  for my $listener (@$listeners) {
    $self->_normalize_elb_load_balancer_listener($listener, $lb);
  }
}

sub _validate_elb_load_balancers {
  my ($self, $lbs) = @_;

  # do some validity checks to prevent unexpected behavior. e.g. overwriting listener rules when overlapping
  # check that if lb name repeats that listener ports are not matching
  my %name_port_pairs;

  foreach (@$lbs) {
    my $lb_name = $_->{name};
    my $listener_specs = $_->{listeners};
    for my $listener_spec (@$listener_specs) {
      if(defined $name_port_pairs{"$lb_name$listener_spec->{port}"}){
        $name_port_pairs{"$lb_name$listener_spec->{port}"} = $name_port_pairs{"$lb_name$listener_spec->{port}"} + 1;
      } else {
        $name_port_pairs{"$lb_name$listener_spec->{port}"} = 1;
      }
    }
  }
  my @all_matches = grep { $name_port_pairs{$_} > 1 } keys %name_port_pairs;

  confess "At least one repeat load balancer and listener port found. List: @all_matches. You can combine rules."
    if scalar @all_matches;

  # validate that target group is not used on more than one load balancer
  my %target_group_name_to_elb_name;
  foreach (@$lbs) {
    my $lb_name = $_->{name};
    my $listener_specs = $_->{listeners};
    for my $listener_spec (@$listener_specs) {
      if ($_->{type} eq 'network') {
        my $target_group_name = $listener_spec->{action}->{targetGroupName};
        if(defined $target_group_name_to_elb_name{"$target_group_name"}){
          confess "Same target group cannot be on multiple different elbs" unless $target_group_name_to_elb_name{"$target_group_name"} eq $lb_name;
        } else {
          $target_group_name_to_elb_name{"$target_group_name"} = $lb_name;
        }
      }
      if(defined $name_port_pairs{"$lb_name$listener_spec->{port}"}){
        $name_port_pairs{"$lb_name$listener_spec->{port}"} = $name_port_pairs{"$lb_name$listener_spec->{port}"} + 1;
      } else {
        $name_port_pairs{"$lb_name$listener_spec->{port}"} = 1;
      }
    }
  }

}

sub _validate_elb_load_balancer {
  my ($self, $lb, $index) = @_;

  confess "elb.loadBalancer[$index] is not an object" unless 'HASH' eq ref $lb;
  confess "elb.loadBalancer[$index] value requires a name keyword" unless exists $lb->{name};
  confess "elb.loadBalancer[$index] value requires a type keyword" unless exists $lb->{type};
}

sub _validate_aws_elb_name {
  my ($self, $name) = @_;

  confess "Invalid load balancer name: null" unless defined $name;

  confess "Load balancer name $name is not scalar. This means that you probably did not provide an appropriate value for the environment you provided"
    if ref $name;
  
  confess qq|ELB load balancer name length cannot exceed 32 characters, got "$name"|
    if length $name > 32;
  
  confess qq|Invalid ELB load balancer name, only alphanumerics and hyphens are permitted: got "$name"|
   unless $name =~ /^[-a-zA-Z0-9]+$/;
  
  confess qq|Invalid ELB load balancer name "$name", cannot start or end with a hyphen|
    if $name =~ /^-|-$/;
}

sub _validate_aws_elb_type {
  my ($self, $lb) = @_;

  confess "Unsupported type. '$lb->{type}' in load balancer $lb->{name}: " .
          "expected 'application' or 'network'"
    unless $lb->{type} =~ /^(application|network)$/;
}



sub _normalize_elb_load_balancer_listener {
  my ($self, $listener, $lb) = @_;
  $self->_normalize_elb_load_balancer_listener_protocol($listener, $lb);
  $self->_normalize_elb_load_balancer_listener_port($listener, $lb);
  
  $self->_normalize_elb_load_balancer_listener_ruleset($listener, $lb) if $lb->{type} eq 'application';
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

sub _normalize_elb_load_balancer_listener_port {
  my ($self, $listener, $lb) = @_;

  confess "Invalid listener port in $lb->{type} load balancer $lb->{name}: expected integer > 0, got $listener->{port}"
    unless defined($listener->{port})
       and looks_like_number $listener->{port}
       and $listener->{port} > 0;
  
  $listener->{port} = int $listener->{port};
}

sub _normalize_elb_load_balancer_listener_ruleset {
  my ($self, $listener, $lb) = @_;

  my $ruleset = $listener->{rules};

  $self->_normalize_elb_load_balancer_listener_rules($ruleset, $lb);

  confess "listener.rules is not an array in $lb->{type} load balancer $lb->{name}"
    unless 'ARRAY' eq ref $ruleset;
  

  $self->_normalize_elb_load_balancer_listener_rules($ruleset, $lb);
}

sub _normalize_elb_load_balancer_listener_rules {
  my ($self, $rules, $lb) = @_;

  my $i = 0;

  for my $rule (@$rules) {
    $self->_normalize_elb_load_balancer_listener_rule($rules, $i, $lb);
    $i++;
  }
}

sub _normalize_elb_load_balancer_listener_rule {
  my ($self, $rules, $index, $lb) = @_;

  my $rule = $rules->[$index];

  confess "listener rule at index $index is not an object ".
          "in $lb->{type} load balancer $lb->{name}"
    unless 'HASH' eq ref $rule;

  $rule->{placement} = lc $self->stringify($rule->{placement});

  confess "Invalid placement value '$rule->{placement}' for listener rule at index $index ".
          "in $lb->{type} load balancer $lb->{name}"
    unless $rule->{placement} =~ /^(?:start|end)$/;
  
  # TODO Conditions validation

  $self->_validate_elb_load_balancer_listener_rule_action($rule, $index, $lb);
}

sub _validate_elb_load_balancer_listener_rule_action {
  my ($self, $rule, $index, $lb) = @_;

  my $action = $rule->{action};

  confess "Action types other than 'forward' are not supported at this time"
    unless $action->{type} eq 'forward';
  
  my $targetGroupName = $action->{targetGroupName};

  # This structure is already validated at this point
  my $target_groups = $self->elb->{targetGroups};
  my $found;

  for my $tg (@$target_groups) {
    if ($tg->{name} eq $targetGroupName) {
      $found = 1;
      last;
    }
  }

  confess "Invalid action for listener rule at index $index: " .
          "cannot find target group $targetGroupName in elb.targetGroups list"
    unless $found;
}

sub _normalize_elb_target_groups {
  my ($self, $elb) = @_;

  my $tgs = $elb->{targetGroups};

  confess "Missing target group configuration in elb section" unless defined $tgs;
  confess "elb.targetGroups is not an array" unless 'ARRAY' eq ref $tgs;

  my $i = 0;

  for my $tg (@$tgs) {
    $self->_normalize_elb_target_group($tg, $i);
    $i++;
  }
}

sub _normalize_elb_target_group {
  my ($self, $tg, $index) = @_;

  confess "elb.targetGroups entry at index $index is not an object"
    unless 'HASH' eq ref $tg;

  $self->_validate_elb_target_group_name($tg->{name}, $index);

  # We don't pass index to these because target group is expected to have a valid name
  # at this point, and error messages will contain the name instead of index.
  $self->_normalize_elb_target_group_protocol($tg);
  $self->_normalize_elb_target_group_health_check($tg);
}

sub _validate_elb_target_group_name {
  my ($self, $name, $index) = @_;

  confess "Target group name is required at elb.targetGroups index $index"
    unless length $name > 0;

  confess qq|Target group name length cannot exceed 32 characters, got "$name" at elb.targetGroups index $index|
    if length $name > 32;    

  confess qq|Invalid target group name "$name", only alphanumerics and hyphens are permitted at elb.targetGroups index $index|
    unless $name =~ /^[-a-zA-Z0-9]+$/;

  confess qq|Invalid target group name "$name", cannot start or end with a hyphen at elb.targetGroups index $index|
    if $name =~ /^-|-$/;
  
  return;
}

sub _normalize_elb_target_group_protocol {
  my ($self, $tg, $lb) = @_;

  $tg->{protocol} = uc $self->stringify($tg->{protocol});

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

sub _normalize_elb_target_group_health_check {
  my ($self, $tg) = @_;

  my $hc = $tg->{healthCheck};

  confess "healthCheck is not an object in ELB target group $tg->{name}"
    unless 'HASH' eq ref $hc;
  
  $self->_normalize_elb_target_group_health_check_protocol($hc, $tg);

  if (defined (my $matcher = $hc->{matcher})) {
    $self->_normalize_elb_target_group_health_check_matcher($matcher, $hc, $tg);
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

sub _normalize_elb_target_group_health_check_matcher {
  my ($self, $matcher, $hc, $tg) = @_;

  confess "healthCheck.matcher is not an object in ELB target group $tg->{name}"
    unless 'HASH' eq ref $matcher;
  
  $matcher->{HttpCode} = $self->stringify($matcher->{HttpCode})
    if exists $matcher->{HttpCode};
}

sub _normalize_verification {
  my ($self) = @_;

  my $verification = $self->verification;

  return unless defined $verification;

  confess "verification is not an object"
    unless 'HASH' eq ref $verification;

  $verification->{protocol} = lc $self->stringify($verification->{protocol})
    if defined $verification->{protocol};
  
  if (defined (my $request = $verification->{request})) {
    confess "verification.request is not an object"
      unless 'HASH' eq ref $request;
    
    confess "verification.request.headers is not an array"
      unless 'ARRAY' eq ref $request->{headers};
    
    my @headers;
    my $i = 0;

    for my $header (@{ $request->{headers} || [] }) {
      if ('HASH' eq ref $header) {
        for my $hdr (keys %$header) {
          push @headers, "$hdr: " . $self->stringify($header->{$hdr});
        }
      }
      elsif ('ARRAY' eq ref $header) {
        confess "Array of headers is not expected at verification.request.headers entry index $i";
      }
      else {
        push @headers, $header;
      }

      $i++;
    }

    $request->{headers} = [@headers];
  }
  
  # Response HTTP status can be either one scalar, or an array. Normalize to array.
  if (defined (my $response = $verification->{response})) {
    confess "verification.response is not an object"
      unless 'HASH' eq ref $response;
    
    $response->{status} = [$response->{status}]
      if defined($response->{status}) and 'ARRAY' ne ref $response->{status};
    
    confess "verification.response.body should be a string"
      if defined($response->{body}) and ref $response->{body};
  }
}

sub _normalize_tests {
  my ($self) = @_;

  confess "tests section is not supported, use ecs.tasks section instead"
    if exists $self->{spec}->{tests};
}

sub tests {
  my ($self) = @_;

  warn 'tests method is deprecated, use ecs.tasks instead';

  my $ecs_tasks = $self->ecs->{tasks} // {};

  my $tests = {};

  for my $task_name (keys %$ecs_tasks) {
    $tests->{$task_name} = {
      type => 'ecsTask',
      ecsTask => $ecs_tasks->{$task_name},
    };
  }

  return $tests;
}

# sub _normalize_test_suite {
#   my ($self, $test_name, $test) = @_;

#   confess "Test suite $test_name: types other than ecsTask are not supported at the time"
#     unless $test->{type} eq 'ecsTask';

#   my $task = $test->{ecsTask};

#   return $self->_normalize_ecs_task($test_name, $task);
# }

sub _normalize_ecs_task {
  my ($self, $task_name, $task) = @_;

  confess "ECS task $task_name should be an object"
    unless 'HASH' eq ref $task;

  confess "ECS task $task_name: Cluster name is required"
    unless defined $task->{cluster};

  my $task_def = $task->{taskDefinition};

  confess "ECS task $task_name: task family is required"
    unless $task_def->{family};

  $self->_normalize_ecs_task_definition($task_def);

  my %log_groups;

  my $container_defs = $task_def->{containerDefinitions};

  confess "containerDefinitions should be an array in ECS task $task_name"
    unless 'ARRAY' eq ref $container_defs;

  for my $container (@$container_defs) {
    my $log_config = $container->{logConfiguration};

    confess "ECS task $task_name: Log drivers other than awslogs are not supported at this time"
      unless $log_config->{logDriver} eq 'awslogs';
    
    my $options = $log_config->{options};

    confess "ECS task $task_name: Log configuration options should include 'awslogs-stream-prefix' and 'awslogs-group' properties"
      if not $options or not $options->{'awslogs-stream-prefix'}
          or not $options->{'awslogs-group'};
  }

  if ($task_def->{networkMode} eq 'awsvpc') {
    confess "ECS task $task_name: Task definition set to awsvpc but networkConfiguration section is not found"
      unless exists $task->{networkConfiguration}
          && exists $task->{networkConfiguration}->{awsvpcConfiguration};
  }

  $self->_normalize_ecs_network_configuration($task->{networkConfiguration});

  return $task;
}

# AWS region is special and as such warrants a getter
sub aws_region { shift->{spec}->{aws}->{region} }
sub service_spec { shift->{spec} }
sub deploy { shift->{spec}->{deploy} }
sub elb { shift->{spec}->{aws}->{elb} }
sub ecs { shift->{spec}->{aws}->{ecs} }
sub verification { shift->{spec}->{verification} }

sub find_elb_target_group {
  my ($self, %params) = @_;

  my $elb = $self->elb;
  my $tgs = $elb->{targetGroups};

  for my $tg (@$tgs) {
    return $tg if defined($params{name}) && $params{name} eq $tg->{name};
    return $tg if (defined($params{protocol}) && defined($params{port}))
               && ($params{protocol} eq $tg->{protocol} && $params{port} == $tg->{port});
  }
}

1;