FROM ruby:2.6.5-slim

LABEL maintainer Travis CI GmbH <support+travis-api-docker-images@travis-ci.com>

# packages required for bundle install
RUN ( \
   apt-get update ; \
   apt-get install -y --no-install-recommends git make gcc g++ libpq-dev \
   && rm -rf /var/lib/apt/lists/* \
)

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

RUN mkdir -p /app
WORKDIR /app

COPY Gemfile      /app
COPY Gemfile.lock /app

RUN gem install bundler -v '2.1.4'
RUN bundler install --verbose --retry=3 --deployment --without development test
RUN gem install --user-install executable-hooks

COPY . /app

CMD ./script/server-buildpacks
