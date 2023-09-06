use v5.030;
use strictures 2;

use Test::More;
use Mast::Service::Spec::v0;

#cannot be empty string
subtest 'static values test for target_group_names' => sub {
    my $empty_string_validate_target_group_name = eval {
        Mast::Service::Spec::v0::_validate_elb_target_group_name(undef, '');
    };
    is ($@ =~ qr/Target group name is required/, 1, 'target group name cannot be empty string');
    my $undef_empty_string_validate_target_group_name = eval {
        Mast::Service::Spec::v0::_validate_elb_target_group_name(undef);
    };
    is ($@ =~ qr/Target group name is required/, 1, 'target group name cannot be undef');
};

done_testing;
