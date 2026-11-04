#!/bin/sh
# The popup: shows the file at its line with bat. q closes it.
here=$(dirname "$0")
{ read -r path; read -r line; } <<EOT
$(python3 -I "$here/parse.py" "$FV_URL")
EOT
if [ -d "$path" ]; then
  ls -la "$path" | less -R
elif [ -f "$path" ]; then
  if [ -n "$line" ]; then
    bat --paging=always --highlight-line "$line" --pager "less -R -j.3 +${line}g" "$path"
  else
    bat --paging=always --pager "less -R" "$path"
  fi
else
  printf 'Not found: %s\nPress Enter to close.' "$path"; read -r _
fi
