# FeedbackToMe API — Railway
FROM node:22-bookworm-slim AS base
WORKDIR /app

RUN apt-get update -y && apt-get install -y openssl ca-certificates && rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# NODE_ENV=production Railway Variables üzerinden verin; imajda sabitlemek bazen
# dashboard’daki JWT_SECRET ile zamanlama/merge sorunlarını zorlaştırabiliyor.
EXPOSE 8080

CMD ["node", "dist/index.js"]
