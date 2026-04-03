# Flutter Web → statik dosyalar → Node "serve" (Railway PORT uyumlu)
# https://docs.railway.app/deploy/dockerfiles

FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release

# ─── Çalışma imajı ───
FROM node:22-alpine

WORKDIR /app
RUN npm install -g serve@14

COPY --from=build /app/build/web ./web

ENV NODE_ENV=production

EXPOSE 8080

# Railway $PORT değişkenine bağlanır (yoksa 8080)
CMD ["sh", "-c", "exec serve -s web -l tcp://0.0.0.0:${PORT:-8080}"]
