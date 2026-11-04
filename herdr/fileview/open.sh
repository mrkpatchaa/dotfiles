#!/bin/sh
# Runs on a Ctrl+click of a file:// link. Opens the viewer popup on that link.
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin mrk.fileview --entrypoint view --env "FV_URL=$HERDR_PLUGIN_CLICKED_URL"
