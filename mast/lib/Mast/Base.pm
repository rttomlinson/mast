package Mast::Base;

use v5.030;
use strictures 2;

use Moo;
use AWS::CLIWrapper;

has aws_region => (
  is => 'ro',
  required => 1,
);

has aws => (
  is => 'ro',
  lazy => 1,
  isa => sub {
    die "Expected AWS::CLIWrapper, got " . (ref($_[0]) || $_[0])
      unless ref($_[0]) and $_[0]->isa('AWS::CLIWrapper');
  },
  builder => sub {
    my $self = shift;

    return $self->{aws} if $self->{aws};

    return $self->{aws} = AWS::CLIWrapper->new(
      region => $self->aws_region,
      croak_on_error => 1,
    );
  },
);

has log => (
  is => 'ro',
  default => sub { sub { say @_ } },
);

around BUILDARGS => sub {
  my ($method, $class, @params) = @_;

  my %args = scalar @params == 1 && 'HASH' eq ref($params[0]) ? %{$params[0]} : @params;

  if ($args{aws} and not $args{aws_region}) {
    $args{aws_region} = $args{aws}->region;
  }

  return $class->$method(%args);
};

1;
