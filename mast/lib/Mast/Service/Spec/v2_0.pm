package Mast::Service::Spec::v2_0;

use v5.030;
use strictures 2;
no warnings 'uninitialized';

use parent 'Mast::Service::Spec::v1_2';

use Carp 'confess';
use Data::Dumper;
our @VERSION = (2.0, '2.0');

sub _normalize_elb_load_balancers {
  my ($self, $elb) = @_;

  confess "elb.loadBalancer is not supported in >v2.0"
    if exists $elb->{loadBalancer};
  
  my $lbs = $elb->{loadBalancers};

  confess "Missing elb.loadBalancers configuration in elb section" unless defined $lbs;
  confess "elb.loadBalancers is not an array" unless 'ARRAY' eq ref $lbs;
    
  for my $lb (@$lbs) {
    confess "elb.loadBalancers.[*].listener is not supported in >v2.0"
        if exists $lb->{listener};

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

  if ($lb->{securityGroups} and not ('ARRAY' eq ref $lb->{securityGroups})) {
    $lb->{securityGroups} = [$lb->{securityGroups}];
  }

  # rename listener to listeners and put in array
  my $listener_exists = $lb->{listener};
  confess "loadBalancers.listener not supported in >=2.x" if defined $listener_exists;

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
  my ($self, $name, $index) = @_;

  eval { $self->SUPER::_validate_aws_elb_name($name) };

  die "elb.loadBalancer[$index] $@\n" if $@;
}

sub _normalize_elb_load_balancer_listener_ruleset {
  my ($self, $listener, $lb) = @_;

  my $ruleset = $listener->{rules};

  if ('ARRAY' ne ref $ruleset) {
    return $self->SUPER::_normalize_elb_load_balancer_listener_ruleset($listener, $lb);
  }

  $self->_normalize_elb_load_balancer_listener_rules('', $ruleset, $lb);
}

1;