ARG base
FROM $base AS debbuild

RUN cd /root && \
  sed -i 's/^# deb-src/deb-src/' /etc/apt/sources.list && \
  cat /etc/apt/sources.list && \
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get -y update && \
  apt-get -y install devscripts

RUN cd /root && \
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get -y source curl && \
  apt-get -y build-dep curl

# locate source dir and create a convenient symlink to it
RUN bash -c 'ln -s $(find /root -maxdepth 1 -type d -name "curl-*") /root/curl-source && ls /root && cd /root/curl-source'

RUN cd /root/curl-source && \
  echo "APPLY NECESSARY PATCH(ES) HERE" && \
  dch --local paas 'foo the bar all over the place' && \
  debuild -us -uc


ARG base
FROM $base
ARG arch
ARG locales
ARG packages
ARG package_args='--allow-downgrades --allow-remove-essential --allow-change-held-packages --no-install-recommends'
ARG user_id=2000
ARG group_id=2000

COPY arch/$arch/sources.list /etc/apt/sources.list

RUN echo "debconf debconf/frontend select noninteractive" | debconf-set-selections && \
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get -y $package_args update && \
  apt-get -y $package_args dist-upgrade && \
  apt-get -y $package_args install $packages && \
  apt-get clean && \
  find /usr/share/doc/*/* ! -name copyright | xargs rm -rf && \
  rm -rf \
    /usr/share/man/* /usr/share/info/* \
    /usr/share/groff/* /usr/share/lintian/* /usr/share/linda/* \
    /var/lib/apt/lists/* /tmp/*

# install over just the already-installed packages that have corresponding .dpkgs here
RUN --mount=from=debbuild,source=/root,target=/debbuild/root bash -c 'cd /debbuild/root && \
  export DEBIAN_FRONTEND=noninteractive && \
  dpkg -i $(find . -maxdepth 1 -type f -name "*.deb" -printf "%f\n" | sed -E "s/^([^_]+)_.*/\1/" | sort | comm -12 - <(dpkg-query -f "\${Package}\n" -W | sort) | xargs -I "{}" find . -maxdepth 1 -type f -name "{}_*.deb")' && \
  find /usr/share/doc/*/* ! -name copyright | xargs rm -rf && \
  rm -rf \
    /usr/share/man/* /usr/share/info/* \
    /usr/share/groff/* /usr/share/lintian/* /usr/share/linda/* \
    /var/lib/apt/lists/* /tmp/*

RUN sed -i s/#PermitRootLogin.*/PermitRootLogin\ no/ /etc/ssh/sshd_config && \
  sed -i s/#PasswordAuthentication.*/PasswordAuthentication\ no/ /etc/ssh/sshd_config

RUN echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \
  echo "$locales" | grep -f - /usr/share/i18n/SUPPORTED | cut -d " " -f 1 | xargs locale-gen && \
  dpkg-reconfigure -fnoninteractive -pcritical locales tzdata libc6

RUN useradd -u ${user_id} -mU -s /bin/bash vcap && \
  mkdir /home/vcap/app && \
  chown vcap:vcap /home/vcap/app && \
  ln -s /home/vcap/app /app

USER ${user_id}:${group_id}
