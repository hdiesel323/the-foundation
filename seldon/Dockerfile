FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --production=false

COPY tsconfig.json index.ts ./

EXPOSE 18789

CMD ["npx", "tsx", "index.ts"]
