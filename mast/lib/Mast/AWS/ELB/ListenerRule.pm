package Mast::AWS::ELB::ListenerRule;

use v5.030;
use strictures 2;

no warnings 'uninitialized';

use Carp 'confess';
use Clone qw(clone);

use AWS::CLIWrapper;

sub new {
  my ($class, %params) = @_;
  my $aws_region = delete $params{aws_region};

  my $aws = delete $params{aws};
  $aws //= AWS::CLIWrapper->new(
      region => $aws_region,
      croak_on_error => 1,
  );

  my $self = bless { aws => $aws, %params }, $class;

  $self;
}

sub describe {
  my ($self,) = @_;

  return $self->resolve_rule;
}
sub resolve_rule {
  my ($self,) = @_;
  my $rule_spec = $self->{rule_spec};
  my $rules = $self->_get_all_rules;
  my @found_rules
    = grep { _match_rule_conditions->($rule_spec->{conditions}, $_->{Conditions}) }
          @$rules;
  confess "Found more than one existing listener rule matching conditions: " .
    encode_json(_canonicalize_conditions($rule_spec->{conditions}))
      if @found_rules > 1;
  return $found_rules[0];
}

sub target_group_name {
  my ($self) = @_;

  return $self->{rule_spec}->{action}->{targetGroupName};
}

sub _get_all_rules {
  my ($self) = @_;

  my $listener_arn = $self->listener->arn;

  my @rules = do {
    my $res = $self->{aws}->elbv2('describe-rules', {
      'listener-arn' => $listener_arn,
    });

    # Default rule priority has a string value of "default". This is awkward
    # because later on we might need to sort rules by priority, and it is
    # redundant as well since there is an IsDefault property in each rule.
    map { $_->{Priority} = 100_000 if $_->{Priority} eq 'default'; $_ } @{ $res->{Rules} };
  };
  $self->{_cached_rules} = [@rules];
}

# host-header and path-pattern rules can be defined using either a simplified
# config via Values property, or with extended config using specific property.
# AWS API call returns a canonicalized version where both Values and specific
# properties are present. We need to canonicalize inbound rule definitions
# as well as API results for comparative purposes.
my %condition_fields = (
    'host-header' => _canonicalizatoror('HostHeaderConfig'),
    'path-pattern' => _canonicalizatoror('PathPatternConfig'),
    'http-header' => _canonicalizatoror('HttpHeaderConfig', 1),
    'http-request-method' => _canonicalizatoror('HttpRequestMethodConfig', 1),
    'source-ip' => _canonicalizatoror('SourceIpConfig', 1),
    # query-string rules use QueryStringConfig structure that will be sorted
    # during JSON canonicalization
    'query-string' => sub { @_ },
);

sub _canonicalizatoror {
  my ($prop, $simplex) = @_;

  sub {
      my $rule = shift;
      my $r = { %$rule };

      my $values = [sort @{ $r->{$prop} ? $r->{$prop}->{Values} : $r->{Values} }];

      delete $r->{$prop};
      delete $r->{Values};

      $r->{$prop}->{Values} = $values;
      $r->{Values} = $r->{$prop}->{Values} unless $simplex;

      $r;
  };
};

sub _canonicalize_conditions {
  my ($conditions) = @_;

  return [] unless 'ARRAY' eq ref $conditions;

  # This is a trivial version of a Schwartzian transform
  my @canonicalized =
    sort { $a->{Field} cmp $b->{Field} }
    map  { $condition_fields{$_->{Field}}->($_) }
         @$conditions;
  
  return \@canonicalized;
}

sub _match_rule_conditions {
  my ($spec_conditions, $rule_conditions) = @_;

  # In order to resolve the rule specified by a set of conditions, we need to
  # retrieve the full set of rules for a listener and select the one matching
  # the provided condition set. AWS `describe-rules` API call always returns
  # rule conditions in canonical form with expanded specific properties. This
  # form is not 100% congruent with the condition specification form that can be
  # passed to AWS `create-rule` API call. To make things easier, the service spec
  # is following the somewhat simpler `create-rule` format, which means that
  # we need to canonicalize the inbound conditions we take from the service spec
  # in order to be able to compare them against the `describe-rules` form.
  my $canon_spec_cond = _canonicalize_conditions($spec_conditions);
  my $canon_rule_cond = _canonicalize_conditions($rule_conditions);

  # Finally, to avoid complex data structure traversal and comparison, we are
  # taking canonicalized conditions and are encoding them in (again canonicalized)
  # JSON form to perform simple string comparison later. Canonicalized JSON
  # will have the object keys sorted.
  my $spec_cond_json = JSON->new->canonical->encode($canon_spec_cond);
  my $rule_cond_json = JSON->new->canonical->encode($canon_rule_cond);

  return $rule_cond_json eq $spec_cond_json;
}

sub _match_rule_actions {
  my ($spec_actions, $rule_actions) = @_;

  # TODO canonicalize actions similar to conditions. This will do for now.
  return unless @$spec_actions == @$rule_actions;

  for (my $i = 0; $i <= $#{$spec_actions}; $i++) {
    my $spec_action = $spec_actions->[$i];
    my $rule_action = $rule_actions->[$i];

    return unless lc($spec_action->{type}) eq lc($rule_action->{Type});

    if (lc($spec_action->{type}) eq 'forward') {
      my $spec_tg_name = $spec_action->{targetGroupName};
      my $rule_tg_arn = $rule_action->{TargetGroupArn};

      return unless $rule_tg_arn =~ /$spec_tg_name/;
    }
    else {
      # Later
      return;
    }
  }

  return 1;
}

sub create {
  my ($self, $target_group) = @_;
  my $rule_spec = $self->{rule_spec};
  my ($placement, $conditions) = @$rule_spec{'placement', 'conditions'};

  my $rules = $self->_get_all_rules;

  # First we need to determine new rule's priority. ALB listeners support up to 200 rules,
  # and rule priority matters: most specific rules should ideally come before the default,
  # which can be assigned priority level 100.
  # Determining actual priority placement is a non-trivial task so we take it as an input,
  # and simply trying to find the first unused priority from either start or end.
  my @sorted_rules = sort { $a->{Priority} <=> $b->{Priority} } @$rules;
  my %used_priorities = map { $_->{Priority} => 1 } @sorted_rules;

  my $new_priority;
  my $acc_limits = Mast::AWS::ELB::AccountLimits->new(aws => $self->{aws});
  my $max_rules = $acc_limits->limit('rules-per-application-load-balancer');

  if ($placement eq "start") {
    # Yes, listener priorities are 1-based
    for (my $i = 1; $i < $max_rules + 1; $i++) {
      if (not exists $used_priorities{$i}) {
        $new_priority = $i;
        last;
      }
    }
  }
  else {
    for (my $i = $max_rules; $i > 0; $i--) {
      if (not exists $used_priorities{$i}) {
        $new_priority = $i;
        last;
      }
    }
  }

  confess 'Cannot find unused priority for the new listener rule!'
    unless defined $new_priority;

  my $new_rule = do {
    my $res = $self->{aws}->elbv2('create-rule', {
        'listener-arn' => $self->listener_arn,
        priority => $new_priority,
        conditions => $conditions,
        actions => [{
          Type => 'forward',
          TargetGroupArn => $target_group->describe->{TargetGroupArn},
        }],
    });

    $res->{Rules}->[0];
  };

  # Invalidate rule cache
  undef $self->{_cached_rules};

  $new_rule;
}

sub update {
  my ($self, $target_group) = @_;
  my $rule_arn = $self->arn;
  my $updated = do {
    my $res = $self->{aws}->elbv2('modify-rule', {
      'rule-arn' => $rule_arn,
      actions => [{
        Type => 'forward',
        TargetGroupArn => $target_group->describe->{TargetGroupArn},
      }]}
    );

    $res->{Rules}->[0];
  };

  # Invalidate rule cache
  undef $self->{_cached_rules};

  $updated;
}

sub delete {
  my ($self,) = @_;

  # No output for this operation, if it doesn't throw then it was successful.
  my $res = $self->{aws}->elbv2(
    'delete-rule', 
    {
      'rule-arn' => $self->arn,
    }
  );

  # Invalidate rule cache
  undef $self->{_cached_rules};

  return 1;
}

sub listener {
  my ($self,) = @_;

  return $self->{listener};
}

sub listener_arn {
  my ($self,) = @_;

  return $self->{listener}->arn;
}

sub arn {
  my ($self) = @_;

  $self->describe->{RuleArn};
}

1;