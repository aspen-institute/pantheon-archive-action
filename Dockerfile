# This file is used to build a Bats test environment; it is not part of the
# action itself. See src/sync.sh.

FROM bats/bats:latest

RUN apk add --no-cache curl git

# Install lox's fork of bats-mock
RUN mkdir -p /usr/lib/bats/bats-mock \
    && curl -sSL https://github.com/lox/bats-mock/archive/v1.3.0.tar.gz -o /tmp/bats-mock.tgz \
    && tar -zxf /tmp/bats-mock.tgz -C /usr/lib/bats/bats-mock --strip 1 \
    && printf 'source "%s"\n' "/usr/lib/bats/bats-mock/stub.bash" >> /usr/lib/bats/bats-mock/load.bash \
    && rm -rf /tmp/bats-mock.tgz

COPY src src
COPY tests tests

ENTRYPOINT []
CMD ["bats", "tests"]
