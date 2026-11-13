# Tiny "demo-app": nginx that renders which version + environment is running.
FROM docker.io/library/nginx:1.31-alpine
ARG VERSION=0.0.0
ENV APP_VERSION=${VERSION} ENV_NAME=unknown BANNER_COLOR=#555 GREETING=hello
COPY default.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 8080
