import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  serverExternalPackages: ["bullmq", "ioredis", "postgres"],
  experimental: {
    // @ts-expect-error nodeMiddleware is supported in Next.js 16 but not yet in the type definitions
    nodeMiddleware: true,
  },
};

export default nextConfig;
