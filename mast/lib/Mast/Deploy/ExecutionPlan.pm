package Mast::Deploy::ExecutionPlan;

use v5.030;
use warnings;
no warnings 'uninitialized', 'unopened';

use Carp 'confess';

use JSON::PP;

use parent 'Mast::Deploy::Base';

use Mast::Service::Spec;
use Mast::Deploy::Service;
use Mast::Deploy::TargetGroups;
use Mast::AWS::VPC::SecurityGroup;

sub check_if_service_and_target_groups_already_created {
  my ($self) = @_;
  # TODO - we pass in the current active service until we have the execution spec
  my (%errors, %output);
  # check of cluster exists
  my $cluster_name = $self->spec->ecs->{service}->{cluster};

  my $cluster = do {
    my $res = $self->aws->ecs('describe-clusters', {
      clusters => [$cluster_name],
    });

    $res->{clusters}->[0];
  };

  $errors{'cluster names'} = "cluster doesn't exist" unless defined $cluster;
  $output{cluster_found} = 1;

  # check if service with same name already created
  my $service_name = $self->spec->ecs->{service}->{name};
  my $service = do {
    my $res = $self->aws->ecs('describe-services', {
      cluster => $cluster_name,
      services => [$service_name],
    });

    $res->{services}->[0];
  };

  $output{service_exists} = !!(defined $service and $service->{status} ne 'INACTIVE');

  # Special case: unless the service is in inactive status OR service returns undefined, consider it as existing
  $errors{'service names'} = "service already exists by this same name of: $service->{serviceArn}"
    if $output{service_exists} and not $self->spec->ecs->{service}->{allowExisting};

  # check if any of the target groups names already exist if elb config is found in spec
  my $ndtgs = $self->spec->elb->{targetGroups} if defined $self->spec->elb;
  my @found_tgs = ();

  # try to find each one
  for my $spec_tg (@{$ndtgs || []}) {
    my $tg = eval {
      my $res = $self->aws->elbv2('describe-target-groups', {
        names => [$spec_tg->{name}],
        'max-items' => 1,
      });

      $res->{TargetGroups}->[0];
    };
    if($@){
      if($@ !~ /TargetGroupNotFound/){
        confess $@;
      }
      # else we're glad we didn't find it
    } else {
      # add the offending target group to a list
      push @found_tgs, $spec_tg->{name} unless $spec_tg->{allowExisting};
    }
  }

  if (@found_tgs > 0){
    my $existing_tgs = join(", ", @found_tgs);
    my $tgs_count = scalar(@found_tgs);
    $errors{'target groups'} = "$tgs_count target groups already exist: $existing_tgs";
    $errors{'existing target groups count'} = $tgs_count;
  }
  
  return (\%errors, \%output);
}

# Define what is blue_green readiness
sub check_ecs_service_blue_green_deployment_readiness {
  my ($self, $current_active_service_spec_json, $environment) = @_;

  my $poll_interval //= 10;

  say "Environment: $environment";

  undef $current_active_service_spec_json if $current_active_service_spec_json eq '';
  confess "current active service spec not found. this is required for this workflow." unless defined $current_active_service_spec_json;

  undef $environment if $environment eq '';
  confess "environment not found. this is required for this workflow." unless defined $environment;


  my $current_active_service_spec = Mast::Service::Spec->new(
    environment => $environment,
    service_spec_json => $current_active_service_spec_json,
  );
  my $current_active_service = Mast::Deploy::Service->new(
    service_spec => $current_active_service_spec,
    poll_interval => $poll_interval,
  );
  my $service_spec = $self->spec;

  # TODO - we pass in the current active service until we have the execution spec
  my %potential_errors = ();
  
  # compare cluster names
  $potential_errors{cluster_names} = "cluster names don't match" if $current_active_service_spec->ecs->{service}->{cluster} ne $service_spec->ecs->{service}->{cluster};

  # compare service names
  $potential_errors{service_names} = "service names are matching" if $current_active_service_spec->ecs->{service}->{name} eq $service_spec->ecs->{service}->{name};

  # compare target groups names
  # If no target groups in spec i.e. empty or undefined? then should be undefined
  my $catgs = $current_active_service_spec->elb->{targetGroups};
  my $ndtgs = $service_spec->elb->{targetGroups};
  if(defined $catgs and defined $ndtgs){
    # filter just for target group names and sort them
    my @catgs = sort(map { $_->{name} } @$catgs);
    my @ndtgs = sort(map { $_->{name} } @$ndtgs);
    # back to scalar context
    $catgs = join("", @catgs);
    $ndtgs = join("", @ndtgs);
    # compare as string
    $potential_errors{target_groups} = "all target group names are the same" if $catgs eq $ndtgs;
  }
  return \%potential_errors;
}

sub check_ecs_service_rolling_deploy_readiness {
  my ($self) = @_;

  my $poll_interval //= 10;

  my $errors = $self->check_if_service_and_target_groups_already_created;
  # cluster is part of the spec and the only cluster we check;
  
  # TODO - we pass in the current active service until we have the execution spec
  my %potential_errors = ();
  
  # compare service names
  my $does_service_exist = $errors->{service_names};
  $potential_errors{service_name_not_found} = "service name in spec was not found" unless defined $does_service_exist;

  my $service_spec = $self->spec;
  # if target_groups not null, check that the number matches
  my $existing_target_groups_count = $errors->{existing_target_groups_count};
  if(defined $existing_target_groups_count){
    # just check that it matches the number of target groups found in the spec
    my $ndtgs = $service_spec->elb->{targetGroups};
    # get count and compare
    my $ndtgs_count = @{$ndtgs};
    $potential_errors{target_groups} = "not all the target groups from the spec were found" if $ndtgs_count != $existing_target_groups_count;
  }
  return \%potential_errors;
}

1;
