FROM ruby:3.2-alpine

ARG VERSION=v1.0.0
ENV DEPLOYMENT_VERSION=$VERSION

RUN apk add --no-cache build-base sqlite-dev tzdata yaml-dev
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]