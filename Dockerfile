# ---- Build Stage ----
FROM node:20-alpine AS builder
LABEL stage=builder

WORKDIR /app

RUN apk add --no-cache tzdata
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装 pnpm
RUN npm install -g pnpm

# 复制 package manifests
COPY package.json pnpm-lock.yaml ./

# 安装所有依赖 (包括 devDependencies 用于构建)
# 使用 --frozen-lockfile 确保使用 lock 文件中的确切版本
RUN pnpm install --frozen-lockfile

# 复制项目源代码 (除了 .dockerignore 中指定的文件)
COPY . .

# --- 添加这一行 ---
# 复制 config.example.ts 并重命名为 config.ts 以便 tsc 编译通过
# 真实 config.ts 仍在 .dockerignore 中，不会被复制
COPY config.example.ts config.ts
# --- 添加结束 ---

# 编译 TypeScript 到 JavaScript (输出到 dist 目录)
RUN pnpm build

# ---- Runtime Stage ----
FROM node:20-alpine

WORKDIR /app

# 安装 pnpm 和 pm2 (用于运行应用)
RUN npm install -g pnpm pm2

# 创建非 root 用户和组，提高安全性
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# 复制 package manifests
COPY package.json pnpm-lock.yaml ./

# 只安装生产依赖
# 使用 --frozen-lockfile 确保使用 lock 文件中的确切版本
RUN pnpm install --prod --frozen-lockfile

# 从 builder 阶段复制编译后的代码
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist

# 切换到非 root 用户
USER appuser

# 暴露默认的 WebSocket 端口 (根据 config.example.ts)
# 如果您的 config.ts 中修改了端口，请相应调整
EXPOSE 11451

# 运行应用的命令
CMD ["pm2-runtime", "dist/index.js", "--name", "ktpwarp-server"]

# --- 重要提示 ---
# 1. 您必须在运行时将您的 config.ts 文件挂载到容器的 /app/config.ts 路径。
# 2. 如果启用了 TLS (WEBSOCKET_ENABLE_TLS = true)，
#    您还需要将 TLS 证书和密钥文件挂载到容器中，
#    并确保 config.ts 中的 TLS_CERT_PATH 和 TLS_KEY_PATH 指向容器内的正确路径。

