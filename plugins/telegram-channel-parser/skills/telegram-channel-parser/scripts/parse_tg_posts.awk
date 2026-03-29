#!/usr/bin/awk -f
# parse_tg_posts.awk — extract posts from Telegram web preview HTML
# Output: id \t date \t views \t reactions \t fwd_from \t fwd_link \t text_preview \t media_url
#
# Note: t.me/s/ does NOT expose share/forward COUNTS (only available via MTProto).
# fwd_from = channel name this post was forwarded from (empty if original)
# fwd_link = link to original post (empty if original)
# media_url = first image/video thumbnail URL (empty if no media)

BEGIN { OFS = "\t"; id = ""; date = ""; views = ""; text = ""; reactions = 0; fwd_from = ""; fwd_link = ""; media_url = "" }

/data-post=/ {
    if (id != "") {
        gsub(/[\t\n\r]+/, " ", text)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
        if (length(text) > 200) text = substr(text, 1, 200) "..."
        gsub(/[[:space:]]/, "", views)
        if (reactions == 0) reactions = ""
        print id, date, views, reactions, fwd_from, fwd_link, text, media_url
    }
    id = ""; date = ""; views = ""; text = ""; reactions = 0; fwd_from = ""; fwd_link = ""; media_url = ""
    tmp = $0
    sub(/.*data-post="[^"]*\//, "", tmp)
    sub(/".*/, "", tmp)
    if (tmp ~ /^[0-9]+$/) id = tmp
}

id != "" && /datetime="/ && date == "" {
    tmp = $0
    sub(/.*datetime="/, "", tmp)
    sub(/".*/, "", tmp)
    date = tmp
}

id != "" && /tgme_widget_message_views/ {
    tmp = $0
    sub(/.*tgme_widget_message_views[^>]*>/, "", tmp)
    sub(/<.*/, "", tmp)
    gsub(/[[:space:]]/, "", tmp)
    if (tmp != "" && views == "") views = tmp
}

# Forwarded from — extract source channel name and link
id != "" && /tgme_widget_message_forwarded_from_name/ && fwd_from == "" {
    tmp = $0
    # Extract link: href="https://t.me/channel/123"
    link = tmp
    if (match(link, /href="[^"]+"/)) {
        link = substr(link, RSTART + 6, RLENGTH - 7)
        fwd_link = link
    }
    # Extract name from <span dir="auto">Name</span>
    sub(/.*<span[^>]*>/, "", tmp)
    sub(/<\/span>.*/, "", tmp)
    gsub(/[[:space:]]+/, " ", tmp)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", tmp)
    if (tmp != "") fwd_from = tmp
}

# Media — extract first image URL from background-image:url('...')
id != "" && /tgme_widget_message_photo_wrap/ && media_url == "" {
    tmp = $0
    if (match(tmp, /background-image:url\('[^']+'\)/)) {
        media_url = substr(tmp, RSTART + 22, RLENGTH - 24)
    }
}

# Video thumbnail
id != "" && /tgme_widget_message_video_thumb/ && media_url == "" {
    tmp = $0
    if (match(tmp, /background-image:url\('[^']+'\)/)) {
        media_url = substr(tmp, RSTART + 22, RLENGTH - 24)
    }
}

id != "" && /tgme_widget_message_text/ && text == "" {
    tmp = $0
    gsub(/<br[\/]?>/, " ", tmp)
    gsub(/<[^>]*>/, "", tmp)
    gsub(/&amp;/, "\\&", tmp)
    gsub(/&lt;/, "<", tmp)
    gsub(/&gt;/, ">", tmp)
    gsub(/&quot;/, "\"", tmp)
    gsub(/&#0*36;/, "$", tmp)
    gsub(/&nbsp;/, " ", tmp)
    gsub(/&#39;/, "'", tmp)
    gsub(/[[:space:]]+/, " ", tmp)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", tmp)
    if (tmp != "") text = tmp
}

id != "" && /tgme_reaction/ {
    tmp = $0
    while (match(tmp, /<\/i>[0-9]+/)) {
        val = substr(tmp, RSTART, RLENGTH)
        sub(/<\/i>/, "", val)
        if (val + 0 > 0) reactions = reactions + val
        tmp = substr(tmp, RSTART + RLENGTH)
    }
}

END {
    if (id != "") {
        gsub(/[\t\n\r]+/, " ", text)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
        if (length(text) > 200) text = substr(text, 1, 200) "..."
        gsub(/[[:space:]]/, "", views)
        if (reactions == 0) reactions = ""
        print id, date, views, reactions, fwd_from, fwd_link, text, media_url
    }
}
