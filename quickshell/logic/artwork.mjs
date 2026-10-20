function safeArtworkUrl(value) {
    if (typeof value !== "string" || !value.trim()) return "";
    var text = value.trim();
    if (/^https?:\/\/[^/?#]+(?:[/?#]|$)/i.test(text) && !/^https?:\/\/[^/?#]*@/i.test(text)) return text;
    return /^file:\/\/(?:localhost)?\/(?!\/)(?:[^?#]*)$/i.test(text) ? text : "";
}

function hostIs(host, domain) { return host === domain || host.endsWith("." + domain); }

export function coverAccent(colors) {
    var clusters = {};
    for (var i = 0; colors && i < colors.length; i++) {
        var color = colors[i];
        var r = Number(color.r), g = Number(color.g), b = Number(color.b);
        if (![r, g, b].every(Number.isFinite) || Number(color.a) < 0.5) continue;
        var max = Math.max(r, g, b), min = Math.min(r, g, b);
        var chroma = max - min;
        var luminance = r * 0.299 + g * 0.587 + b * 0.114;
        if (luminance < 20 / 255 || luminance > 242 / 255 || chroma < 18 / 255) continue;
        var hue = max === r ? ((g - b) / chroma) % 6
            : max === g ? (b - r) / chroma + 2 : (r - g) / chroma + 4;
        hue = (Math.round(hue * 60) + 360) % 360;
        var bucket = Math.floor(hue / 20);
        var cluster = clusters[bucket] || { count: 0, r: 0, g: 0, b: 0, chroma: 0, hue: 0 };
        cluster.count++; cluster.r += r; cluster.g += g; cluster.b += b;
        cluster.chroma += chroma; cluster.hue += hue;
        clusters[bucket] = cluster;
    }
    var best = null, bestScore = 0;
    Object.keys(clusters).forEach(function(key) {
        var cluster = clusters[key];
        var score = cluster.count * Math.pow(cluster.chroma / cluster.count, 1.35);
        if (score > bestScore) { best = cluster; bestScore = score; }
    });
    if (!best) return null;
    var max = Math.max(best.r, best.g, best.b) / best.count;
    var min = Math.min(best.r, best.g, best.b) / best.count;
    var lightness = (max + min) / 2;
    var saturation = lightness <= 0 || lightness >= 1 ? 0
        : (max - min) / (1 - Math.abs(2 * lightness - 1));
    return { hue: best.hue / best.count / 360, saturation: Math.min(0.38, saturation * 0.55), lightness: 0.64 };
}

export function artworkRequestIsCurrent(currentGeneration, requestGeneration, currentKey, requestKey) {
    return Number.isSafeInteger(currentGeneration) && Number.isSafeInteger(requestGeneration)
        && currentGeneration === requestGeneration && currentKey === requestKey;
}

export function resolveArtwork(artUrl, mediaUrl, playerName) {
    var urls = [];
    var art = safeArtworkUrl(artUrl);
    if (art) urls.push(art);
    var parsed = typeof mediaUrl === "string" ? /^(https?):\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?(?:#.*)?$/i.exec(mediaUrl.trim()) : null;
    var host = parsed && !parsed[2].includes("@") ? parsed[2].toLowerCase().replace(/:\d+$/, "").replace(/\.$/, "") : "";
    if (host && /[^a-z0-9.-]/.test(host)) host = "";
    if (parsed && (hostIs(host, "youtube.com") || host === "youtu.be")) {
        var path = parsed[3] || "/";
        var segments = path.split("/").filter(Boolean);
        var id = host === "youtu.be" ? segments[0] :
            path === "/watch" ? ((parsed[4] || "").split("&").map(function(part) { return part.split("="); }).filter(function(part) { return part[0] === "v"; })[0] || [])[1] :
            ["shorts", "embed", "live", "v"].indexOf(segments[0]) >= 0 ? segments[1] : "";
        if (/^[A-Za-z0-9_-]{11}$/.test(id || "")) urls.push("https://i.ytimg.com/vi/" + id + "/hqdefault.jpg");
    }
    var name = String(playerName || "").toLowerCase().replace(/^org\.mpris\.mediaplayer2\./, "");
    var mark = hostIs(host, "youtube.com") || host === "youtu.be" || /^youtube(?:[-_.]|$)/.test(name)
        ? "youtube" : hostIs(host, "instagram.com") || /^instagram(?:[-_.]|$)/.test(name) ? "instagram" : "";
    var clean = [];
    urls.forEach(function(item) { if (clean.indexOf(item) < 0) clean.push(item); });
    return { urls: clean, mark: mark };
}

export function formatPlayerName(raw) {
    var lower = String(raw || "").toLowerCase().replace(/^org\.mpris\.mediaplayer2\./, "");
    var names = [["spotify", "Spotify"], ["telegram", "Telegram"], ["firefox", "Firefox"],
        ["chrome", "Chrome"], ["chromium", "Chromium"], ["cider", "Cider"],
        ["vlc", "VLC"], ["mpv", "MPV"], ["apple", "Apple Music"]];
    for (var i = 0; i < names.length; i++) if (lower.indexOf(names[i][0]) >= 0) return names[i][1];
    return String(raw || "").replace(/[-_.]/g, " ").replace(/\b\w/g, function(c) { return c.toUpperCase(); });
}
