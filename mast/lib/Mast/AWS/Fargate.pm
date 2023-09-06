package Mast::AWS::Fargate;

use v5.030;
use warnings;
no warnings 'uninitialized';

use Exporter 'import';
use Carp 'confess';

our @EXPORT_OK = qw(cpu_to_number memory_to_number adjust_cpu adjust_cpu_and_memory);

# Fargate does not support arbitrary CPU and memory requirements for a task. These are supported
# configurations listed in https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html
my %fargate_configurations = (
  256  => [map { 1024 * $_ } 0.5, 1, 2],
  512  => [map { 1024 * $_ } 1..4],
  1024 => [map { 1024 * $_ } 2..8],
  2048 => [map { 1024 * $_ } 4..16],
  4096 => [map { 1024 * $_ } 8..30],
);

my @cpu_values = sort { $a <=> $b } keys %fargate_configurations;
my %next_cpu_values = map { $cpu_values[$_] => $cpu_values[$_ + 1] } 0..$#cpu_values;

sub cpu_to_number {
  my ($value) = @_;
  
  return $value unless $value =~ /vcpu/i;
  
  return 1024 * $value =~ s/\s*vcpu//ir;
}

sub memory_to_number {
  my ($value) = @_;
  
  return $value unless $value =~ /mb|gb/i;
  
  no warnings 'numeric';
  return $value =~ /gb/ ? $value * 1024 : $value * 1;
}

sub adjust_cpu {
  my ($cpu) = @_;
  
  my $cpu_number = cpu_to_number($cpu);
  
  for my $cpu_value (@cpu_values) {
    if ($cpu_value >= $cpu_number) {
      return $cpu_value;
    }
  }
  
  confess "Cannot find supported Fargate CPU limit for given value of $cpu";
}

sub adjust_cpu_and_memory {
  my ($cpu, $memory) = @_;

  my $cpu_value = adjust_cpu($cpu);
  my $memory_number = memory_to_number($memory);
  
  while (defined $cpu_value) {
    for my $memory_value (@{$fargate_configurations{$cpu_value}}) {
      if ($memory_value >= $memory_number) {
        return wantarray ? ($cpu_value, $memory_value) : [$cpu_value, $memory_value];
      }
    }

    $cpu_value = $next_cpu_values{$cpu_value};
  }
  
  confess "Cannot find supported Fargate memory limit for given values of CPU $cpu and memory $memory";
}

1;