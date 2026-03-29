#!/usr/bin/awk -f
# parse_tg_posts.awk — extract posts from Telegram web preview HTML
# Output: id \t date \t views \t reactions \t fwd_from \t fwd_link \t text_html \t media_url
#
# Note: t.me/s/ does NOT expose share/forward COUNTS (only available via MTProto).
# fwd_from = channel name this post was forwarded from (empty if original)
# fwd_link = link to original post (empty if original)
# media_url = first image/video thumbnail URL (empty if no media)

BEGIN { OFS = "\t"; id = ""; date = ""; views = ""; text = ""; reactions = 0; fwd_from = ""; fwd_link = ""; media_url = ""; in_text = 0 }

function clean_text(t) {
    gsub(/[\t\n\r]+/, " ", t)
    # Convert tg_spoiler class
    gsub(/class="tg_spoiler"/, "class=\"tg-spoiler\"", t)
    # Convert Telegram blockquote: opening div → <blockquote>, its closing </div> → </blockquote>
    # Mark quote-divs before stripping all divs
    gsub(/<div[^>]*class="[^"]*quote[^"]*"[^>]*>/, "<!BQ>", t)
    # Strip all div tags (open and close)
    gsub(/<\/?div[^>]*>/, "", t)
    # Now restore blockquotes — each <!BQ> needs a closing tag
    # Simple approach: replace markers, then ensure balanced tags
    gsub(/<!BQ>/, "<blockquote>", t)
    # Ensure all blockquotes are closed — count and append missing closers
    {
        _open = 0; _close = 0
        _tmp = t
        while (match(_tmp, /<blockquote>/)) { _open++; _tmp = substr(_tmp, RSTART + RLENGTH) }
        _tmp = t
        while (match(_tmp, /<\/blockquote>/)) { _close++; _tmp = substr(_tmp, RSTART + RLENGTH) }
        while (_close < _open) { t = t "</blockquote>"; _close++ }
    }
    # Preserve spoiler spans, remove all other spans
    gsub(/<span[^>]*tg-spoiler[^>]*>/, "<!SPOILER>", t)
    gsub(/<\/?span[^>]*>/, "", t)
    gsub(/<!SPOILER>/, "<span class=\"tg-spoiler\">", t)
    # Ensure spoiler spans are closed
    {
        _open = 0; _close = 0
        _tmp = t
        while (match(_tmp, /<span[^>]*>/)) { _open++; _tmp = substr(_tmp, RSTART + RLENGTH) }
        _tmp = t
        while (match(_tmp, /<\/span>/)) { _close++; _tmp = substr(_tmp, RSTART + RLENGTH) }
        while (_close < _open) { t = t "</span>"; _close++ }
    }
    # Ensure pre tags are closed
    {
        _open = 0; _close = 0
        _tmp = t
        while (match(_tmp, /<pre[^>]*>/)) { _open++; _tmp = substr(_tmp, RSTART + RLENGTH) }
        _tmp = t
        while (match(_tmp, /<\/pre>/)) { _close++; _tmp = substr(_tmp, RSTART + RLENGTH) }
        while (_close < _open) { t = t "</pre>"; _close++ }
    }
    # Clean leftover attrs except href and class
    gsub(/ style="[^"]*"/, "", t)
    gsub(/ dir="[^"]*"/, "", t)
    # Normalize whitespace
    gsub(/[[:space:]]+/, " ", t)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    return t
}

/data-post=/ {
    if (id != "") {
        text = clean_text(text)
        gsub(/[[:space:]]/, "", views)
        if (reactions == 0) reactions = ""
        print id, date, views, reactions, fwd_from, fwd_link, text, media_url
    }
    id = ""; date = ""; views = ""; text = ""; reactions = 0; fwd_from = ""; fwd_link = ""; media_url = ""; in_text = 0
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

# Multi-line text capture: start collecting when we see tgme_widget_message_text
id != "" && /tgme_widget_message_text/ && text == "" && in_text == 0 {
    in_text = 1
    tmp = $0
    sub(/.*tgme_widget_message_text[^>]*>/, "", tmp)
    # Check if closing </div> is on the same line
    if (tmp ~ /<\/div>/) {
        sub(/<\/div>.*/, "", tmp)
        text = tmp
        in_text = 0
    } else {
        text = tmp
    }
    next
}

# Continue collecting text lines until closing </div>
in_text == 1 {
    tmp = $0
    if (tmp ~ /<\/div>/) {
        sub(/<\/div>.*/, "", tmp)
        text = text " " tmp
        in_text = 0
    } else {
        text = text " " tmp
    }
    next
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
        text = clean_text(text)
        gsub(/[[:space:]]/, "", views)
        if (reactions == 0) reactions = ""
        print id, date, views, reactions, fwd_from, fwd_link, text, media_url
    }
}
