apt-get update
apt-get install -y docker.io jq make libperlio-eol-perl
curl -L https://cpanmin.us | perl - App::cpanminus
cpanm AWS::CLIWrapper local::lib
cat > /bin/docker_run <<"__END__"
#!/bin/sh -e

image="clarius.jfrog.io/clari-docker-v0-virtual/$1"; shift

# Docker will print out the pulled image name and tag on stdout,
# we don't want it to pollute the output for the actual tool we're calling
# in the next step. We also don't want this command to fail step execution
# if pulling timed out or something; there's a great chance that pulling
# will not update the called image anyway since they are not changed
# all that often, and the probability of the image not being in local cache already
# is very, very low.
docker pull -q "$image" >/dev/null || true
exec docker run --init -v "$TMPDIR:$TMPDIR" -i "$image" "$@"
__END__
chmod +x /bin/docker_run

curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -o awscliv2.zip
./aws/install --update
