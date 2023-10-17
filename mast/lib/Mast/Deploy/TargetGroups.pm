package Mast::Deploy::TargetGroups;

use v5.030;
use warnings;
no warnings 'uninitialized', 'unopened';

use Carp 'confess', 'cluck';

use parent 'Mast::Deploy::Base';

use Mast::Cloud::Spec;
use Mast::AWS::ELB::TargetGroup;

sub get_target_group_objects {
  my ($self, %params) = @_;

  my @targets = @{$self->spec->ecs->{service}->{loadBalancers}};
  my @target_groups = ();

  for my $item (@targets) {
    
    my $tg = $self->_resolve_target_group($item);
    $tg->describe; # This verifies that the target group exists
    push(@target_groups, $tg) if defined $tg->{tg};
  }
  return \@target_groups;
}

sub create_target_groups {
  my ($self, @targets) = @_;

  @targets = @{$self->spec->ecs->{service}->{loadBalancers}} unless @targets;
  my @created = $self->_work_target_groups('create', \@targets);

  say "Successfully created " . (scalar @created) . " target group(s).";

  return @created;
}

sub tag_target_groups {
  my ($self, %params) = @_;

  my $targets = $params{targets} // $self->spec->ecs->{service}->{loadBalancers};
  my $tags = $params{tags};

  my @tagged = $self->_work_target_groups('tag', $targets, $tags);

  say "Successfully tagged " . (scalar @tagged) . " target group(s).";

  return @tagged;
}

sub delete_target_groups {
  my ($self, @targets) = @_;
  my @deleted = $self->_work_target_groups('delete', \@targets);

  say "Successfully deleted " . (scalar @deleted) . " target group(s).";

  return @deleted;
}

sub delete_target_groups_with_spec {
  my ($self) = @_;
  # get target groups from spec
  my $targets = $self->spec->elb->{targetGroups};
  my @targets = map { $_->{name} } @$targets;
  # aws cli will throw an error if no target groups are found - all current active target groups should be validated in the execution spec
  my @target_groups = (); 
  for(@targets){
    my $tg = Mast::AWS::ELB::TargetGroup->new(
      aws_region => $self->aws_region,
      name => $_,
      aws => $self->aws,
    );
    my $tg_data = $tg->describe;
    push(@target_groups, $tg_data) if defined $tg_data;
  }
  cluck "number of target groups found is less than the number of target groups in the service spec. something might have drifted or another deployment has started deleting your target groups."
    unless scalar(@targets) == scalar(@target_groups);
  my @deleted = $self->_work_target_groups('delete', \@target_groups);
  say "Successfully deleted " . (scalar @deleted) . " target group(s).";
  return @deleted;
}

sub _work_target_groups {
  my ($self, $operation, $targets, @args) = @_;

  my $spec = $self->spec;
  my $ecs = $spec->ecs;
  my $service = $ecs->{service};

  say "Working on " . (scalar @$targets) . " load balancer target(s) for ECS service $service->{name}";

  my @modified = ();

  for my $item (@$targets) {
    my @result = $operation eq 'create' ? $self->_create_target_group($item, @args)
               : $operation eq 'delete' ? $self->_delete_target_group($item, @args)
               : $operation eq 'tag'    ? $self->_tag_target_group($item, @args)
               :                          confess "Unknown operation: $operation"
               ;
    push @modified, @result;
  }

  return @modified;
}

sub _resolve_target_group {
  my ($self, $item) = @_;

  if ($item->{TargetGroupArn}) {
    return Mast::AWS::ELB::TargetGroup->new(
      aws_region => $self->aws_region,
      target_group => $item,
      aws => $self->aws,
    );
  }

  my $tg_name = $item->{targetGroup}->{name};
  my $lb_name = $item->{loadBalancerName};
  my $tg_rec = $self->spec->find_elb_target_group(name => $tg_name);
  
  die "Cannot find relevant ELB configuration for service specified target group $tg_name!"
      unless $tg_rec;
  
  say "Validating parameters for target group $tg_name...";
  
  Mast::AWS::ELB::TargetGroup->new(
      aws_region => $self->aws_region,
      lb_name => $item->{loadBalancerName},
      aws => $self->aws,
      %$tg_rec,
  );
}

sub _create_target_group {
  my ($self, $lb_rec) = @_;

  my ($tg_name, $allow_existing) = @{$lb_rec->{targetGroup}}{'name', 'allowExisting'};
  my $tg = $self->_resolve_target_group($lb_rec);
  
  say "Checking if target group $tg_name already exists...";
  
  my $existing = $tg->describe;

  die "Found already existing target group $tg_name, service spec does not allow existing target groups.\n"
     if $existing and not $allow_existing;

  if ($existing) {
      say "Found already existing target group with ARN $existing->{TargetGroupArn}";

      return ();
  }
  else {
      say "Creating target group $tg_name...";
  
      # Not catching exceptions here so that the script would stop if something goes wrong
      $tg->create;
  }
}

sub _tag_target_group {
  my ($self, $item, $tags) = @_;

  my $tg = $self->_resolve_target_group($item);

  say "Checking if target group $tg->{name} already exists...";

  my $existing = $tg->describe;

  confess "Could not find existing target group with name $tg->{name}"
    unless $existing;
  
  say "Tagging target group $tg->{name} as active...";

  $tg->tag(%$tags);

  return $tg;
}

sub _delete_target_group {
  my ($self, $item) = @_;

  my $tg = $self->_resolve_target_group($item);

  say "Checking if target group $tg->{name} already exists...";

  my $existing = $tg->describe;

  if (not $existing) {
    say "Could not find existing target group with name $tg->{name}, nothing to do.";

    return ();
  }
  else {
    say "Deleting target group $tg->{name}...";

    $tg->remove;

    return $tg->{name};
  }
}

1;
