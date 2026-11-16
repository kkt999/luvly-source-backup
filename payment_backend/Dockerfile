FROM node:22-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app/payment_backend
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY *.mjs ./
COPY accessory-catalogue.json /app/assets/images/accessory-catalogue.json
COPY guide.json /app/assets/support/guide.json
USER node
CMD ["node", "server.mjs"]
