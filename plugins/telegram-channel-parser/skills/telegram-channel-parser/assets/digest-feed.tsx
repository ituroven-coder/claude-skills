/**
 * Telegram Digest Feed — React artifact template (ultra-compact reader)
 *
 * Usage:
 * 1. Agent runs: bash scripts/digest_json.sh --period today
 * 2. Script outputs JSON: { posts: [...], channels: {...} }
 * 3. Agent reads this template, replaces __DIGEST_DATA__ with the JSON
 * 4. Renders as React artifact
 */

import { useState, useMemo } from "react";

// __DIGEST_DATA__ — agent replaces this line with JSON from digest_json.sh
const _data: { posts: Post[]; channels: Record<string, { title: string; subscribers: string }> } = __DIGEST_DATA__;
const POSTS_DATA = _data.posts;
const CHANNELS = _data.channels;

interface Post {
  id: string;
  channel: string;
  date: string;
  views: string;
  reactions: string;
  fwd_from?: string;
  fwd_link?: string;
  text: string;
  mediaUrl?: string;
}

type Period = "24h" | "today" | "week" | "month" | "all";

const PERIOD_LABELS: Record<Period, string> = {
  "24h": "24ч",
  today: "Сегодня",
  week: "Неделя",
  month: "Месяц",
  all: "Все",
};

function getChannelColor(channel: string): string {
  const colors = [
    "#2AABEE", "#E14E54", "#9B59B6", "#3498DB", "#E67E22",
    "#1ABC9C", "#E74C3C", "#2ECC71", "#F39C12", "#8E44AD",
    "#16A085", "#D35400", "#2980B9", "#C0392B", "#27AE60",
  ];
  let hash = 0;
  for (let i = 0; i < channel.length; i++) {
    hash = channel.charCodeAt(i) + ((hash << 5) - hash);
  }
  return colors[Math.abs(hash) % colors.length];
}

function timeAgo(dateStr: string): string {
  const now = new Date();
  const date = new Date(dateStr);
  const diff = Math.floor((now.getTime() - date.getTime()) / 1000);
  if (diff < 60) return "сейчас";
  if (diff < 3600) return `${Math.floor(diff / 60)}м`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}ч`;
  if (diff < 604800) return `${Math.floor(diff / 86400)}д`;
  return date.toLocaleDateString("ru-RU", { day: "numeric", month: "short" });
}

function filterByPeriod(posts: Post[], period: Period): Post[] {
  if (period === "all") return posts;
  const now = new Date();
  const cutoff = new Date();
  switch (period) {
    case "24h": cutoff.setHours(now.getHours() - 24); break;
    case "today": cutoff.setHours(0, 0, 0, 0); break;
    case "week": cutoff.setDate(now.getDate() - 7); break;
    case "month": cutoff.setMonth(now.getMonth() - 1); break;
  }
  return posts.filter((p) => new Date(p.date) >= cutoff);
}

function PostRow({ post }: { post: Post }) {
  const [imgError, setImgError] = useState(false);
  const color = getChannelColor(post.channel);
  const postUrl = `https://t.me/${post.channel}/${post.id}`;

  return (
    <div style={{ padding: "10px 0", borderBottom: "1px solid #f0f0f0" }}>
      {/* Header: initial + channel + time */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
        <span style={{
          width: 22, height: 22, borderRadius: "50%", background: color,
          display: "inline-flex", alignItems: "center", justifyContent: "center",
          color: "#fff", fontSize: 11, fontWeight: 700, flexShrink: 0,
        }}>
          {post.channel[0].toUpperCase()}
        </span>
        <span style={{ fontSize: 13, fontWeight: 600, color: "#1a1a1a", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
          @{post.channel}
        </span>
        <span style={{ fontSize: 11, color: "#aaa", flexShrink: 0 }}>{timeAgo(post.date)}</span>
      </div>

      {/* Forwarded from */}
      {post.fwd_from && (
        <div style={{ fontSize: 11, color: "#8e8e93", marginBottom: 4, paddingLeft: 30 }}>
          ↩ {post.fwd_from}
        </div>
      )}

      {/* Media */}
      {post.mediaUrl && (
        <div style={{ paddingLeft: 30, marginBottom: 6 }}>
          {imgError ? (
            <div style={{
              width: "100%", height: 120, borderRadius: 8,
              background: "#f5f5f5", display: "flex", alignItems: "center",
              justifyContent: "center", fontSize: 28, color: "#ccc",
            }}>🖼</div>
          ) : (
            <img src={post.mediaUrl} alt=""
              onError={() => setImgError(true)}
              style={{ width: "100%", borderRadius: 8, objectFit: "cover", maxHeight: 300, display: "block" }} />
          )}
        </div>
      )}

      {/* Full post text with HTML formatting */}
      <div
        className="tg-post"
        style={{ paddingLeft: 30, fontSize: 14, lineHeight: 1.55, color: "#333", wordBreak: "break-word" }}
        dangerouslySetInnerHTML={{ __html: post.text }}
      />

      {/* Metrics + open link */}
      <div style={{ display: "flex", gap: 12, marginTop: 4, paddingLeft: 30, fontSize: 11, color: "#aaa", alignItems: "center" }}>
        {post.views && <span>👁 {post.views}</span>}
        {post.reactions && <span>❤️ {post.reactions}</span>}
        <span style={{ flex: 1 }} />
        <a href={postUrl} target="_blank" rel="noopener noreferrer"
          style={{ color: "#2AABEE", textDecoration: "none", cursor: "pointer" }}>
          Открыть →
        </a>
      </div>
    </div>
  );
}

export default function TelegramDigest() {
  const [period, setPeriod] = useState<Period>("today");
  const [channelFilter, setChannelFilter] = useState<string>("all");

  const allChannels = useMemo(() => [...new Set(POSTS_DATA.map((p) => p.channel))], []);

  const filtered = useMemo(() => {
    let posts = filterByPeriod(POSTS_DATA, period);
    if (channelFilter !== "all") {
      posts = posts.filter((p) => p.channel === channelFilter);
    }
    return posts.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  }, [period, channelFilter]);

  return (
    <div style={{ maxWidth: 400, margin: "0 auto", padding: "12px 8px", fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif" }}>
      <style>{`
        .tg-post a { color: #2AABEE; text-decoration: none; }
        .tg-post a:hover { text-decoration: underline; }
        .tg-post b, .tg-post strong { font-weight: 600; }
        .tg-post i, .tg-post em { font-style: italic; }
        .tg-post s, .tg-post del, .tg-post strike { text-decoration: line-through; color: #999; }
        .tg-post code { background: #f5f5f5; padding: 1px 4px; border-radius: 3px; font-size: 12px; }
        .tg-post pre { background: #f5f5f5; padding: 8px; border-radius: 6px; overflow-x: auto; font-size: 12px; }
        .tg-post blockquote { border-left: 3px solid #2AABEE; margin: 6px 0; padding: 4px 10px; color: #555; background: #f9f9f9; border-radius: 0 4px 4px 0; }
        .tg-post .tg-spoiler { background: #333; color: #333; border-radius: 3px; padding: 0 3px; cursor: pointer; transition: all 0.2s; }
        .tg-post .tg-spoiler:hover, .tg-post .tg-spoiler.revealed { background: transparent; color: inherit; }
        .tg-post br { display: block; content: ""; margin: 4px 0; }
      `}</style>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", marginBottom: 10 }}>
        <h2 style={{ margin: 0, fontSize: 17, fontWeight: 700 }}>Telegram Digest</h2>
        <span style={{ fontSize: 11, color: "#aaa" }}>
          {filtered.length} постов
        </span>
      </div>

      {/* Period tabs */}
      <div style={{ display: "flex", gap: 4, marginBottom: 8 }}>
        {(Object.keys(PERIOD_LABELS) as Period[]).map((p) => (
          <button key={p} onClick={() => setPeriod(p)} style={{
            padding: "4px 10px", borderRadius: 14, border: "none", cursor: "pointer",
            fontSize: 12, fontWeight: period === p ? 600 : 400,
            background: period === p ? "#2AABEE" : "#f5f5f5",
            color: period === p ? "#fff" : "#666",
          }}>
            {PERIOD_LABELS[p]}
          </button>
        ))}
      </div>

      {/* Channel chips */}
      <div style={{ display: "flex", gap: 4, marginBottom: 8, flexWrap: "wrap" }}>
        <button onClick={() => setChannelFilter("all")} style={{
          padding: "3px 8px", borderRadius: 10, border: "none", cursor: "pointer",
          fontSize: 11, background: channelFilter === "all" ? "#333" : "#f5f5f5",
          color: channelFilter === "all" ? "#fff" : "#666",
        }}>
          Все
        </button>
        {allChannels.map((ch) => (
          <button key={ch} onClick={() => setChannelFilter(ch)} style={{
            padding: "3px 8px", borderRadius: 10, border: "none", cursor: "pointer",
            fontSize: 11, background: channelFilter === ch ? getChannelColor(ch) : "#f5f5f5",
            color: channelFilter === ch ? "#fff" : "#666",
          }}>
            @{ch}
          </button>
        ))}
      </div>

      {/* Divider */}
      <div style={{ height: 1, background: "#e8e8e8", marginBottom: 4 }} />

      {/* Posts */}
      {filtered.length === 0 ? (
        <div style={{ textAlign: "center", padding: 32, color: "#aaa", fontSize: 13 }}>
          Нет постов за выбранный период
        </div>
      ) : (
        filtered.map((post) => <PostRow key={`${post.channel}-${post.id}`} post={post} />)
      )}
    </div>
  );
}
