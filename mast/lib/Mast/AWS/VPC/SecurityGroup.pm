package Mast::AWS::VPC::SecurityGroup;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Carp 'confess';
use JSON::PP;
use AWS::CLIWrapper;

# Just used to check if a security group exists or not

sub new {
  my ($class, %params) = @_;

  my $cloud_spec = $params{cloud_spec};

  confess 'Expected Mast::Cloud::Spec object as "cloud_spec" parameter'
    unless $cloud_spec and $cloud_spec->isa('Mast::Cloud::Spec');

  my $aws = AWS::CLIWrapper->new(
    region => $cloud_spec->aws_region,
    croak_on_error => 1,
  );

  bless { aws => $aws, spec => $cloud_spec }, $class;
}

sub describe {
  my ($self, $security_group_id) = @_;

  return $self->{_security_group} if $self->{_security_group};

  my $security_group = eval {
    my $res = $self->{aws}->ec2('describe-security-groups', {
      'group-ids' => [$security_group_id],
    });

    $res->{SecurityGroups}->[0];
  };

  if($@){
    if($@ !~ /InvalidGroup\.NotFound/){
      confess $@;
    } else {
      undef $security_group;
    }
  }
  $self->{_security_group} = $security_group;
}

1;
