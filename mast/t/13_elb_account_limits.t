use v5.030;
use strictures 2;

use Test::More;
use JSON::PP;

use lib 't/lib';
use AWS::MockCLIWrapper;

use Mast::AWS::ELB::AccountLimits;

my $data = join '', <DATA>;

my $aws = AWS::MockCLIWrapper->new(
  aws_region => 'us-east-1',
  actors => {
    elbv2 => {
      'describe-account-limits' => sub { decode_json $data },
    },
  },
);

my $acc_limits = eval { Mast::AWS::ELB::AccountLimits->new(aws => $aws) };

is "$@", "", "new no exception";

my $target_groups = eval { $acc_limits->limit('target-groups') };

is "$@", "", "limits no exception";
is $target_groups, 3000, "limits value";

done_testing;

__DATA__
{
  "Limits": [
    {
      "Name": "target-groups",
      "Max": "3000"
    },
    {
      "Name": "targets-per-application-load-balancer",
      "Max": "1000"
    },
    {
      "Name": "listeners-per-application-load-balancer",
      "Max": "50"
    },
    {
      "Name": "rules-per-application-load-balancer",
      "Max": "200"
    },
    {
      "Name": "network-load-balancers",
      "Max": "50"
    },
    {
      "Name": "targets-per-network-load-balancer",
      "Max": "3000"
    },
    {
      "Name": "targets-per-availability-zone-per-network-load-balancer",
      "Max": "500"
    },
    {
      "Name": "listeners-per-network-load-balancer",
      "Max": "50"
    },
    {
      "Name": "condition-values-per-alb-rule",
      "Max": "5"
    },
    {
      "Name": "condition-wildcards-per-alb-rule",
      "Max": "5"
    },
    {
      "Name": "target-groups-per-application-load-balancer",
      "Max": "100"
    },
    {
      "Name": "target-groups-per-action-on-application-load-balancer",
      "Max": "5"
    },
    {
      "Name": "target-groups-per-action-on-network-load-balancer",
      "Max": "1"
    },
    {
      "Name": "certificates-per-application-load-balancer",
      "Max": "25"
    },
    {
      "Name": "certificates-per-network-load-balancer",
      "Max": "25"
    },
    {
      "Name": "targets-per-target-group",
      "Max": "1000"
    },
    {
      "Name": "target-id-registrations-per-application-load-balancer",
      "Max": "1000"
    },
    {
      "Name": "network-load-balancer-enis-per-vpc",
      "Max": "1200"
    },
    {
      "Name": "application-load-balancers",
      "Max": "160"
    },
    {
      "Name": "gateway-load-balancers",
      "Max": "100"
    },
    {
      "Name": "gateway-load-balancers-per-vpc",
      "Max": "100"
    },
    {
      "Name": "geneve-target-groups",
      "Max": "100"
    },
    {
      "Name": "targets-per-availability-zone-per-gateway-load-balancer",
      "Max": "300"
    }
  ]
}
