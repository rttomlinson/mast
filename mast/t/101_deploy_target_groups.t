use v5.030;
use strictures 2;
no warnings 'uninitialized';

use Test::More;
use Test::Exception;

use Data::Dumper;
use File::Slurp;

use JSON::PP;

use Mast::Service::Spec;
use Mast::Deploy::TargetGroups;

use lib 't/lib';
use AWS::MockCLIWrapper;

# Need to test value validation test for different envs
my $service_spec_json = read_file "t/data/spec/test-baseline-valid-template.json";
my $contexts = ["prestaging", "standby"];
my $service_spec_obj = Mast::Service::Spec->new(contexts => $contexts, service_spec_json => $service_spec_json);
my $aws = AWS::MockCLIWrapper->new(
    aws_region => 'us-east-1',
    mock_aws_state => {
        target_groups => {
            TargetGroups => [
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
my $tgs = Mast::Deploy::TargetGroups->new(
    service_spec => $service_spec_obj,
    aws => $aws
);

is $tgs->isa("Mast::Deploy::TargetGroups"), 1, "is the expected object";

my $tg_objects = $tgs->get_target_group_objects;
$tgs->create_target_groups;
$tgs->delete_target_groups_with_spec;

done_testing();