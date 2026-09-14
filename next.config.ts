import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // 生产部署：自包含产物，服务器无需 npm install / 构建
  output: "standalone",
};

export default nextConfig;
