use Test::More tests => 21;

use v5.030;
use warnings;

use_ok 'Mast::Service::Spec';
use_ok 'Mast::Service::Spec::v1_0';
use_ok 'Mast::Service::Metadata';
use_ok 'Mast::Service::Verification';

use_ok 'Mast::AWS::Fargate';
use_ok 'Mast::AWS::ApplicationAutoscaling::ScalableTarget';
use_ok 'Mast::AWS::ApplicationAutoscaling::ScalingPolicy';
use_ok 'Mast::AWS::ECS::Service';
use_ok 'Mast::AWS::ECS::Task';
use_ok 'Mast::AWS::ECS::TaskDefinition';
use_ok 'Mast::AWS::ELB::LoadBalancer';
use_ok 'Mast::AWS::ELB::TargetGroup';
use_ok 'Mast::AWS::VPC::SecurityGroup';

use_ok 'Mast::Deploy::DNS';
use_ok 'Mast::Deploy::ExecutionPlan';
use_ok 'Mast::Deploy::ListenerRules';
use_ok 'Mast::Deploy::Listeners';
use_ok 'Mast::Deploy::Service';
use_ok 'Mast::Deploy::Step';
use_ok 'Mast::Deploy::TargetGroups';
use_ok 'Mast::Deploy::TaskDefinition';
