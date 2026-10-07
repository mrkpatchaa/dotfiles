#  ---------------------------------------------------------------------------
#  Description: ZSH Configurations and Aliases
#  Loaded from ~/.zshrc. Private, machine-specific settings go in ~/.zshrc.local (section 11).
#  Order matters: zsh expands aliases inside a function when the function is defined,
#  so a function only sees the aliases defined above it.
#  ---------------------------------------------------------------------------

DOTFILES="${${(%):-%x}:A:h}"   # this repo's folder, wherever it is cloned


#   ---------------------------------------
#   1.  ENVIRONMENT & PATH
#   ---------------------------------------

export PATH="/usr/local/bin:$PATH"
export EDITOR=/usr/bin/vim
export BLOCKSIZE=1k

# Homebrew (on PATH via /etc/paths.d/homebrew); the prefix is the folder holding bin/brew
(( $+commands[brew] )) && HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-${commands[brew]:h:h}}"

# nvm, loaded on first use (sourcing nvm.sh costs ~280 ms). The default Node is on PATH right away.
export NVM_DIR="$HOME/.nvm"
() {
    local want=node
    local -a bin
    [[ -r $NVM_DIR/alias/default ]] && want="$(<$NVM_DIR/alias/default)"
    case $want in
        node|stable) bin=($NVM_DIR/versions/node/v*/bin(Nn[-1])) ;;
        v<->*|<->*)  bin=($NVM_DIR/versions/node/v${want#v}(|.*)/bin(Nn[-1])) ;;
    esac
    if (( $#bin )); then
        export PATH="$bin[1]:$PATH" NVM_BIN="$bin[1]" NVM_INC="${bin[1]:h}/include/node" NVM_CD_FLAGS=-q
        nvm() {
            unset -f nvm
            # --no-use: the default Node is already on PATH, don't add it a second time
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
            nvm "$@"
        }
    else
        # The default isn't a plain version (e.g. lts/*): load nvm now
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    fi
}

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

# Android
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
() { local jh; jh="$(/usr/libexec/java_home -v 21 2>/dev/null)" && export JAVA_HOME="$jh"; }

export PATH=$PATH:$HOME/.maestro/bin              # Maestro
export PATH=$PATH:$HOME/.local/bin                # Claude Code
export PATH=$HOME/.opencode/bin:$PATH             # opencode


#   ---------------------------------------
#   2.  HISTORY
#   ---------------------------------------

export HISTFILE=~/.zsh_history
export HISTSIZE=10000000         # entries kept in memory
SAVEHIST=10000000                # entries kept in the file (macOS's /etc/zshrc sets 1000)

setopt BANG_HIST                 # Treat the '!' character specially during expansion
setopt EXTENDED_HISTORY          # Write the history file in the ":start:elapsed;command" format
setopt INC_APPEND_HISTORY        # Write to the history file immediately, not when the shell exits
setopt SHARE_HISTORY             # Share history between all sessions natively (Replaces PROMPT_COMMAND)
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicate entries first when trimming history
setopt HIST_IGNORE_DUPS          # Don't record an entry that was just recorded again
setopt HIST_IGNORE_ALL_DUPS      # Delete old recorded entry if new entry is a duplicate
setopt HIST_FIND_NO_DUPS         # Do not display a line previously found
setopt HIST_IGNORE_SPACE         # Don't record an entry starting with a space
setopt HIST_SAVE_NO_DUPS         # Don't write duplicate entries in the history file
setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks before recording entry
setopt HIST_VERIFY               # Don't execute immediately upon history expansion

# To remove any command from the zsh history file
histrm() { LC_ALL=C sed -i '' "/$1/d" $HISTFILE }
dedupHistory() {
    cp ~/.zsh_history{,-old}
    awk -F ";" '!seen[$2]++' ~/.zsh_history > /tmp/zsh_hist_tmp && mv /tmp/zsh_hist_tmp ~/.zsh_history
}


#   ---------------------------------------
#   3.  COMPLETION & KEY BINDINGS (replaces .inputrc)
#   ---------------------------------------

# Map Up and Down arrows to search history based on what you already typed
# (history-search-* only matches the first word; *-line-or-beginning-search
# matches everything left of the cursor, like readline's history-search-*)
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
# Same keys when the terminal is in application cursor mode
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

# Homebrew completions (must be on fpath before compinit)
[ -n "$HOMEBREW_PREFIX" ] && FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:$FPATH"

# Initialize the advanced completion system
autoload -Uz compinit && compinit

# Make tab-completion case-insensitive
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Use a visual menu to cycle through possible tab completions
zstyle ':completion:*' menu select

# Mole completion, cached (generating it costs ~140 ms) and regenerated when mole is updated
if (( $+commands[mole] )); then
    () {
        local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/mole-completion.zsh"
        if [[ ! -s $cache || ${commands[mole]:A} -nt $cache ]]; then
            command mkdir -p "${cache:h}"
            if mole completion zsh >| "$cache.tmp" 2>/dev/null; then command mv -f "$cache.tmp" "$cache"; else command rm -f "$cache.tmp"; fi
        fi
        [[ -s $cache ]] && source "$cache"
    }
fi

# Option+Left / Option+Right jump a word (iTerm2 with Option = Normal, iTerm2 with Option = Esc+, Terminal.app)
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[^[[D' backward-word
bindkey '^[^[[C' forward-word
bindkey '^[b' backward-word
bindkey '^[f' forward-word
bindkey "^[a" beginning-of-line
bindkey "^[e" end-of-line


#   ---------------------------------------
#   4.  MODERN CLI REPLACEMENTS
#   ---------------------------------------

# eza (replaces ls)
alias ls='eza --icons --git'          # Standard list with icons and git status
alias ll='eza -lh --icons --git'      # Long format, human-readable sizes
alias la='eza -lah --icons --git'     # Long format including hidden files
alias tree='eza --tree --icons'       # Directory tree view
[[ -o interactive ]] && cd() { builtin cd "$@" && ll; }   # List directory contents upon 'cd' (interactive only: eza hangs in scripts)

# bat (replaces cat)
alias cat='bat'

# bottom (replaces top/htop)
alias top='btm'

# dust and duf (replaces du and df)
alias du='dust'
alias df='duf'


#   ---------------------------------------
#   5.  SHELL, NAVIGATION & FILES
#   ---------------------------------------

alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -i'
alias mkdir='mkdir -pv'
alias less='less -FSRXc'

# Shell
alias c='clear'
alias which='type -a'
alias path='echo -e ${PATH//:/\\n}'
alias fix_stty='stty sane'                  # Restore terminal settings when screwed up
alias reload='source ~/.zshrc'              # reloads the prompt
alias cic='setopt NO_CASE_GLOB'             # Make ZSH globbing case-insensitive
alias suroot='sudo -E -s'
alias edit='subl'                           # Opens any file in sublime editor
alias zshconfig='vim $DOTFILES/.zshrc'      # Edit the shared config (private settings: ~/.zshrc.local)

# Remind yourself of an alias (searches the shared and the private config)
showa () { grep --color=always -i -a1 "$@" $DOTFILES/.zshrc $DOTFILES/claude/aliases.zsh ~/.zshrc.local | grep -v '^\s*$' | less -FSRXc ; }

# Search manpage (e.g., mans mplayer codec)
mans () { man $1 | grep -iC2 --color=always $2 | less }

# Weather (Modernized from old Accuweather RSS)
alias weather='curl -s "wttr.in/?format=3"'

# Navigation
alias ..='cd ../'
alias ...='cd ../../'
alias .3='cd ../../../'
alias .4='cd ../../../../'
mcd () { mkdir -p "$1" && cd "$1"; }        # Makes new Dir and jumps inside
alias lsh='ls -ld .??*'                     # only show dot files

# Full Recursive Directory Listing
alias lr='command ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less'

# Files
zipf () { zip -r "$1".zip "$1" ; }
alias numFiles='echo $(ls -1 | wc -l)'
alias make1mb='mkfile 1m ./1MB.dat'

# Extract most known archives
extract () {
    if [ -f $1 ] ; then
      case $1 in
        *.tar.bz2|*.tbz2) tar xjf $1     ;;
        *.tar.gz|*.tgz)   tar xzf $1     ;;
        *.bz2)            bunzip2 $1     ;;
        *.rar)            unrar e $1     ;;
        *.gz)             gunzip $1      ;;
        *.tar)            tar xf $1      ;;
        *.zip)            unzip $1       ;;
        *.Z)              uncompress $1  ;;
        *.7z)             7z x $1        ;;
        *) echo "'$1' cannot be extracted via extract()" ;;
      esac
    else
      echo "'$1' is not a valid file"
    fi
}

gzipsize() { echo $((`gzip -c $1 | wc -c`/1024))"KB" }
rename() { for i in $1*; do mv "$i" "${i/$1/$2}"; done }


#   ---------------------------------------
#   6.  SEARCHING
#   ---------------------------------------

alias qfind="find . -name "
ffs () { find . -name "$@"'*' ; }
ffe () { find . -name '*'"$@" ; }
spotlight () { mdfind "kMDItemDisplayName == '$@'wc"; }

# Find file under current dir, ignoring common cache dirs
ff () { find . -iname "*$1*" -not -path "*/node_modules/*" -not -path "*/.git/*" }

# Find in files
fif () {
    if [ "$#" -eq 1 ]; then
        grep -nr "$1" . --color
    else
        sed -n "${2}p" $(grep -nr "$1" . | cut -d: -f-2)
    fi
}


#   ---------------------------------------
#   7.  PROCESSES & NETWORK
#   ---------------------------------------

# `command top` = macOS top (plain `top` is btm, see section 4)
findPid () { lsof -t -c "$@" ; }
alias memHogsTop='command top -l 1 -o rsize | head -20'
alias memHogsPs='ps wwaxm -o pid,stat,vsize,rss,time,command | head -10'
alias cpu_hogs='ps wwaxr -o pid,stat,%cpu,time,command | head -10'
alias topForever='command top -l 9999999 -s 10 -o cpu'
alias ttop="command top -R -F -s 10 -o rsize"
my_ps() { ps $@ -u $USER -o pid,%cpu,%mem,start,time,bsdtime,command ; }

alias myip='curl ifconfig.me'                       # Modernized public IP check
alias localip="ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'"
alias netCons='lsof -i'
alias flushDNS='dscacheutil -flushcache; sudo killall -HUP mDNSResponder' # Updated for modern macOS
alias lsock='sudo /usr/sbin/lsof -i -P'
alias lsockU='sudo /usr/sbin/lsof -nP | grep UDP'
alias lsockT='sudo /usr/sbin/lsof -nP | grep TCP'
alias openPorts='sudo lsof -i | grep LISTEN'

ii() {
    echo -e "\nYou are logged on $HOST"
    echo -e "\nAdditionnal information: " ; uname -a
    echo -e "\nUsers logged on: " ; w -h
    echo -e "\nCurrent date : " ; date
    echo -e "\nMachine stats : " ; uptime
    echo -e "\nPublic facing IP Address : " ; myip
    echo
}

#   rdp: Open the Windows RDP profile, filling host/user from RDP_HOST / RDP_USER (set them in ~/.zshrc.local)
#   Usage: rdp            or   RDP_HOST=other-pc rdp
rdp() {
    local tpl="$DOTFILES/rdp/windows.rdp.template"
    [ -n "$RDP_HOST" ] || { echo "rdp: set RDP_HOST (and RDP_USER) in ~/.zshrc.local" >&2; return 1; }
    local out="${TMPDIR:-/tmp}/${RDP_HOST}.rdp"
    local esc='s/[\\&|]/\\&/g'   # escape sed replacement chars (DOMAIN\user has a backslash)
    sed -e "s|{{RDP_HOST}}|$(printf '%s' "$RDP_HOST" | sed "$esc")|" \
        -e "s|{{RDP_USER}}|$(printf '%s' "$RDP_USER" | sed "$esc")|" "$tpl" > "$out" && open "$out"
}


#   ---------------------------------------
#   8.  MACOS
#   ---------------------------------------

alias f='open -a Finder ./'                 # Opens current directory in MacOS Finder
ql () { qlmanage -p "$*" >& /dev/null; }    # Opens any file in MacOS Quicklook Preview
trash () { command mv "$@" ~/.Trash ; }     # Moves a file to the MacOS trash
alias dodo='pmset sleepnow'                 # puts computer to sleep immediately

# Cd's to frontmost window of MacOS Finder
cdf () {
    currFolderPath=$( /usr/bin/osascript <<EOT
        tell application "Finder"
            try
        set currFolder to (folder of the front window as alias)
            on error
        set currFolder to (path to desktop folder as alias)
            end try
            POSIX path of currFolder
        end tell
EOT
    )
    echo "cd to \"$currFolderPath\""
    cd "$currFolderPath"
}

alias restartdock="killall -KILL Dock"
alias cleanupDS="find . -type f -name '*.DS_Store' -ls -delete && find . -type d -name '__MACOSX' -ls -delete"
alias finderShowHidden='defaults write com.apple.Finder AppleShowAllFiles YES; killall Finder'
alias finderHideHidden='defaults write com.apple.Finder AppleShowAllFiles NO; killall Finder'
alias finderHideDesktop='defaults write com.apple.Finder CreateDesktop false; killall Finder'
alias finderShowDesktop='defaults write com.apple.Finder CreateDesktop true; killall Finder'
alias cleanupLS="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"

# One-time setting (it persists, so it doesn't need to run on every shell start). On a new Mac:
#   defaults write com.apple.screencapture disable-shadow -bool true   # no shadow on screenshots


#   ---------------------------------------
#   9.  DEV TOOLS
#   ---------------------------------------

alias devs='cd ~/devs'

# Git
function gitexport(){
    mkdir -p "$1"
    git archive HEAD | tar -x -C "$1"
}
function gitcleanbranches(){
    git branch --merged | egrep -v "(^\*|master|dev|develop|main)" | xargs git branch -D
    git remote prune origin
}
alias git-list-untracked='git fetch --prune && git branch -r | awk "{print \$1}" | egrep -v -f /dev/fd/0 <(git branch -vv | grep origin) | awk "{print \$1}"'
alias git-remove-untracked='git-list-untracked | xargs git branch -d'
alias git-remove-untracked-f='git-list-untracked | xargs git branch -D'
alias lg='lazygit'

# Docker
docker-ip() { docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@" }
alias docker-cleanup='docker system prune -af --volumes' # Modernized docker cleanup
alias lzd='lazydocker'

# Node & Xcode
alias cleannode="find . -name 'node_modules' -type d -prune -print -exec rm -rf '{}' + && find . -name 'package-lock.json' -type f -prune -print -exec rm -rf '{}' +"
alias cleanupXcode="rm -rf ~/Library/Developer/Xcode/DerivedData/* && rm -rf ~/Library/Caches/com.apple.dt.Xcode"
alias cleanupAll="cleanupXcode && yarn cache clean --all"

# HTTP
httpHeaders () { curl -I -L "$@" ; }
httpDebug () { curl "$@" -o /dev/null -w "dns: %{time_namelookup} connect: %{time_connect} pretransfer: %{time_pretransfer} starttransfer: %{time_starttransfer} total: %{time_total}\n" ; }

# Supabase: per-project access tokens live in the macOS Keychain (service "supabase-token-<name>"),
# and each project gets a `supabase-<name>` alias in ~/.zshrc.local
_sb() { SUPABASE_ACCESS_TOKEN="$(security find-generic-password -a "$USER" -s "$1" -w)" supabase "${@:2}"; }

# Store a token in the Keychain and create its alias (e.g. supabase-token-add myapp -> supabase-myapp)
function supabase-token-add() {
    local name="$1" svc="supabase-token-$1" rc="$HOME/.zshrc.local" token
    [[ -n "$name" && "$name" != *[^a-z0-9-]* ]] || { echo "usage: supabase-token-add <name>   (a-z, 0-9, -)" >&2; return 1; }
    if security find-generic-password -a "$USER" -s "$svc" >/dev/null 2>&1; then
        read -q "?A token for '$name' already exists. Replace it? [y/N] " || { echo; return 1; }
        echo
    fi
    read -rs "token?Paste the access token for '$name' (input hidden): "; echo
    [[ "$token" == sbp_* && "$token" != *[^A-Za-z0-9_]* ]] || { echo "That doesn't look like a Supabase access token (sbp_...)" >&2; return 1; }
    # Sent through stdin, so the token never shows up in the process list
    printf 'add-generic-password -U -a "%s" -s "%s" -l "Supabase access token (%s)" -w "%s"\n' \
        "$USER" "$svc" "$name" "$token" | security -i >/dev/null
    [[ "$(security find-generic-password -a "$USER" -s "$svc" -w 2>/dev/null)" == "$token" ]] || { echo "Saving to the Keychain failed" >&2; return 1; }
    local line="alias supabase-$name='_sb $svc'"
    grep -qxF "$line" "$rc" 2>/dev/null || print -r -- "$line" >> "$rc"
    alias "supabase-$name=_sb $svc"
    echo "Saved. Use it with: supabase-$name <command>"
}

# Generate SSH Key
function sshKeyGen(){
    read "?What's the name of the Key (no spaces please)? " name
    read "?What's the email associated with it? " email
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_$name -C "$email"
    ssh-add ~/.ssh/id_ed25519_$name
    pbcopy < ~/.ssh/id_ed25519_$name.pub
    echo "SSH Key copied in your clipboard"
}

# Generate a random password (Modernized to one-liner)
function randpasswd() {
    openssl rand -base64 "${1:-12}"
}

# Compress PDF
function compress_pdf() {
  docker run --rm -ti \
  -v "$PWD":/work \
  --workdir /work \
  jess/ghostscript \
  -sDEVICE=pdfwrite \
  -dCompatibilityLevel=1.4 \
  -dQUIET \
  -q -dNOPAUSE -dBATCH -dSAFER \
  -dPDFSETTINGS=/screen \
  -dEmbedAllFonts=true \
  -dSubsetFonts=true \
  -dAutoRotatePages=/None \
  -dColorImageDownsampleType=/Bicubic \
  -dColorImageResolution=300 \
  -dGrayImageDownsampleType=/Bicubic \
  -dGrayImageResolution=300 \
  -dMonoImageDownsampleType=/Bicubic \
  -dMonoImageResolution=300 \
  -sOutputFile="${1%%.*}_small.pdf" \
  "$1"
}


#   ---------------------------------------
#   10. AI LOOP (launch aliases + helper scripts on PATH)
#   ---------------------------------------

[ -f "$DOTFILES/claude/aliases.zsh" ] && source "$DOTFILES/claude/aliases.zsh"


#   ---------------------------------------
#   11. LOCAL OVERRIDES
#   ---------------------------------------

# Machine-specific, untracked settings: RDP_HOST / RDP_USER for `rdp`, supabase-<name> aliases,
# AI workflow model lists (GRUNT_MODELS, REVIEW_FALLBACK_MODELS, OPENCODE_FREE_MODELS…)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"


#   ---------------------------------------
#   12. PROMPT & PLUGINS (keep this section last)
#   ---------------------------------------

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
command -v starship >/dev/null && eval "$(starship init zsh)"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

if [ -n "$HOMEBREW_PREFIX" ]; then
    _p="$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"; [ -f "$_p" ] && source "$_p"
    # Syntax highlighting must be the last thing loaded
    _p="$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"; [ -f "$_p" ] && source "$_p"
    unset _p
fi
