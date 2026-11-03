# Vyapari online server — native binary on a minimal runtime image.
FROM dart:stable AS build
WORKDIR /src
COPY pubspec.yaml analysis_options.yaml ./
COPY packages/core/pubspec.yaml packages/core/
COPY packages/protocol/pubspec.yaml packages/protocol/
COPY packages/server/pubspec.yaml packages/server/
COPY server_bin/pubspec.yaml server_bin/
# The Flutter app is not needed for the server image.
RUN sed -i '/packages\/app/d' pubspec.yaml && dart pub get
COPY packages/core packages/core
COPY packages/protocol packages/protocol
COPY packages/server packages/server
COPY server_bin server_bin
RUN dart compile exe server_bin/bin/main.dart -o /out/vyapari_server
# SQLite shared library for the store, copied into the minimal runtime.
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-0 \
 && mkdir -p /runtime/usr/lib \
 && cp "$(find /usr/lib -name 'libsqlite3.so.0' | head -n1)" /runtime/usr/lib/ \
 && ln -s libsqlite3.so.0 /runtime/usr/lib/libsqlite3.so

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/vyapari_server /app/vyapari_server
COPY assets/boards /app/assets/boards
WORKDIR /app
ENV LD_LIBRARY_PATH=/usr/lib VYAPARI_DB=/data/vyapari.db
VOLUME /data
EXPOSE 47800
ENTRYPOINT ["/app/vyapari_server"]
