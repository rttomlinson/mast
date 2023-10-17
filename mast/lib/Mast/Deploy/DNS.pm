package Mast::Deploy::DNS;

use v5.030;
use warnings;
no warnings 'uninitialized', 'unopened';

use Carp 'confess';

use JSON::PP;
use Mast::Cloud::Spec;
use Mast::AWS::ECS::Service;
use Mast::Deploy::ListenerRules;
use Mast::AWS::Route53::Zone;
use Mast::AWS::Route53::Record;

use parent 'Mast::Deploy::Base';

sub get_hosted_zones {
    # infer the hosted zone name from listener
    # infer public or private hosted zone from load balancer
    my ($self, $rules, $lb) = @_;
    my @host_header_fqdns = ();
    for my $index (0..$#$rules) {
        my $rule_spec = $rules->[$index];

        
        my %conditions = map { $_->{Field} => $_->{Values} } @{$rule_spec->{conditions}};
        if($conditions{'host-header'}){
            push(@host_header_fqdns, @{$conditions{'host-header'}});
        }
    }
    my %temp_hash   = map { $_, 1 } @host_header_fqdns;
    my @unique_host_header_fqdns = keys %temp_hash;

    # let's just assume one for now
    say "Found one host-header fqdn $unique_host_header_fqdns[0]";
    # get the hosted zone, but first trying the fqdn directly. If this fails, then try popping at the first period and try again. then throw error

    my $hosted_zones = $self->_check_if_hosted_zones_exist($unique_host_header_fqdns[0]);
    if(scalar(@{$hosted_zones}) == 0){
        my ($subdomain, $parent_domain_name) = split(/\./, $unique_host_header_fqdns[0], 2);
        $hosted_zones = $self->_check_if_hosted_zones_exist($parent_domain_name);
    }
    return $hosted_zones;
    
}

# public or private?
sub _check_if_hosted_zones_exist {
    my ($self, $dns_name) = @_;
    say "Looking for hosted zones with $dns_name";
    my $hosted_zones; 
    eval {
        $hosted_zones = do {
            my $res = $self->aws->route53('list-hosted-zones-by-name', { # TODO: Fix
            'dns-name' => $dns_name,
            'max-items' => 2, # 2 is the max that can exist for each dns-name
            });
            $res->{HostedZones};
        };
    };
    if ($@) {
        say "$@";
        say "Failed to describe hosted zones. Need to manually intervene.";
        say "Should we throw an error here?";
        return undef;
    } else {
        my @matching_hosted_zones = ();
        for(@$hosted_zones){
            if($_->{Name} eq "$dns_name."){ # fqdn in route53 will include the trailing period. TODO: Add if not present
                push(@matching_hosted_zones, $_);
            }
        }
        # see if the first two match, and discard the rest
        return \@matching_hosted_zones;
    }
}

sub create_dns_record_based_on_listener_rule_hostname_condition{
    my ($self, $hosted_zones, $rules, $lb) = @_;
    # based on the load balancer, determine if we need a public or private hosted zone
    # Just going to assume private for now
    # try to clean hosted_zone if it has a leading slash
    say $lb->lb_arn;
    my %hash = map { $_->{Config}->{PrivateZone} => $_ } @$hosted_zones;
    my $change_set;
    if(defined $hash{'1'}){
        say "Found a private zone";
        my $hosted_zone_id = $hash{'1'}->{Id};
        if($hosted_zone_id =~ /^\//){
            $hosted_zone_id = substr $hosted_zone_id, 1;
        }
        my ($prefix, $id) = split(/\//, $hosted_zone_id, 2);
        $hosted_zone_id = $id;

        $change_set = do {
            my $change_batch = {
                    Changes => [
                    {
                        'Action' => 'CREATE',
                        'ResourceRecordSet' => {
                            AliasTarget => {
                                DNSName => $lb->lb_arn,
                                EvaluateTargetHealth => JSON::PP::true,
                                HostedZoneId => $hosted_zone_id
                            },
                            Name => $rules->[0]->{conditions}->[0]->{Values}->[0],
                            Type => 'A'
                        }
                    }
                ]};
            
            my $change_resource_record_sets_payload = {
                'HostedZoneId' => $hosted_zone_id,
                'ChangeBatch' => $change_batch,
            };
            # An error occurred (InvalidChangeBatch) when calling the ChangeResourceRecordSets operation: [null]???
            my $res = $self->aws->route53('change-resource-record-sets', {
                'cli-input-json' => encode_json($change_resource_record_sets_payload)
            });
            $res->{Changes};
        };
    } else {
        say "No private zone found."; #TODO: Enhancement logic
    }
}

sub modify_dns_records {
  my ($self, $action) = @_;

  my $route53 = $self->spec->route53;

  $self->modify_dns_record($action, $_) for @$route53;
}

sub create_dns_records { shift->modify_dns_records('create') }
sub delete_dns_records { shift->modify_dns_records('delete') }

sub modify_dns_record {
  my ($self, $action, $record_spec) = @_;

  my $zone = Mast::AWS::Route53::Zone->new(%$record_spec, aws => $self->aws);

  my $record = Mast::AWS::Route53::Record->new(
    %$record_spec,
    zone => $zone,
    aws => $self->aws,
  );

  my $log = $self->log;
  my $fqdn = $record->fqdn;
  my $change;

  if ($action eq 'create') {
    $log->("Creating Route53 DNS record for $fqdn..");

    $change = $record->create;
  }
  elsif ($action eq 'delete') {
    $log->("Checking if there is existing Route53 DNS record for $fqdn..");

    if (not $record->exists) {
      $log->("Route53 DNS record for FQDN $fqdn was not found, nothing to do.");
      return;
    }

    $log->("Deleting Route53 DNS record for $fqdn..");

    $change = $record->remove;
  }

  $log->("Successfully submitted Route53 change with id " . $change->id);

  $self->wait_for_change($change);
}

sub wait_for_change {
  my ($self, $change) = @_;

  my $poll_interval = $self->poll_interval;
  my $change_id = $change->id;

  while (1) {
    my $status = $change->status;

    if ($status eq 'INSYNC') {
      $self->log->("Route53 change $change_id has completed propagation and is in sync.");
      return;
    }

    $self->log->("Route53 change $change_id is in status $status, waiting $poll_interval seconds...");

    sleep $poll_interval;
  }
}

1;
