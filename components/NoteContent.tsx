"use client";

import { useState } from "react";
import { AnimatePresence, motion } from "motion/react";

const URL_RE = /https?:\/\/[^\s)）】]+/g;
const IMG_RE = /\.(png|jpe?g|gif|webp|bmp)(\?|$)|\/media\//i;

type Seg = { kind: "text" | "img" | "link"; value: string };

function parse(text: string): Seg[] {
  const segs: Seg[] = [];
  let last = 0;
  for (const m of text.matchAll(URL_RE)) {
    const url = m[0];
    const i = m.index!;
    if (i > last) segs.push({ kind: "text", value: text.slice(last, i) });
    segs.push({ kind: IMG_RE.test(url) ? "img" : "link", value: url });
    last = i + url.length;
  }
  if (last < text.length) segs.push({ kind: "text", value: text.slice(last) });
  return segs;
}

/** 备注渲染：图片 URL 直接显示图片（走 /api/img 代理避免 HTTPS 混合内容），点击放大 */
export default function NoteContent({ text }: { text: string }) {
  const [zoom, setZoom] = useState<string | null>(null);
  const segs = parse(text);

  return (
    <>
      <div className="text-sm leading-relaxed whitespace-pre-wrap break-words">
        {segs.map((s, i) => {
          if (s.kind === "img") {
            const src = `/api/img?u=${encodeURIComponent(s.value)}`;
            return (
              <button
                key={i}
                type="button"
                onClick={() => setZoom(src)}
                className="block my-2 rounded-xl overflow-hidden border border-line hover:border-ink/25 transition-colors cursor-zoom-in"
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={src}
                  alt="附件图片"
                  loading="lazy"
                  className="max-h-56 w-auto object-contain bg-paper"
                />
              </button>
            );
          }
          if (s.kind === "link") {
            return (
              <a
                key={i}
                href={s.value}
                target="_blank"
                rel="noreferrer"
                className="text-accent underline decoration-accent/30 underline-offset-2 break-all"
              >
                {s.value}
              </a>
            );
          }
          return <span key={i}>{s.value}</span>;
        })}
      </div>

      {/* 放大查看 */}
      <AnimatePresence>
        {zoom && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
            onClick={() => setZoom(null)}
            className="fixed inset-0 z-[110] bg-ink/85 backdrop-blur-sm flex items-center justify-center cursor-zoom-out p-4"
          >
            <motion.img
              src={zoom}
              alt="放大查看"
              initial={{ scale: 0.9 }}
              animate={{ scale: 1 }}
              exit={{ scale: 0.94 }}
              transition={{ type: "spring", stiffness: 320, damping: 30 }}
              className="max-w-[94vw] max-h-[90vh] object-contain rounded-lg shadow-lift"
            />
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
