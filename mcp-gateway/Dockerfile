FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app

COPY package.json server.mjs ./

RUN npm install --production

EXPOSE 3000

CMD ["node", "server.mjs"]
