#!/usr/bin/env perl
use v5.030;
use strictures 2;
use warnings;
no warnings 'uninitialized';

use Carp;
use JSON::PP;

sub handle {
    my ($payload, $context) = @_;
    my $step_name = $payload->{step_name};
    my @mast_args = keys %{$payload};

    # my $output_key = $payload->{output_key};
    # if (not defined $output_key) {
    #     # Result scope is used to name the output values without overriding existing global state
    #     my @set = ('0' ..'9', 'A' .. 'F');
    #     $output_key = join '' => map $set[rand @set], 1 .. 8;
    # }
    # @mast_args = grep(!/output_key/, @mast_args); # need to hardcode this
    
    @mast_args = grep(!/step_name/, @mast_args); # need to hardcode this

    # my $global_state = $payload->{global_state};
    # @mast_args = grep(!/global_state/, @mast_args) if defined $global_state; # need to hardcode this
    
    confess "step_name not provided. exiting" unless defined $step_name;
    my $script_location = "/opt/bin/$step_name"; # don't know how to not hardcode this

    my @p_args = ($script_location,);
    for(@mast_args) {
        my $next_val = $payload->{$_};
        my $hyphens_arg = $_;
        $hyphens_arg=~s/_/-/g;
        $hyphens_arg = "--${hyphens_arg}";
        # if a val is an array, then split the array into individual arguments
        if (ref $next_val eq 'ARRAY'){
            for my $val (@{$next_val}) {
                my @arg_pair = ($hyphens_arg, $val);
                push(@p_args, @arg_pair);
            }
        } else {
            my @arg_pair = ($hyphens_arg, $next_val);
            push(@p_args, @arg_pair);
        }
    }

    say @p_args;
    system("perl", @p_args) == 0
        or die "system perl @p_args failed: $?";
    # system("perl", "/opt/bin/$step_name", "--environment", "$environment", "--service-spec-json" $service_spec_json,); 
    # my $files = `perl /opt/bin/validate_service_spec --environment $val --service-spec-json "{}"`;
    # say $files;

    return unless defined $payload->{output_file};
    # if output file exists, read from output file and populate the return payload
    my %result_output;
    my $file = $payload->{output_file};
    open my $info, $file or die "Could not open $file: $!";
    # my $decoded_json = decode_json($global_state);
    while( my $line = <$info>)  {
        chomp $line; 
        my @spl = split("=", $line);
        my $key = $spl[0];
        my $value = $spl[1];
        $result_output{$key} = $value;
        # $decoded_json->{$key} = $value;

    }
    # $payload->{global_state} = encode_json($decoded_json);
    # $payload->{$output_key} = \%result_output;
    close $info;
    return \%result_output;
}
1;
