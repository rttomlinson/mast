Mast
=====

Mast is a collection of software that defines a Service Spec and functions that operate using the spec. The Service Spec strives to make no assumptions about HOW deployments should happen, but only to describe the configuration of resources within a given environment. An instance of the spec is an immutable document that is only constructed once and never modified. Any changes to the document will yield a new instance of the spec.

Building the Docker image:

    make build

Pushing the Docker image:

    make push

Testing:

    export GITHUB_TOKEN=<GitHub access token>
    cd mast
    make test

Build locally and skip testing:

    make quick

Testing while developing:

    cd mast
    perl -Ilib t/test.t # single test
    prove -Ilib         # all tests

Pure code tests will run without GITHUB_TOKEN variable.

Cleaning up:

    make clean

Or:

    make realclean

The environment value that you provide becomes a "protected" key word in your spec. i.e. Any hash (dictionary, json object) found in the spec during normalization will be replaced with the value found at that keyword. For example:
{
    hello: {
        first: "foo",
        second: "bar",
        third: "baz"
    }
}
if you pass, "second" as your environment, the value at 'hello' will be collapsed to:
{
    hello: "bar"
}

perl Makefile.PL && make test && make manifest && make disttest && make dist && make realclean && mv Mast-1.00.tar.gz ~/Downloads/
