# The game server's Linux image. Server/ uses ../HeistCore, so build from the repo root:
#   docker build -f Server/Dockerfile -t heist-server .
# Server/deploy/deploy.sh builds it on Cloud Build instead, so the Mac needs no Docker.

FROM swift:6.4-noble AS build
WORKDIR /src
# Only the packages themselves: a Mac's .build folders must not reach the Linux build.
COPY HeistCore/Package.swift HeistCore/
COPY HeistCore/Sources HeistCore/Sources/
COPY HeistCore/Tests HeistCore/Tests/
COPY Server/Package.swift Server/Package.resolved Server/
COPY Server/Sources Server/Sources/
WORKDIR /src/Server
RUN swift build -c release --product HeistServer \
    && cp "$(swift build -c release --show-bin-path)/HeistServer" /HeistServer

FROM swift:6.4-noble-slim
RUN useradd --system --uid 2000 --no-create-home heist && mkdir /data && chown heist /data
COPY --from=build /HeistServer /usr/local/bin/HeistServer
USER heist
ENV PORT=8080 DATA_DIR=/data
EXPOSE 8080
VOLUME /data
ENTRYPOINT ["HeistServer"]
