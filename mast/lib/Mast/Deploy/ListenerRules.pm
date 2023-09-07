package Mast::Deploy::ListenerRules;

use v5.030;
use warnings;

no warnings 'uninitialized', 'unopened';

use Carp 'confess';

use parent 'Mast::Deploy::Base';

use Mast::Service::Spec;
use Mast::Service::Spec 'collapser';
use Mast::AWS::ELB::LoadBalancer;
use Mast::AWS::ELB::TargetGroup;

sub update_listener_rules {
  my ($self, $role) = @_;

  my @modified;
  my $lb_specs = $self->spec->elb->{loadBalancers};

  # Carry over from v<2.0
  $lb_specs = collapser([$role], $lb_specs) if defined $role;

  my $lbs = $self->lbs($lb_specs);
  for my $lb (@$lbs) {
    confess "update_listener_rules on a list containing non-network type elbs not supported at this time. You provided $lb->type" unless $lb->type eq 'application';
    my $listeners = $lb->listeners;
    for my $listener (@$listeners) {
      my $rules = $listener->rules;
      my $rule_count = scalar @$rules;

      for my $index (0..$#$rules) {
        my $rule = $rules->[$index];
        my $tg_name = $rule->{rule_spec}->{action}->{targetGroupName};
        my $logging_index = $index + 1;
        say qq|Working on "$role" rule #$logging_index of $rule_count|;

        my $target_group = Mast::AWS::ELB::TargetGroup->new(
          aws_region => $self->aws_region,
          name => $tg_name,
          aws => $self->aws,
        );

        say "Resolving target group...";
        my $tg = $target_group->describe;

        confess "Cannot find target group $tg_name!" unless $tg;

        my $resolved_rule = $rule->resolve_rule;
        my @res;

        if ($resolved_rule) {
          say qq|Updating "$role" rule #$index to forward traffic to target group $tg_name...|;

          @res = $rule->update($target_group);

          say qq|Successfully updated "$role" listener rule #$index.|;
        }
        else {
          say qq|Could not find existing "$role" listener rule, creating a new rule...|;

          @res = $rule->create($target_group);

          say qq|Successfully created new "$role" listener rule forwarding traffic to $tg_name.|;
        }

        push @modified, map {
          +{
            TargetGroupName => $tg_name,
            TargetGroupArn => $tg->{TargetGroupArn},
            RuleArn => $_->{RuleArn},
            LoadBalancerArn => $lb->arn,
            ListenerArn => $listener->arn,
            ListenerRuleConditions => $resolved_rule->{Conditions},
          }
        } @res;
      }
    }
  }
  return @modified;
}

sub delete_listener_rules {
  my ($self, $role) = @_;

  my @deleted;
  my $lb_specs = $self->spec->elb->{loadBalancers};

  # Carry over from v<2.0
  $lb_specs = collapser([$role], $lb_specs) if defined $role;

  my $lbs = $self->lbs($lb_specs);
  for my $lb (@$lbs) {
    confess "delete_listener_rules on a list containing non-network type elbs not supported at this time. You provided $lb->type" unless $lb->type eq 'application';
    my $listeners = $lb->listeners;
    for my $listener (@$listeners) {
      my $rules = $listener->rules;
      my $rule_count = scalar @$rules;

      for my $index (0..$#$rules) {
        my $rule = $rules->[$index];
        my $tg_name = $rule->{rule_spec}->{action}->{targetGroupName};

        my $logging_index = $index + 1;
        say qq|Working on "$role" rule #$logging_index of $rule_count|;

        my $target_group = Mast::AWS::ELB::TargetGroup->new(
          aws_region => $self->aws_region,
          name => $tg_name,
          aws => $self->aws,
        );

        say "Resolving target group...";
        my $tg = $target_group->describe;

        confess "Cannot find target group $tg_name!" unless $tg;

        my $resolved_rule = $rule->resolve_rule;
        my @res;
        if ($resolved_rule) {
          say qq|Deleting "$role" rule #$index of $rule_count..."|;

          $rule->delete;

          push @deleted, { RuleArn => $resolved_rule->{RuleArn} };
        }
      }
    }
  }
  return @deleted;
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
    push(@lbs, ($lb));  
  }
  $self->{_lbs} = \@lbs;
}


1;
