use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More tests => 21;
use Mast::AWS::Fargate qw(cpu_to_number memory_to_number adjust_cpu adjust_cpu_and_memory);

is cpu_to_number(256), 256, "cpu_to_number numeric input";
is cpu_to_number('0.25vcpu'), 256, "cpu_to_number vcpu input 1";
is cpu_to_number('0.3 vCPU'), 307.2, "cpu_to_number vcpu input 2";
is cpu_to_number('0.5 vCPU'), 512, "cpu_to_number vcpu input 3";

is memory_to_number(1024), 1024, "memory_to_number numeric input";
is memory_to_number('128 mb'), 128, "memory_to_number mb input";
is memory_to_number('4gb'), 4096, "memory_to_number gb input";

is adjust_cpu(128), 256, "adjust_cpu 1";
is adjust_cpu('.1 vcpu'), 256, "adjust_cpu 2";
is adjust_cpu('.3vCPU'), 512, "adjust_cpu 3";
is adjust_cpu(1000), 1024, "adjust_cpu 4";

eval { adjust_cpu 5000 };

like $@, qr/Cannot find supported Fargate CPU limit for given value of 5000/, "adjust_cpu 5";

{
  my ($cpu, $mem) = adjust_cpu_and_memory(100, 200);

  is $cpu, 256, "adjust_cpu_and_memory 1 cpu";
  is $mem, 512, "adjust_cpu_and_memory 1 memory";
}

{
  my ($cpu, $mem) = adjust_cpu_and_memory(100, 600);

  is $cpu, 256, "adjust_cpu_and_memory 2 cpu";
  is $mem, 1024, "adjust_cpu_and_memory 2 memory";
}

{
  my ($cpu, $mem) = adjust_cpu_and_memory(100, '2.5gb');

  is $cpu, 512, "adjust_cpu_and_memory 3 cpu";
  is $mem, 3072, "adjust_cpu_and_memory 3 memory";
}

{
  my $adj = adjust_cpu_and_memory(100, 29000);

  is $adj->[0], 4096, "adjust_cpu_and_memory 4 cpu";
  is $adj->[1], 29 * 1024, "adjust_cpu_and_memory 4 memory";
}

eval { adjust_cpu_and_memory(100, '32gb') };

like $@, qr/Cannot find supported Fargate memory limit for given values of CPU 100 and memory 32gb/,
  "adjust_cpu_and_memory 5";
