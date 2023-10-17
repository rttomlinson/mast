use v5.030;
use strictures 2;

use Test::More;
use Mast::Service::Spec::v1_0;
use Test::LectroTest;
use Test::LectroTest::Generator qw(:common :combinators Gen);

my $ten_thousand_runner = new Test::LectroTest::TestRunner(
  trials      => 10_000,
);

# ASCII only
my $nonalphanumeric_target_group_name_gen = String( length=>[1,32], charset=>"\x00-\x2c\x2e-\x2f\x3a-\x40\x5b-\x60\x7b-\x7f");
Property {
    ##[ target_group_name <- $nonalphanumeric_target_group_name_gen ]##
    my $res = eval {Mast::Service::Spec::v1_0::_validate_elb_target_group_name(undef, $target_group_name, 0)};
    if($@){
        # diag $@;
        $@ =~ qr/Invalid target group name/ and $@ =~ qr/only alphanumerics and hyphens are permitted/;
    } else {
        0;
    }
}, name => "Target group can only contain alphanumeric characters and hyphens";

# This name must be unique per region per account, can have a maximum of 32 characters, must contain only alphanumeric characters or hyphens, and must not begin or end with a hyphen.
my $exceed_length_target_group_name_gen = Paste( String( length=>[1,1], charset=>"A-Za-z0-9"), String( length=>[31,100], charset=>"-A-Za-z0-9" ), String( length=>[1,1], charset=>"A-Za-z0-9" ), glue => '');
Property {
    ##[ target_group_name <- $exceed_length_target_group_name_gen ]##
    my $res = eval {Mast::Service::Spec::v1_0::_validate_elb_target_group_name(undef, $target_group_name)};
    if($@){
        # diag $@;
        $@ =~ qr/Target group name length cannot exceed 32 characters/;
    } else {
        0;
    }
}, name => "Target group name length cannot exceed 32 characters" ;

my $hyphen_start_target_group_name_gen = Paste( String( length=>[1,1], charset=>"-"), String( length=>[0,31], charset=>"-A-Za-z0-9" ), glue => '');
my $hyphen_end_target_group_name_gen = Paste( String( length=>[0,31], charset=>"-A-Za-z0-9" ), String( length=>[1,1], charset=>"-" ), glue => '');
my $hyphen_start_and_end_target_group_name_gen = Paste( String( length=>[1,1], charset=>"-"), String( length=>[0,30], charset=>"-A-Za-z0-9" ), String( length=>[1,1], charset=>"-" ), glue => '');
my $hyphen_start_and_or_end_target_group_name_gen = OneOf( $hyphen_start_target_group_name_gen, $hyphen_end_target_group_name_gen, $hyphen_start_and_end_target_group_name_gen );
Property {
    ##[ target_group_name <- $hyphen_start_and_or_end_target_group_name_gen ]##
    my $res = eval {Mast::Service::Spec::v1_0::_validate_elb_target_group_name(undef, $target_group_name)};
    if($@){
        # diag $@;
        $@ =~ qr/Invalid target group name/ and $@ =~ qr/cannot start or end with a hyphen/;
    } else {
        0;
    }
}, name => "Target group name cannot start or end with hyphen";

my $target_group_name_gen = Paste( String( length=>[1,1], charset=>"A-Za-z0-9"), String( length=>[0,30], charset=>"-A-Za-z0-9" ), String( length=>[1,1], charset=>"A-Za-z0-9" ), glue => '');
Property {
    ##[ target_group_name <- $target_group_name_gen ]##
    my $res = eval {Mast::Service::Spec::v1_0::_validate_elb_target_group_name(undef, $target_group_name)};
    1;
}, name => "Target group name passed all valid cases";


