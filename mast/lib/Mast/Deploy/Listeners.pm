package Mast::Deploy::Listeners;

use v5.030;
use warnings;

no warnings 'uninitialized', 'unopened';

use Carp 'confess';

use parent 'Mast::Deploy::Base';

use Mast::Cloud::Spec;
use Mast::AWS::ELB::LoadBalancer;
use Mast::AWS::ELB::TargetGroup;

# Upsert listener of elb application and network types
# 10/17 allowExisting is the default
sub update_listeners {
  my ($self,) = @_;

  my $num_updated = 0;
  my $lb_specs = $self->spec->elb->{loadBalancers};

  my $lbs = $self->lbs($lb_specs);
  for my $lb (@$lbs) {
    my $listeners = $lb->listeners;

    for my $listener (@$listeners) {
      my $port = $listener->port;
      my $protocol = $listener->protocol;
      
      if($lb->type eq 'application'){

        # check for certificate changes
        # check if listener can exist
        # check if listener already exists
        # if listener already exists, then update
        # if listener doesn't exist and allowExisting is not set to false
        # then create the listener
        my $target_group_arn;
        if (defined $listener->{listener_spec}->{action}->{targetGroupName}) {
          my $tg_name = $listener->{listener_spec}->{action}->{targetGroupName};
          my $target_group = Mast::AWS::ELB::TargetGroup->new(
            aws_region => $self->aws_region,
            name => $tg_name,
            aws => $self->aws,
          );
          say "Resolving target group...";
          my $tg = $target_group->describe;
          $target_group_arn = $tg->{TargetGroupArn};

          confess "Cannot find target group $tg_name!" unless $tg;
        }

        my $res;

        my $listener_exists;
        eval {
          $listener_exists = $listener->describe;
        } or do {
          if($@ =~ /Cannot find/){
            say $@;
            say "Continuing";
          } else {
            confess "$@";
          }
        };

        if($listener_exists) {
          my $listener_arn = $listener->arn;
          # only if allowExisting is explicitly set to false
          if(defined $listener->{listener_spec}->{allowExisting} && $listener->{listener_spec}->{allowExisting} == JSON::PP::false){
            confess "Trying to modify existing listener with arn: $listener_arn, but allowExisting on the listener_spec set to false. Aborting." ;
          }

          say "Mast::Deploy::Listeners - Existing listener found for port $port and protocol $protocol. Updating";
          # $res = $listener->modify(target_group_arn => $target_group_arn);
          $res = $listener->modify();
          $num_updated++;
          say qq|Successfully updated existing listener.|;
        } else {
            say "Listener for port $port and protocol $protocol not found. Creating new";
            # $res = $listener->create(target_group_arn => $target_group_arn);
            $res = $listener->create();
            $num_updated++;
            say qq|Successfully created new listener.|;
        }

      } elsif($lb->type eq 'network') {
        # TODO: ignore keys with nil value
        my $target_group_arn;
        if (defined $listener->{listener_spec}->{action}->{targetGroupName}) {
          my $tg_name = $listener->{listener_spec}->{action}->{targetGroupName};
          my $target_group = Mast::AWS::ELB::TargetGroup->new(
            aws_region => $self->aws_region,
            name => $tg_name,
            aws => $self->aws,
          );
          say "Resolving target group...";
          my $tg = $target_group->describe;
          $target_group_arn = $tg->{TargetGroupArn};

          confess "Cannot find target group $tg_name!" unless $tg;
        }

        my $res;

        my $listener_exists;
        eval {
          $listener_exists = $listener->describe;
        } or do {
          if($@ =~ /Cannot find/){
            say $@;
            say "Continuing";
          } else {
            confess "$@";
          }
        };

        if($listener_exists) {
          my $listener_arn = $listener->arn;
          # only if allowExisting is explicitly set to false
          if(defined $listener->{listener_spec}->{allowExisting} && $listener->{listener_spec}->{allowExisting} == JSON::PP::false){
            confess "Trying to modify existing listener with arn: $listener_arn, but allowExisting on the listener_spec set to false. Aborting." ;
          }

          say "Mast::Deploy::Listeners - Existing listener found for port $port and protocol $protocol. Updating";
          $res = $listener->modify(target_group_arn => $target_group_arn);
          $num_updated++;
          say qq|Successfully updated existing listener forwarding traffic to $target_group_arn.|;
        } else {
            say "Listener for port $port and protocol $protocol not found. Creating new";
            $res = $listener->create(target_group_arn => $target_group_arn);
            $num_updated++;
            say qq|Successfully created new listener forwarding traffic to $target_group_arn.|;
        }
      }
    }
  }  
  return $num_updated;
}

# What about dealing with certs?
# Well, since we can have multiple certs, we can just deal with the one's that are relevant to our spec
# Do delete listener is really modify/update unless allowExisting is false

sub delete_listeners {
  my ($self,) = @_;
  my $lb_specs = $self->spec->elb->{loadBalancers};

  my $lbs = $self->lbs($lb_specs);
  for my $lb (@$lbs) {
    my $listeners = $lb->listeners;
    for my $listener (@$listeners) {
      if(defined $listener->{listener_spec}->{allowExisting} && defined $listener->{listener_spec}->{allowExisting} == JSON::PP::false && $listener->arn){
        $listener->delete;
        # delete it
      } elsif($listener->arn) {
        # Just update it to reflect the when removing anything applied from the cloud_spec was applied.
        # This may or may not be the "previous" state
        if($lb->type eq 'application'){
          say "For application elb we're just going to skip delete since we don't have the logic/test for keeping it around";
          # $listener->delete;
        } elsif($lb->type eq 'network') {
            say "For network elb we're just going to delete since we don't have a blackhole target group";
            $listener->delete;
            # We may need a "blackhole" target group here that is meant to be a placeholder
        }
      }
    }
  }
  return undef;
}

sub lbs {
  my ($self, $lb_specs) = @_;

  return $self->{_lbs} if $self->{_lbs};

  my @lbs = ();

  for my $lb_spec (@$lb_specs) {

    my $lb = Mast::AWS::ELB::LoadBalancer->new(
      aws_region => $self->aws_region,
      aws => $self->aws,
      %$lb_spec,
    );
    confess "lb by name $lb_spec->{name} not found. aborting" unless defined $lb->describe; # confirm that lb exists
    push(@lbs, ($lb));  
  }
  $self->{_lbs} = \@lbs;
}

1;