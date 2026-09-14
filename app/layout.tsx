import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Todo 待办清单",
  description: "个人私用待办清单",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body className="antialiased">{children}</body>
    </html>
  );
}
