FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src.js ./
RUN mkdir -p /data
ENV PORT=8080 DATA_DIR=/data
EXPOSE 8080
CMD ["node", "src.js"]
