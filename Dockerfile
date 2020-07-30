# source fetching
FROM alpine:3.12 as src
ARG SRC_MOTION_SOURCE="git"
ARG SRC_MOTION_VERSION="master"
ARG SRC_MOTION_CHECKSUM
WORKDIR /build
RUN set -ex ;\
	case "$SRC_MOTION_SOURCE" in \
		"git") \
			apk add --no-cache git ;\
			git clone -n https://github.com/Motion-Project/motion.git /src ;\
			cd /src ;\
			git checkout "$SRC_MOTION_VERSION" ;\
		;; \
		"tar") \
			apk add --no-cache curl ca-certificates ;\
			curl -fSL \
				https://github.com/Motion-Project/motion/archive/release-$SRC_MOTION_VERSION.tar.gz \
				-o motion.tar.gz \
			;\
			echo "${SRC_MOTION_CHECKSUM}  motion.tar.gz" | md5sum -c - ;\
			tar -zxC . -f motion.tar.gz ;\
			mkdir src ;\
			rm motion.tar.gz ;\
			mv motion* /src ;\
		;; \
        *) \
            echo "Unknown src source: '$SRC_MOTION_SOURCE'" ; \
            exit 1 ; \
        ;; \
	esac

# toolchain
FROM alpine:3.12 as builder
ARG USE_V4L2
ARG USE_FFMPEG
ARG USE_WEBP
ARG USE_MARIADB
ARG USE_SQLITE
ARG USE_POSTGRESQL
WORKDIR /build
RUN apk add --virtual .deps-motion-config \
		# configure and build tools
		autoconf automake gettext-dev g++ make pkgconf libtool \
		# git is used by autopoint
		git \
		# reqires deps
		jpeg-dev \
		libmicrohttpd-dev \
		# options deps
		$( [ "$USE_FFMPEG" == 'yes' ] && echo ffmpeg-dev ) \
		$( [ "$USE_V4L2" == 'yes' ] && echo linux-headers ) \
		$( [ "$USE_WEBP" == 'yes' ] && echo libwebp-dev ) \
		$( [ "$USE_MARIADB" == 'yes' ] && echo mariadb-dev ) \
		$( [ "$USE_SQLITE" == 'yes' ] && echo sqlite-dev ) \
		$( [ "$USE_POSTGRESQL" == 'yes' ] && echo postgresql-dev )

# actual build
FROM builder as build
ARG USE_V4L2
ARG USE_FFMPEG
ARG USE_WEBP
ARG USE_MARIADB
ARG USE_SQLITE
ARG USE_POSTGRESQL
WORKDIR /build
COPY --from=src /src /build
RUN set -ex ;\
	# configure
	autoreconf -fiv ;\
	./configure \
		$( [ ! "$USE_FFMPEG" == 'yes' ] && echo --without-ffmpeg ) \
		$( [ ! "$USE_V4L2" == 'yes' ] && echo --without-v4l2 ) \
		$( [ ! "$USE_WEBP" == 'yes' ] && echo --without-webp ) \
		$( [ ! "$USE_MARIADB" == 'yes' ] && echo --without-mariadb ) \
		$( [ ! "$USE_SQLITE" == 'yes' ] && echo --without-sqlite3 ) \
		$( [ ! "$USE_POSTGRESQL" == 'yes' ] && echo --without-pgsql ) \
	;\
	# build
	make ;\
	# install =)
	make install

# runtime base
FROM alpine:3.12 as target_deps
ARG USE_V4L2
ARG USE_FFMPEG
ARG USE_WEBP
ARG USE_MARIADB
ARG USE_SQLITE
ARG USE_POSTGRESQL
RUN set -ex ;\
    apk add tzdata ;\
	apk add --no-cache \
	    --virtual .motion-runtime-deps \
		libintl \
		jpeg \
		libmicrohttpd \
		$( [ "$USE_FFMPEG" == 'yes' ] && echo ffmpeg-libs ) \
		$( [ "$USE_WEBP" == 'yes' ] && echo libwebp ) \
		$( [ "$USE_MARIADB" == 'yes' ] && echo mariadb-connector-c ) \
		$( [ "$USE_SQLITE" == 'yes' ] && echo sqlite-libs ) \
		$( [ "$USE_POSTGRESQL" == 'yes' ] && echo libpq )

# final image
FROM target_deps as final
WORKDIR /motion
COPY --from=build /usr/local/bin/motion /usr/local/bin/motion
COPY --from=build /usr/local/share/locale /usr/local/share/locale
COPY --from=build /usr/local/etc/motion/motion-dist.conf /usr/local/etc/motion/motion.conf

VOLUME /usr/local/etc/motion
VOLUME /var/lib/motion

CMD [ "motion", "-n" ]
