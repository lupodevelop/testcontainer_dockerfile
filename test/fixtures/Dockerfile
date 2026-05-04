FROM alpine:3.19

ARG GREETING=hello

ENV GREETING=${GREETING}
ENV TZ=Europe/Rome

EXPOSE 8080

LABEL org.opencontainers.image.title="testcontainer_dockerfile_itest"

HEALTHCHECK --interval=10s --timeout=2s --retries=3 \
  CMD echo healthy

CMD ["sh", "-c", "echo $GREETING && sleep 3600"]
