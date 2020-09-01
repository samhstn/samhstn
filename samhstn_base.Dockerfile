FROM debian:buster

# Install essential build packages
RUN apt-get update 
RUN apt-get install -y wget git locales curl \
    apt-transport-https ca-certificates gnupg-agent software-properties-common

# Install docker, see: https://docs.docker.com/engine/install/debian/
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN apt-key fingerprint 0EBFCD88
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
RUN apt-get update
RUN apt-get install -y docker-ce

# Set locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8

ENV HOME=/opt/app

WORKDIR /opt/app

# Install python3
RUN apt-update
RUN apt-get -y install python3 python3-pip
RUN pip3 install -vU setuptools

# Install python packages
RUN pip3 install cfn-lint awscli

# Install nodejs
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN apt-update
RUN apt-get install -y nodejs

# Install erlang and elixir
RUN wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
RUN dpkg -i erlang-solutions_2.0_all.deb
RUN apt-get update
RUN apt-get install -y esl-erlang
RUN apt-get install -y elixir

# Install hex and rebar
RUN mix do local.hex --force, local.rebar --force

# Install phoenix
RUN mix archive.install hex phx_new 1.5.4 --force

ENV MIX_ENV prod
