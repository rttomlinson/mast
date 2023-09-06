use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Test::More;
use Test::Exception;

use Data::Dumper;
use File::Slurp;

use JSON::PP;

use Mast::Service::Spec;
use Mast::Deploy::ListenerRules;

use lib 't/lib';
use AWS::MockCLIWrapper;

my $account_limits = join '', <DATA>;

# Need to test value validation test for different envs
my $service_spec_json = read_file "t/data/spec/test-baseline-valid-template.json";
my $env = "prestaging";
my $service_spec_obj = Mast::Service::Spec->new(environment => $env, service_spec_json => $service_spec_json);

# override describe-target-groups to just pretend that one already exists

my $aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    service_actors_override => {
        elbv2 => {
          'describe-account-limits' => sub { decode_json $account_limits },
        }
    },
    mock_aws_state => {
        target_groups => {
            TargetGroups => [
                {
                    TargetGroupArn => "aws:us-east-1:123456:tg-placeholder",
                    TargetGroupName => "tg-placeholder",
                },
            ]
        },
        listeners => {
            Listeners => [{
                ListenerArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:listener/gwy/example-lb-int-prestag/e0f9b3d5c7f7d3d6/afc127db15f925de",
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/example-lb-int-prestag/50dc6c495c0c9188",
                Port => 443,
                Protocol => "HTTPS",
                DefaultActions => [{
                    Type => "forward",
                    TargetGroupArn => "aws:us-east-1:123456:tg-placeholderasdfasdfasdf",
                    ForwardConfig => {
                        TargetGroups => [{
                            TargetGroupArn => "aws:us-east-1:123456:tg-placeholderasdfasdfasdf"
                        }]
                    },
                }],
            }],
        },
        listener_rules => {
            Rules => [
                {
                    ListenerArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:listener/gwy/example-lb-int-prestag/e0f9b3d5c7f7d3d6/afc127db15f925de",
                    RuleArn => "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/staging-alb-internal-facing/f6db2a6e4a02bf02/2a9f292b7a7fd6be/0d1206fc211a1095",
                    Priority => "120",
                    Conditions => [
                        {
                            Field => "host-header",
                            Values => [
                              "example.prestaging.foo.io"
                            ],
                            HostHeaderConfig => {
                              Values => [
                                "example.prestaging.foo.io"
                              ]
                            }
                        }
                    ],
                    Actions => [
                        {
                            Type => "forward",
                            TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/app-builder-staging/24214340d928f883",
                            Order => 1,
                            ForwardConfig => {
                                TargetGroups => [
                                    {
                                        TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/app-builder-staging/24214340d928f883",
                                        Weight => 1
                                    }
                                ],
                                TargetGroupStickinessConfig => {
                                    Enabled => JSON::false
                                }
                            }
                        }
                    ],
                    IsDefault => JSON::false
                }
            ]
        },
        load_balancers => {
           LoadBalancers => [
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
                DNSName => "my-load-balancer-424835706.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "example-lb-int-prestag",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/example-lb-int-prestag/50dc6c495c0c9188"
            }],
        }
    }
);
# unsure how to mock specific function calls one-time. seems like advanced functionality. could just create multiple instances of MockCLIWrapper;
my $lr = Mast::Deploy::ListenerRules->new(
    service_spec => $service_spec_obj,
    aws => $aws
);

is $lr->isa("Mast::Deploy::ListenerRules"), 1, "is the expected object";

my $num_modified = $lr->update_listener_rules("active");
is $num_modified == 1, 1, "expect 1 listener rule to be modified. found $num_modified";
my $num_deleted = $lr->delete_listener_rules("active");
is $num_deleted == 1, 1, "expect 1 listener rule to be deleted. found $num_deleted";

# testing for v2.0
$aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    service_actors_override => {
        elbv2 => {
            'describe-account-limits' => sub { decode_json $account_limits },
        }
    },
    mock_aws_state => {
        target_groups => {
            TargetGroups => [{
                TargetGroupArn => "aws:us-east-1:123456:clr-foo-pres-master-foobaroo",
                TargetGroupName => "clr-foo-pres-master-foobaroo",
            },
            {
                TargetGroupArn => "aws:us-east-1:123456:clr-foo-pres-master-another",
                TargetGroupName => "clr-foo-pres-master-another",
            }]
        },
        listeners => {
            Listeners => [{
                ListenerArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:listener/gwy/cluster-lb-int-prestaging/e0f9b3d5c7f7d3d6/afc127db15f925de",
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/cluster-lb-int-prestaging/50dc6c495c0c9188",
                Port => 443,
                Protocol => "HTTPS",
                DefaultActions => [{
                    Type => "forward",
                    TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/test-tg-agw-2/007ca469fae3bb1615",
                    ForwardConfig => {
                        TargetGroups => [{
                            TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/test-tg-agw-2/007ca469fae3bb1615"
                        }]
                    },
                }],
            },{
                ListenerArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:listener/gwy/cluster-lb-int-psg-another/e0f9b3d5c7f7d3d6/afc127db15f925de",
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/cluster-lb-int-psg-another/50dc6c495c0c9188",
                Port => 443,
                Protocol => "HTTPS",
                DefaultActions => [{
                    Type => "forward",
                    TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/test-tg-agw-2/007ca469fae3bb1615",
                    ForwardConfig => {
                        TargetGroups => [{
                            TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/test-tg-agw-3/007ca469fae3bb1615"
                        }]
                    },
                }],
            }]
        },
        load_balancers => {
           LoadBalancers => [
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
                DNSName => "my-load-balancer-424835706.us-west-2.elb.amazonaws.com",
                SecurityGroups => [
                    "sg-5943793c"
                ],
                LoadBalancerName => "cluster-lb-int-psg-another",
                State => {
                    Code => "active"
                },
                LoadBalancerArn => "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/cluster-lb-int-psg-another/50dc6c495c0c9188"
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
        listener_rules => {
            Rules => [
                {
                    ListenerArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:listener/app/staging-alb-internal-facing/f6db2a6e4a02bf02/2a9f292b7a7fd6be",
                    RuleArn => "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/staging-alb-internal-facing/f6db2a6e4a02bf02/2a9f292b7a7fd6be/0d1206fc211a1095",
                    Priority => "120",
                    Conditions => [
                        {
                            Field => "host-header",
                            Values => [
                                "admin.staging.foo.com",
                                "admin-staging.foo.com"
                            ],
                            HostHeaderConfig => {
                                Values => [
                                    "admin.staging.foo.com",
                                    "admin-staging.foo.com"
                                ]
                            }
                        }
                    ],
                    Actions => [
                        {
                            Type => "forward",
                            TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/app-builder-staging/24214340d928f883",
                            Order => 1,
                            ForwardConfig => {
                                TargetGroups => [
                                    {
                                        TargetGroupArn => "arn:aws:elasticloadbalancing:us-east-1:12345678901:targetgroup/app-builder-staging/24214340d928f883",
                                        Weight => 1
                                    }
                                ],
                                TargetGroupStickinessConfig => {
                                    Enabled => JSON::false
                                }
                            }
                        }
                    ],
                    IsDefault => JSON::false
                }
            ]
        }
    }
);
say "starting tests for v2.0";
say "diff albs multi tg";
# allow multiple application lb listener rules
$service_spec_json = read_file "t/data/spec/bar-baz-v2_0_diff-albs-multi-tg.json";
my @contexts = ("prestaging", "active");
$service_spec_obj = Mast::Service::Spec->new(environment => undef, service_spec_json => $service_spec_json, contexts => \@contexts);
say "Create ListenerRules object";
$lr = Mast::Deploy::ListenerRules->new(
    service_spec => $service_spec_obj,
    aws => $aws,
    aws_region => "us-east-1",
);

is $lr->isa("Mast::Deploy::ListenerRules"), 1, "is the expected object";

$lr->update_listener_rules;
my $lb_specs = $service_spec_obj->elb->{loadBalancers};
my @lbs = map {
    Mast::AWS::ELB::LoadBalancer->new(
      aws => $aws,
      %$_,
    );
} @{$lb_specs};
# check that listener rules exist on respective lbs
# expect to find rules on the lbs
is scalar(@lbs), 2, "expected two lbs to be return";


my %lb_rules = ();
for my $lb_spec (@{$service_spec_obj->elb->{loadBalancers}}) {
    $lb_rules{$lb_spec->{name}} = $lb_spec->{listeners};
}

for my $lb (@lbs) {

    is exists($lb_rules{$lb->{name}}), 1, "expect lb from spec to be returned as valid";

    my $target_group_name = $lb_rules{$lb->{name}}->[0]->{rules}->[0]->{action}->{targetGroupName};
    
    my $listener = $lb->listeners;
    for my $listener (@$listener) {
      my $rules = $listener->rules;
      for my $rule (@$rules) {
        my $returned_target_group_arn = $rule->target_group_name // "bogusplaceholder";
        is $returned_target_group_arn =~ /$target_group_name/, 1, "target group expected in updated rules";
      }
    }
}

$lr->delete_listener_rules;
@lbs = map {
    Mast::AWS::ELB::LoadBalancer->new(
      aws => $aws,
      %$_,
    );
} @{$lb_specs};
foreach (@lbs) {
    is exists($lb_rules{$_->{name}}), 1, "expect lb from spec to be returned as valid";
    my $target_group_name = $lb_rules{$_->{name}}->[0]->{rules}->[0]->{action}->{targetGroupName};

    my $listeners = $_->listeners;

    for my $listener (@$listeners) {
      my $rules = $listener->rules;
      for my $rule (@$rules) {
        is $rule->describe, undef, "expect to not find rule pointing to $target_group_name";
      }
    }
}

# expect errors for listener rules on network load balancer type
say "diff nlb multi tg. expect errors";
$service_spec_json = read_file "t/data/spec/elb/multi-elb-network-v2_0.json";
@contexts = ("prestaging", "active");
$service_spec_obj = Mast::Service::Spec->new(environment => undef, service_spec_json => $service_spec_json, contexts => \@contexts);
say "Create ListenerRules object";
$lr = Mast::Deploy::ListenerRules->new(
    service_spec => $service_spec_obj,
    aws => $aws,
    aws_region => "us-east-1",
);
is $lr->isa("Mast::Deploy::ListenerRules"), 1, "is the expected object";
throws_ok { $lr->update_listener_rules } qr/update_listener_rules on a list containing non-network type elbs not supported at this time./, "expect failure when trying to modify listener rules on network load balancer";
throws_ok { $lr->delete_listener_rules } qr/delete_listener_rules on a list containing non-network type elbs not supported at this time./, "expect failure when trying to modify listener rules on network load balancer";



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