use v5.030;
use warnings;
no warnings 'uninitialized';

use Test::More;

use Mast::Service::Metadata;

my $tests = eval join '', <DATA> or die "$@";

for my $test (@$tests) {
  my ($name, $input, $want) = @$test{qw(name input want)};

  # next unless $name eq 'registry/image';

  my @have;

  eval { @have = Mast::Service::Metadata::_parse_docker_image_name($input) };

  is "$@", "", "$name no exception";
  is_deeply \@have, $want, "$name output"
    or diag explain "want: ", $want, "\nhave:", \@have;
}

done_testing;

__DATA__
[{
  name => 'image',
  input => 'ubuntu',
  want => ['', 'ubuntu'],
}, {
  name => 'image:tag',
  input => 'ubuntu:latest',
  want => ['', 'ubuntu:latest'],
}, {
  name => 'image@digest',
  input => 'ubuntu@sha256:26c68657ccce2cb0a31b330cb0be2b5e108d467f641c62e13ab40cbec258c68d',
  want => ['', 'ubuntu@sha256:26c68657ccce2cb0a31b330cb0be2b5e108d467f641c62e13ab40cbec258c68d'],
}, {
  name => 'org/image',
  input => 'foo/bar',
  want => ['', 'foo/bar'],
}, {
  name => 'org/image:tag',
  input => 'foo/bar:qux',
  want => ['', 'foo/bar:qux'],
}, {
  name => 'org/image@digest',
  input => 'foo/bar@sha256:26c68657ccce2cb0a31b330cb0be2b5e108d467f641c62e13ab40cbec258c68d',
  want => ['', 'foo/bar@sha256:26c68657ccce2cb0a31b330cb0be2b5e108d467f641c62e13ab40cbec258c68d'],
}, {
  name => 'registry/image',
  input => 'registry-1.docker.io/debian',
  want => ['registry-1.docker.io', 'debian'],
}, {
  name => 'registry/image:tag',
  input => 'registry-1.docker.io/debian:bookworm',
  want => ['registry-1.docker.io', 'debian:bookworm'],
}, {
  name => 'registry/image@digest',
  input => 'registry-1.docker.io/debian@sha256:ee71fe8b4093251ca8462c29b2d78cdb491fd124a20350c89cd3456a43324a73',
  want => ['registry-1.docker.io', 'debian@sha256:ee71fe8b4093251ca8462c29b2d78cdb491fd124a20350c89cd3456a43324a73'],
}, {
  name => 'registry/org/image',
  input => 'public.ecr.aws/nginx/nginx',
  want => ['public.ecr.aws', 'nginx/nginx'],
}, {
  name => 'registry/org/image:tag',
  input => 'public.ecr.aws/nginx/nginx:1-alpine-perl',
  want => ['public.ecr.aws', 'nginx/nginx:1-alpine-perl'],
}, {
  name => 'registry/org/image@digest',
  input => 'public.ecr.aws/nginx/nginx@sha256:bb840cafcef21b6df339f1f977c21ee40a91edb6bd12950a128a4c7c1aaacdce',
  want => ['public.ecr.aws', 'nginx/nginx@sha256:bb840cafcef21b6df339f1f977c21ee40a91edb6bd12950a128a4c7c1aaacdce'],
}, {
  name => 'registry:port/org/image',
  input => 'public.ecr.aws:443/nginx/nginx',
  want => ['public.ecr.aws:443', 'nginx/nginx'],
}, {
  name => 'registry:port/org/image:tag',
  input => 'public.ecr.aws:443/nginx/nginx:1-alpine-perl',
  want => ['public.ecr.aws:443', 'nginx/nginx:1-alpine-perl'],
}, {
  name => 'registry:port/org/image@digest',
  input => 'public.ecr.aws:443/nginx/nginx@sha256:bb840cafcef21b6df339f1f977c21ee40a91edb6bd12950a128a4c7c1aaacdce',
  want => ['public.ecr.aws:443', 'nginx/nginx@sha256:bb840cafcef21b6df339f1f977c21ee40a91edb6bd12950a128a4c7c1aaacdce'],
}]
