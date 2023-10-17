package Mast::Deploy::Listeners;

use v5.030;
use warnings;

no warnings 'uninitialized', 'unopened';

use Carp 'confess';

use parent 'Mast::Deploy::Base';

use Mast::Cloud::Spec;
use Mast::AWS::ELB::LoadBalancer;
use Mast::AWS::ELB::TargetGroup;

# Upsert listener of network elb type
# 07/28 - require allowExisting if listener is found to already exist
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
      
      # TODO: Can the spec support multiple different types of elbs?
      confess "update_listeners on a list containing non-network type elbs not supported at this time. You provided $lb->type" unless $lb->type eq 'network';
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
        confess "Trying to modify existing listener with arn: $listener_arn, but allowExisting on the listener_spec not set to true. Aborting." unless $listener->{listener_spec}->{allowExisting};
        say "Mast::Deploy::Listeners - Existing listener found for port $port and protocol $protocol. Updating";
        # TODO: ignore keys with nil value
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
  return $num_updated;
}

sub delete_listeners {
  my ($self,) = @_;
  my $lb_specs = $self->spec->elb->{loadBalancers};

  my $lbs = $self->lbs($lb_specs);
  for my $lb (@$lbs) {
    confess "delete_listeners on a list containing non-network type elbs not supported at this time. You provided $lb->type" unless $lb->type eq 'network';
    my $listeners = $lb->listeners;
    for my $listener (@$listeners) {
      $listener->delete;
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