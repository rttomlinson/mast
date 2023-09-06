package Mast::Service::Metadata;

use v5.030;
use warnings;
no warnings 'uninitialized';

use JSON::PP;
use Carp 'confess';
use Exporter 'import';

use AWS::CLIWrapper;
use Net::DNS;
use HTTP::Tinyish;
use MIME::Base64 'encode_base64';

use Mast::AWS::ECS::Service;

our @EXPORT_OK = qw($service_spec_url_tag);

our $service_spec_url_tag = 'service_spec_url';
our $docker_hub_registry = 'registry-1.docker.io';

sub new {
    my ($class, %params) = @_;

    my $aws = delete $params{aws};
    $aws //= AWS::CLIWrapper->new(
        region => $params{aws_region},
        croak_on_error => 1,
    );

    bless { aws => $aws, %params }, $class;
}

sub get_service_spec_from_active_service_cluster_tag {
    my ($self, %params) = @_;

    my $ecs_service_name = $self->get_ecs_service_name_from_active_service_cluster_tag(
        $params{cluster_name},
        $params{task_family},
    );

    my ($service_spec_json, $spec_url, $task_definition_arn) = $self->get_service_spec_from_task_definition_tag_using_ecs_service_name(
        service_name => $ecs_service_name,
        %params,
    );
    return ($service_spec_json, $spec_url, $task_definition_arn);
}

sub check_if_tag_exists_on_cluster {
    my ($self, %params,) = @_;
    my ($cluster_name, $tag_name,) = @params{qw(cluster_name tag_name)};
    say "Searching for the $tag_name tag on the $cluster_name cluster.";

    my $cluster = do {
        my $res = $self->{aws}->ecs('describe-clusters', {
            clusters => [$cluster_name],
            include => ['TAGS'],
        });

        $res->{clusters}->[0];
    };

    my @tags = grep { $_->{key} eq $tag_name } @{$cluster->{tags}};
    return scalar(@tags);
}

sub get_service_spec_from_task_definition_tag_using_ecs_service_name {
    my ($self, %params) = @_;
    my ($cluster_name, $ecs_service_name) = @params{'cluster_name', 'service_name'};

    my $task_definition_arn = $self->get_task_definition_arn_from_ecs_service($cluster_name, $ecs_service_name);
    my $spec_url = $self->get_spec_url_from_task_definition_tags($task_definition_arn);
    my $service_spec_json = get_service_spec_from_url($spec_url, %params);

    return ($service_spec_json, $spec_url, $task_definition_arn);
}

sub get_ecs_service_name_from_active_service_cluster_tag {
    my ($self, $cluster_name, $task_family) = @_;
    my $tag = "active-$task_family";
    say "Searching for the $tag tag on the $cluster_name cluster.";
    confess "you need to provide a task definition family name"
        unless defined $task_family;
    confess "you need to provide a cluster name"
        unless defined $cluster_name;

    my $cluster = do {
        my $res = $self->{aws}->ecs('describe-clusters', {
            clusters => [$cluster_name],
            include => ['TAGS'],
        });

        $res->{clusters}->[0];
    };

    my @tags = grep { $_->{key} eq $tag } @{$cluster->{tags}};

    return undef unless @tags;

    return $tags[0]->{value};
}

sub get_task_definition_arn_from_ecs_service {
    my ($self, $cluster_name, $ecs_service_name) = @_;

    my $ecs_service_object = Mast::AWS::ECS::Service->new(
        cluster => $cluster_name,
        name => $ecs_service_name,
        aws_region => $self->{aws_region},
        poll_interval => 10,
        aws => $self->{aws},
    );

    my $task_definition_arn = $ecs_service_object->describe->{taskDefinition};

    return $task_definition_arn;
}

sub get_spec_url_from_task_definition_tags {
    my ($self, $task_definition_arn) = @_;
    my ($task_definition_data, $task_definition_tags) = do {
        my $res = $self->{aws}->ecs('describe-task-definition', {
            'task-definition' => $task_definition_arn,
            include => ['TAGS'],
        });

        ($res->{taskDefinition}, $res->{tags},);
    };
    
    say "Searching for the $service_spec_url_tag tag on the task definition with arn $task_definition_arn.";
    my @filtered_task_definition_tags = grep { $_->{key} eq $service_spec_url_tag } @{$task_definition_tags};

    return undef unless @filtered_task_definition_tags;

    return $filtered_task_definition_tags[0]->{value};
}

sub get_image_configuration_from_spec_url {
    my ($spec_url, %params) = @_;

    confess "Error: cannot retrieve Docker image labels from service spec url " .
            "$spec_url, should be in docker:// schema"
        unless $spec_url =~ m|^docker://|;
    
    my $image_reference = $spec_url =~ s|^docker://||r;

    return get_image_configuration_from_docker_reference($image_reference, %params);
}

sub get_service_spec_from_url {
    my ($spec_url, %params) = @_;

    if ($spec_url =~ m|^docker://|) {
        my $image_reference = $spec_url =~ s|^docker://||r;

        my $image_configuration
            = get_image_configuration_from_docker_reference($image_reference, %params);
        
        return $image_configuration->{Labels}->{service_spec};
    }
    elsif ($spec_url =~ m|https://.*github|) {
        return get_service_spec_from_github_url($spec_url, %params);
    }
    else {
        confess "Unsupported service spec URL: $spec_url";
    }
}

sub get_image_configuration_from_docker_reference {
    my ($image_path, %params) = @_;

    my ($registry, $image_name_and_manifest_reference)
        = _parse_docker_image_name($image_path, %params);

    my $token = _get_token($registry, $image_name_and_manifest_reference, %params);
    my ($image, $digest) = _get_image_and_digest($registry, $image_name_and_manifest_reference, $token);
    my $image_configuration = _get_image_configuration($registry, $image, $digest, $token);

    return $image_configuration;
}

sub get_service_spec_from_github_url {
    my ($spec_url, %params) = @_;
    my ($github_token) = $params{github_token};

    confess "GitHub access token is required to retrieve service spec from $spec_url"
        unless $github_token;
    
    my $res = HTTP::Tinyish->new->get($spec_url, {
        headers => { Authorization => "token $github_token" },
    });

    confess "Error retrieving service spec from $spec_url: $res->{status} $res->{reason}"
        unless $res->{success};

    return $res->{content};
}

sub _parse_docker_image_name {
    my ($image_path) = @_;

    my @parts = split '/', $image_path;

    return ('', $image_path) unless @parts > 1;

    # The Docker image reference is essentially a URI with no scheme defined, and
    # the authority (hostname/fqdn) is optional. It is hard to determine whether
    # the potential authority part is a shorthand intranet host name, or a fqdn,
    # or it's not a host name altogether but a part of the image path in the default
    # registry.
    # To work around this, we cheat by simply taking the first part of the image path
    # and trying to do a DNS lookup on it. If there's a match, then it's the registry host.
    my $potential_registry = shift @parts;
    my $potential_host = $potential_registry =~ s/:\d+$//r;
    my @rr = rr($potential_host);

    return @rr ? ($potential_registry, join '/', @parts) : ('', $image_path);
}

sub _get_token {
    my ($registry, $image, %params) = @_;

    return $registry
        ? _get_docker_registry_token($image, $registry, %params)
        : _get_docker_hub_token($image, %params)
        ;
}

sub _get_docker_registry_token {
    my ($image, $registry, %params) = @_;

    my %tokens = _unpack_docker_registry_tokens($params{docker_registry_tokens});
    my $token = $tokens{$registry};

    confess "Authentication token for Docker registry $registry is required to retrieve service spec from $image"
        unless $token;
    
    return $token;
}

# TODO error handle the curl call
sub _get_docker_hub_token {
    my ($image_name_and_manifest_reference, %params) = @_;

    my ($image) = _split_docker_image_and_manifest_reference($image_name_and_manifest_reference);
    
    my ($docker_username, $docker_password) = @params{'docker_username', 'docker_password'};

    confess "Docker Hub username and password are required to retrieve service spec from $image"
        unless $docker_username && $docker_password;

    say "Retrieving Docker Hub authentication token for $image.";

    my $res = HTTP::Tinyish->new->get(
        "https://auth.docker.io/token?scope=repository:$image:pull&service=registry.docker.io",
        {
            headers => {
                Authorization => "Basic " . encode_base64 "$docker_username:$docker_password",
            },
        }
    );

    confess "Error retrieving authentication token from Docker Hub: $res->{status} $res->{reason}"
        unless $res->{success};

    my $token_data = decode_json $res->{content};

    return $token_data->{token};
}

sub _get_image_and_digest {
    my ($registry, $image_name_and_manifest_reference, $token) = @_;

    my ($image, $tag, $digest)
        = _split_docker_image_and_manifest_reference($image_name_and_manifest_reference);

    return ($image, $digest) if $digest;

    $registry ||= $docker_hub_registry;

    say "Retrieving digest for $registry/$image:$tag.";

    my $res = HTTP::Tinyish->new->get("https://$registry/v2/$image/manifests/$tag", {
        headers => {
            Accept => 'application/vnd.docker.distribution.manifest.v2+json',
            Authorization => "Bearer $token",
        },
    });

    confess "Error retrieving Docker image digest from $registry/$image:$tag: $res->{status} $res->{reason}"
        unless $res->{success};

    my $data = decode_json $res->{content};

    return ($image, $data->{config}->{digest});
}

sub _get_image_configuration {
    my ($registry, $image, $digest, $token) = @_;

    $registry ||= $docker_hub_registry;

    say "Retrieving image configuration for $registry/$image"."@"."$digest.";

    my $res = HTTP::Tinyish->new->get("https://$registry/v2/$image/blobs/$digest", {
        headers => {
            Authorization => "Bearer $token",
        },
    });

    confess "Error retrieving Docker image configuration from $registry/$image"."@"
            ."$digest: $res->{status} $res->{reason}"
        unless $res->{success};

    my $data = decode_json $res->{content};

    return $data->{config};
}

sub _split_docker_image_and_manifest_reference {
    my ($image_name_and_manifest_reference) = @_;

    if ($image_name_and_manifest_reference =~ /\@sha256:/) {
        my ($image, @digest) = split /@/, $image_name_and_manifest_reference;

        # image, tag, digest
        return ($image, '', join '@', @digest);
    }

    my ($image, $tag) = split /:/, $image_name_and_manifest_reference;

    # image, tag, digest
    return ($image, $tag, '');
}

sub _unpack_docker_registry_tokens {
    my ($args) = @_;

    my %tokens;

    for my $arg (@$args) {
        my ($registry, @token) = split /=/, $arg;

        $tokens{$registry} = join '=', @token;
    }

    return %tokens;
}

1;
