#!/usr/bin/env python3
"""Local Shelf metadata and standard GNOME thumbnails, streamed as JSON lines."""
import json
import os
from pathlib import Path
import sys
import threading
import time
from urllib.parse import unquote, urlsplit

_icon_theme = None

def file_icon(names):
    global _icon_theme
    try:
        import gi
        gi.require_version('Gtk', '4.0')
        from gi.repository import Gtk
        if _icon_theme is None:
            _icon_theme = Gtk.IconTheme.new()
            _icon_theme.set_theme_name('Adwaita')
        for name in names:
            if not _icon_theme.has_icon(name):
                continue
            icon = _icon_theme.lookup_icon(name, [], 64, 1, Gtk.TextDirection.NONE, Gtk.IconLookupFlags.PRELOAD)
            file = icon.get_file()
            if file and file.get_path():
                return {'iconSource': file.get_uri(), 'iconSymbolic': name.endswith('-symbolic')}
    except (ImportError, ValueError, RuntimeError):
        pass
    return {}

def file_path(uri):
    parsed = urlsplit(uri)
    if parsed.scheme != 'file' or parsed.netloc.lower() not in ('', 'localhost') or parsed.query or parsed.fragment:
        raise ValueError('Only local file URIs are supported')
    path = unquote(parsed.path, errors='strict')
    if not path.startswith('/') or any(ord(c) < 32 for c in path):
        raise ValueError('Invalid file URI')
    return path

def metadata(uri):
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio
    try:
        path = file_path(uri)
        info = Gio.File.new_for_path(path).query_info(
            'standard::type,standard::content-type,standard::icon,standard::size,time::modified', Gio.FileQueryInfoFlags.NONE, None)
        folder = info.get_file_type() == Gio.FileType.DIRECTORY
        mime = info.get_content_type() or 'application/octet-stream'
        icon = info.get_icon()
        names = list(icon.get_names()) if isinstance(icon, Gio.ThemedIcon) else []
        size = {} if folder else {'size': info.get_size()}
        return {'uri': uri, 'available': True, 'folder': folder, 'mimeType': mime, **size,
                'iconNames': names, 'mtime': info.get_attribute_uint64('time::modified'), 'thumbnail': '', **file_icon(names)}
    except Exception:
        return {'uri': uri, 'available': False, 'iconNames': ['text-x-generic'], 'thumbnail': '', **file_icon(['text-x-generic'])}

def thumbnail(item, factory):
    if not item['available'] or item.get('folder') or factory is None:
        return ''
    from gi.repository import Gio, GdkPixbuf
    uri, mtime = item['uri'], item['mtime']
    path = factory.lookup(uri, mtime)
    if path:
        return Path(path).as_uri()
    cancellable = Gio.Cancellable()
    deadline = threading.Timer(2, cancellable.cancel)
    deadline.start()
    try:
        pixbuf = factory.generate_thumbnail(uri, item['mimeType'], cancellable)
    except Exception:
        pixbuf = None
    finally:
        deadline.cancel()
    if pixbuf is None and item['mimeType'].startswith('image/'):
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(file_path(uri), 256, 256, True)
            pixbuf = pixbuf.apply_embedded_orientation()
        except Exception:
            return ''
    if pixbuf is None:
        return ''
    try:
        factory.save_thumbnail(pixbuf, uri, mtime, None)
        path = factory.lookup(uri, mtime)
        return Path(path).as_uri() if path else ''
    except Exception:
        return ''

def emit(item):
    print(json.dumps(item, ensure_ascii=False), flush=True)

def main():
    raw = sys.stdin.buffer.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise ValueError('Input exceeds limit')
    request = json.loads(raw)
    uris = request.get('uris')
    if not isinstance(uris, list) or len(uris) > 350 or any(not isinstance(u, str) or len(u) > 8192 for u in uris):
        raise ValueError('Invalid file list')
    import gi
    gi.require_version('GdkPixbuf', '2.0')
    try:
        gi.require_version('GnomeDesktop', '4.0')
    except ValueError:
        try:
            gi.require_version('GnomeDesktop', '3.0')
        except ValueError:
            pass
    try:
        from gi.repository import GnomeDesktop
        factory = GnomeDesktop.DesktopThumbnailFactory.new(GnomeDesktop.DesktopThumbnailSize.LARGE)
    except (ImportError, ValueError):
        factory = None
    items = [metadata(uri) for uri in dict.fromkeys(uris)]
    for item in items:
        emit(item)
    deadline = time.monotonic() + 12
    for item in items:
        if time.monotonic() >= deadline:
            break
        source = thumbnail(item, factory)
        if source:
            emit(dict(item, thumbnail=source))

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
