/**
 * Telegram Digest Feed — React artifact template
 *
 * Agent: after running digest.sh, parse TSV output and substitute into POSTS_DATA below.
 * Then render this as a React artifact.
 *
 * TSV columns from digest: id \t date \t views \t reactions \t fwd_from \t fwd_link \t text \t media_url
 * Each post also needs a "channel" field (the channel username it came from).
 */

import { useState, useMemo } from "react";

// ---- Agent substitutes this data ----
const POSTS_DATA: Post[] = [
  // Example:
  // { id: "123", channel: "countwithsasha", date: "2026-03-29T14:30:00+00:00", views: "1.2K", reactions: "45", text: "Post text here...", mediaUrl: "https://cdn..." },
];

const CHANNELS: Record<string, { title: string; subscribers: string }> = {
  // Example:
  // countwithsasha: { title: "Count With Sasha", subscribers: "12K" },
};
// ---- End of data section ----

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
  "24h": "24 часа",
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
  if (diff < 60) return "только что";
  if (diff < 3600) return `${Math.floor(diff / 60)} мин`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} ч`;
  if (diff < 604800) return `${Math.floor(diff / 86400)} д`;
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

function PostCard({ post }: { post: Post }) {
  const color = getChannelColor(post.channel);
  const channelInfo = CHANNELS[post.channel];
  const displayName = channelInfo?.title || `@${post.channel}`;
  const postUrl = `https://t.me/${post.channel}/${post.id}`;

  return (
    <div style={{
      background: "#fff",
      borderRadius: 12,
      padding: 16,
      marginBottom: 12,
      boxShadow: "0 1px 3px rgba(0,0,0,0.08)",
      borderLeft: `4px solid ${color}`,
    }}>
      <div style={{ display: "flex", alignItems: "center", marginBottom: 10, gap: 10 }}>
        <div style={{
          width: 40, height: 40, borderRadius: "50%",
          background: color, display: "flex", alignItems: "center",
          justifyContent: "center", color: "#fff", fontWeight: 700,
          fontSize: 16, flexShrink: 0,
        }}>
          {post.channel[0].toUpperCase()}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: 14, color: "#1a1a1a" }}>{displayName}</div>
          <div style={{ fontSize: 12, color: "#8e8e93" }}>{timeAgo(post.date)}</div>
        </div>
        <a href={postUrl} target="_blank" rel="noopener noreferrer"
          style={{ fontSize: 12, color: "#2AABEE", textDecoration: "none", flexShrink: 0 }}>
          Открыть
        </a>
      </div>

      {post.mediaUrl && (
        <div style={{ marginBottom: 10, borderRadius: 8, overflow: "hidden" }}>
          <img src={post.mediaUrl} alt="" style={{ width: "100%", display: "block", maxHeight: 300, objectFit: "cover" }} />
        </div>
      )}

      <div style={{ fontSize: 14, lineHeight: 1.5, color: "#333", whiteSpace: "pre-wrap", wordBreak: "break-word" }}>
        {post.text}
      </div>

      {post.fwd_from && (
        <div style={{ fontSize: 12, color: "#8e8e93", marginTop: 8, fontStyle: "italic" }}>
          Переслано из {post.fwd_from}
        </div>
      )}

      <div style={{ display: "flex", gap: 16, marginTop: 12, fontSize: 13, color: "#8e8e93" }}>
        {post.views && <span>👁 {post.views}</span>}
        {post.reactions && <span>❤️ {post.reactions}</span>}
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
    <div style={{ maxWidth: 600, margin: "0 auto", padding: "16px 12px", fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif" }}>
      <h2 style={{ margin: "0 0 4px", fontSize: 20, fontWeight: 700 }}>Telegram Digest</h2>
      <p style={{ margin: "0 0 16px", fontSize: 13, color: "#8e8e93" }}>
        {filtered.length} постов из {channelFilter === "all" ? allChannels.length : 1} каналов
      </p>

      {/* Period filter */}
      <div style={{ display: "flex", gap: 6, marginBottom: 12, flexWrap: "wrap" }}>
        {(Object.keys(PERIOD_LABELS) as Period[]).map((p) => (
          <button key={p} onClick={() => setPeriod(p)} style={{
            padding: "6px 14px", borderRadius: 20, border: "none", cursor: "pointer",
            fontSize: 13, fontWeight: period === p ? 600 : 400,
            background: period === p ? "#2AABEE" : "#f0f0f0",
            color: period === p ? "#fff" : "#555",
          }}>
            {PERIOD_LABELS[p]}
          </button>
        ))}
      </div>

      {/* Channel filter */}
      <div style={{ display: "flex", gap: 6, marginBottom: 16, flexWrap: "wrap" }}>
        <button onClick={() => setChannelFilter("all")} style={{
          padding: "4px 12px", borderRadius: 16, border: "none", cursor: "pointer",
          fontSize: 12, background: channelFilter === "all" ? "#333" : "#f0f0f0",
          color: channelFilter === "all" ? "#fff" : "#555",
        }}>
          Все
        </button>
        {allChannels.map((ch) => (
          <button key={ch} onClick={() => setChannelFilter(ch)} style={{
            padding: "4px 12px", borderRadius: 16, border: "none", cursor: "pointer",
            fontSize: 12, background: channelFilter === ch ? getChannelColor(ch) : "#f0f0f0",
            color: channelFilter === ch ? "#fff" : "#555",
          }}>
            @{ch}
          </button>
        ))}
      </div>

      {/* Posts feed */}
      {filtered.length === 0 ? (
        <div style={{ textAlign: "center", padding: 40, color: "#8e8e93" }}>
          Нет постов за выбранный период
        </div>
      ) : (
        filtered.map((post) => <PostCard key={`${post.channel}-${post.id}`} post={post} />)
      )}
    </div>
  );
}
