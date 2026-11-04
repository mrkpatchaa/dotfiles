# file:///abs/path#L9, file:///abs/path:9 or file://host/abs/path -> "path\nline"
import os, re, sys
from urllib.parse import urlsplit, unquote
u = urlsplit(sys.argv[1] if len(sys.argv) > 1 else "")
path, line = unquote(u.path), ""
m = re.fullmatch(r"L?(\d+)(?:-L?\d+)?", u.fragment or "")
if m:
    line = m.group(1)
if not os.path.exists(path):
    m = re.fullmatch(r"(.+?):(\d+)(?::\d+)?", path)
    if m:
        path, line = m.group(1), m.group(2)
print(path)
print(line)
