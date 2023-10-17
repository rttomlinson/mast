use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Test::More;
use Test::Exception;

use Data::Dumper;
use File::Slurp;

use JSON::PP;

use Mast::Cloud::Spec;
use Mast::Deploy::Listeners;
use Mast::Deploy::TargetGroups;
use Mast::Cloud::Spec 'collapser';

use lib 't/lib';
use AWS::MockCLIWrapper;

# Need to test value validation test for different envs
my $cloud_spec_json = read_file "t/data/spec/elb/valid-elb-network-ecs.json";
my $contexts = ["prestaging", "standby"];
my $cloud_spec_obj = Mast::Cloud::Spec->new(contexts => $contexts, cloud_spec_json => $cloud_spec_json);

my $aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    mock_aws_state => {
        load_balancers => {
           LoadBalancers => [
            {
                Type => "network",
                Scheme => "internet-facing",
                IpAddressType => "ipv4",
                VpcId => "vpc-3ac0fb5f",
                AvailabilityZones => [
                    {
                        ZoneName => "us-west-2a",
                        SubnetId => "subnet-8360a9e7"
                    },
                    {
                        ZoneName => "us-west-2b",
                        SubnetId => "subnet-b7d581c0"
                    }
                ],
                CreatedTime => "2016-03-25T21:26:12.920Z",
                CanonicalHostedZoneId => "Z2P70J7EXAMPLE",
                DNSName => "my-load-balancer-424835706.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "sdm-gw1-admin-nlb",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/network/sdm-gw1-admin-nlb/50dc6c495c0c9188"
            }, {
                Type => "application",
                Scheme => "internet-facing",
                IpAddressType => "ipv4",
                VpcId => "vpc-3ac0fb5f",
                AvailabilityZones => [
                    {
                        ZoneName => "us-west-2a",
                        SubnetId => "subnet-8360a9e7"
                    },
                    {
                        ZoneName => "us-west-2b",
                        SubnetId => "subnet-b7d581c0"
                    }
                ],
                CreatedTime => "2016-03-25T21:26:12.920Z",
                CanonicalHostedZoneId => "Z2P70J7EXAMPLE",
                DNSName => "my-load-balancer-424835706.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "cluster-lb-int-prestaging",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/cluster-lb-int-prestaging/50dc6c495c0c9188"
            }
        ]},
    }
);
# create the target group
my $tgs = Mast::Deploy::TargetGroups->new(
    aws => $aws,
    cloud_spec => $cloud_spec_obj,
);
$tgs->create_target_groups;

my $listeners = Mast::Deploy::Listeners->new(
    aws => $aws,
    cloud_spec => $cloud_spec_obj,
);

is $listeners->isa("Mast::Deploy::Listeners"), 1, "is the expected object";

$listeners->update_listeners;

my $lb_specs = $cloud_spec_obj->elb->{loadBalancers};

my $lbs = $listeners->lbs($lb_specs);
for my $lb (@$lbs) {
    my $expect_listeners = $lb->listeners;
        for my $expect_listener (@$expect_listeners) {
            ok $expect_listener->describe, "first update_listeners - expected non-error";
        }
}

# expect error for versions less than 2.0 and nlb
throws_ok {$listeners->update_listeners} qr/^(Trying to modify existing listener with arn:)(.*)(but allowExisting on the listener_spec not set to true. Aborting.)/, "expect upserting nlbs in spec version <2.0 to fail";


$lb_specs = $cloud_spec_obj->elb->{loadBalancers};

$lbs = $listeners->lbs($lb_specs);
for my $lb (@$lbs) {
    my $expect_listeners = $lb->listeners;
        for my $expect_listener (@$expect_listeners) {
            ok $expect_listener->describe, "second update_listener (fails) - expected non-error";
        }
}

$listeners->delete_listeners;
$lb_specs = $cloud_spec_obj->elb->{loadBalancers};

$lbs = $listeners->lbs($lb_specs);
for my $lb (@$lbs) {
    my $expect_listeners = $lb->listeners;
        for my $expect_listener (@$expect_listeners) {
            throws_ok {$expect_listener->describe} qr/Cannot find $expect_listener->{protocol} listener at port $expect_listener->{port} for load balancer/, "delete_listeners - expected non-error";
        }
}


#############################

# multi-nlb listeners test
$cloud_spec_json = read_file "t/data/spec/elb/multi-elb-network-v2_0.json";
my @contexts = ("prestaging");
$cloud_spec_obj = Mast::Cloud::Spec->new(contexts => \@contexts, cloud_spec_json => $cloud_spec_json);

$aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    mock_aws_state => {
        load_balancers => {
           LoadBalancers => [
            {
                Type => "network",
                Scheme => "internet-facing",
                IpAddressType => "ipv4",
                VpcId => "vpc-3ac0fb5f",
                AvailabilityZones => [
                    {
                        ZoneName => "us-west-2a",
                        SubnetId => "subnet-8360a9e7"
                    },
                    {
                        ZoneName => "us-west-2b",
                        SubnetId => "subnet-b7d581c0"
                    }
                ],
                CreatedTime => "2016-03-25T21:26:12.920Z",
                CanonicalHostedZoneId => "Z2P70J7EXAMPLE",
                DNSName => "my-load-balancer-424835706.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "sdm-gw1-admin-nlb",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/network/sdm-gw1-admin-nlb/50dc6c495c0c9188"
            },{
                Type => "network",
                Scheme => "internet-facing",
                IpAddressType => "ipv4",
                VpcId => "vpc-3ac0fb5f",
                AvailabilityZones => [
                    {
                        ZoneName => "us-west-2a",
                        SubnetId => "subnet-8360a9e7"
                    },
                    {
                        ZoneName => "us-west-2b",
                        SubnetId => "subnet-b7d581c0"
                    }
                ],
                CreatedTime => "2016-03-25T21:26:12.920Z",
                CanonicalHostedZoneId => "Z2P70J7EXAMPLE",
                DNSName => "my-load-balancer2-424835706.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "sdm-gw2-admin-nlb",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/network/sdm-gw2-admin-nlb/50dc6c495c0c9188"
            }, {
                Type => "application",
                Scheme => "internet-facing",
                IpAddressType => "ipv4",
                VpcId => "vpc-3ac0fb5f",
                AvailabilityZones => [
                    {
                        ZoneName => "us-west-2a",
                        SubnetId => "subnet-8360a9e7"
                    },
                    {
                        ZoneName => "us-west-2b",
                        SubnetId => "subnet-b7d581c0"
                    }
                ],
                CreatedTime => "2016-03-25T21:26:12.920Z",
                CanonicalHostedZoneId => "Z2P70J7EXAMPLE",
                DNSName => "my-load-balancer-424835706.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "cluster-lb-int-prestaging",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/cluster-lb-int-prestaging/50dc6c495c0c9188"
            },
            {
                Type => "application",
                Scheme => "internet-facing",
                IpAddressType => "ipv4",
                VpcId => "vpc-3ac0fb5f",
                AvailabilityZones => [
                    {
                        ZoneName => "us-west-2a",
                        SubnetId => "subnet-8360a9e7"
                    },
                    {
                        ZoneName => "us-west-2b",
                        SubnetId => "subnet-b7d581c0"
                    }
                ],
                CreatedTime => "2016-03-25T21:26:12.920Z",
                CanonicalHostedZoneId => "Z2P70J7EXAMPLE",
                DNSName => "cluster-lb-int-stg-another.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "cluster-lb-int-stg-another",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/cluster-lb-int-stg-another/50dc6c495c0c9188"
            },
            {
                Type => "application",
                Scheme => "internet-facing",
                IpAddressType => "ipv4",
                VpcId => "vpc-3ac0fb5f",
                AvailabilityZones => [
                    {
                        ZoneName => "us-west-2a",
                        SubnetId => "subnet-8360a9e7"
                    },
                    {
                        ZoneName => "us-west-2b",
                        SubnetId => "subnet-b7d581c0"
                    }
                ],
                CreatedTime => "2016-03-25T21:26:12.920Z",
                CanonicalHostedZoneId => "Z2P70J7EXAMPLE",
                DNSName => "cluster-lb-int-staging.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "cluster-lb-int-staging",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/cluster-lb-int-staging/50dc6c495c0c9188"
            }
        ]},
    }
);

$tgs = Mast::Deploy::TargetGroups->new(
    aws => $aws,
    cloud_spec => $cloud_spec_obj,
);
$tgs->create_target_groups;

$listeners = Mast::Deploy::Listeners->new(
    aws => $aws,
    cloud_spec => $cloud_spec_obj,
);

is $listeners->isa("Mast::Deploy::Listeners"), 1, "is the expected object";

$listeners->update_listeners;

$lb_specs = $cloud_spec_obj->elb->{loadBalancers};

$lbs = $listeners->lbs($lb_specs);
for my $lb (@$lbs) {
    my $expect_listeners = $lb->listeners;
        for my $expect_listener (@$expect_listeners) {
            ok $expect_listener->describe, "multi-nlb, first update_listeners - expected non-error";
        }
}

$listeners->update_listeners;
$lb_specs = $cloud_spec_obj->elb->{loadBalancers};

$lbs = $listeners->lbs($lb_specs);
for my $lb (@$lbs) {
    my $expect_listeners = $lb->listeners;
        for my $expect_listener (@$expect_listeners) {
            ok $expect_listener->describe, "expected non-error";
        }
}

$listeners->delete_listeners;
$lb_specs = $cloud_spec_obj->elb->{loadBalancers};

$lbs = $listeners->lbs($lb_specs);
for my $lb (@$lbs) {
    my $expect_listeners = $lb->listeners;
        for my $expect_listener (@$expect_listeners) {
            throws_ok {$expect_listener->describe} qr/Cannot find $expect_listener->{protocol} listener at port $expect_listener->{port} for load balancer/, "expected non-error";
        }
}

# expect error thrown when trying to update_listeners but allowExisting is not set
# This is part of the test above since it uses the same aws "state"
# multi-nlb listeners test
say "check that allowExisting on listeners required for version >=2.0";
$cloud_spec_json = read_file "t/data/spec/elb/multi-elb-network-v1_0_no_allowExistingOnListeners.json";
$cloud_spec_obj = Mast::Cloud::Spec->new(contexts => \@contexts, cloud_spec_json => $cloud_spec_json);
$listeners = Mast::Deploy::Listeners->new(
    aws => $aws,
    cloud_spec => $cloud_spec_obj,
);
$listeners->update_listeners;
throws_ok {$listeners->update_listeners} qr/^(Trying to modify existing listener with arn:)(.*)(but allowExisting on the listener_spec not set to true. Aborting.)/, "expect upserting nlbs in spec version <2.0 to fail";

#########################################
# Test ALB function limitations
$cloud_spec_json = read_file "t/data/spec/bar-baz-v1_0_diff-albs-multi-tg.json";
@contexts = ("staging", "active");
$cloud_spec_obj = Mast::Cloud::Spec->new(environment => undef, cloud_spec_json => $cloud_spec_json, contexts => \@contexts);
say "Create Listeners object";
my $lr = Mast::Deploy::Listeners->new(
    cloud_spec => $cloud_spec_obj,
    aws => $aws,
    aws_region => "us-east-1",
);

is $lr->isa("Mast::Deploy::Listeners"), 1, "is the expected object";
throws_ok { $lr->update_listeners } qr/update_listeners on a list containing non-network type elbs not supported at this time/, "expect failure when trying to modify listeners on application load balancer";
throws_ok { $lr->delete_listeners } qr/delete_listeners on a list containing non-network type elbs not supported at this time/, "expect failure when trying to delete listeners on application load balancer";

done_testing();

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