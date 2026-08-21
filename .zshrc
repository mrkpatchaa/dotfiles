#  ---------------------------------------------------------------------------
#  Description: ZSH Configurations and Aliases
#  ---------------------------------------------------------------------------

#   -------------------------------
#   1.  ENVIRONMENT CONFIGURATION
#   -------------------------------

export PATH="/usr/local/git/bin:/sw/bin:/usr/local/bin:/usr/local/sbin:/usr/local/mysql/bin:/opt/local/bin:$PATH:$HOME/.composer/vendor/bin"
export EDITOR=/usr/bin/vim
export BLOCKSIZE=1k

# ZSH specific configurations
ZSH_DISABLE_COMPFIX=true
ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"

# History Configuration (Zsh Native)
export HISTFILE=~/.zsh_history
export HISTSIZE=10000000
export HISTFILESIZE=10000000
export HISTTIMEFORMAT='%F %T '

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


#   -----------------------------
#   2.  MAKE TERMINAL BETTER
#   -----------------------------

alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -i'
alias lsh='ls -ld .??*'                     # only show dot files
alias mkdir='mkdir -pv'
alias ll='ls -FGlAhp'
alias less='less -FSRXc'
cd() { builtin cd "$@"; ll; }               # Always list directory contents upon 'cd'

# Navigation
alias ..='cd ../'
alias ...='cd ../../'
alias .3='cd ../../../'
alias .4='cd ../../../../'

# General Utilities
alias edit='subl'                           # Opens any file in sublime editor
alias f='open -a Finder ./'                 # Opens current directory in MacOS Finder
alias c='clear'
alias which='type -a'
alias path='echo -e ${PATH//:/\\n}'
alias fix_stty='stty sane'                  # Restore terminal settings when screwed up
alias dodo='pmset sleepnow'                 # puts computer to sleep immediately
alias reload='source ~/.zshrc'              # reloads the prompt
alias cic='setopt NO_CASE_GLOB'             # Make ZSH globbing case-insensitive
mcd () { mkdir -p "$1" && cd "$1"; }        # Makes new Dir and jumps inside
trash () { command mv "$@" ~/.Trash ; }     # Moves a file to the MacOS trash
ql () { qlmanage -p "$*" >& /dev/null; }    # Opens any file in MacOS Quicklook Preview
alias suroot='sudo -E -s'

# Full Recursive Directory Listing
alias lr='ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less'

# Search manpage (e.g., mans mplayer codec)
mans () { man $1 | grep -iC2 --color=always $2 | less }

# Remind yourself of an alias
showa () { grep --color=always -i -a1 "$@" ~/.zshrc | grep -v '^\s*$' | less -FSRXc ; }

# Weather (Modernized from old Accuweather RSS)
alias weather='curl -s "wttr.in/?format=3"'

# ---------------------------------------------------------------------------
# ZLE KEYBINDINGS & COMPLETION (Replaces .inputrc)
# ---------------------------------------------------------------------------

# Map Up and Down arrows to search history based on what you already typed
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Initialize the advanced completion system
autoload -Uz compinit && compinit

# Make tab-completion case-insensitive
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Use a visual menu to cycle through possible tab completions
zstyle ':completion:*' menu select

# (Standard Zsh bindings)
bindkey "[D" backward-word
bindkey "[C" forward-word
bindkey "^[a" beginning-of-line
bindkey "^[e" end-of-line


#   -------------------------------
#   3.  FILE AND FOLDER MANAGEMENT
#   -------------------------------

zipf () { zip -r "$1".zip "$1" ; }
alias numFiles='echo $(ls -1 | wc -l)'
alias make1mb='mkfile 1m ./1MB.dat'

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


#   ---------------------------
#   4.  SEARCHING
#   ---------------------------

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


# ---------------------------------------------------------------------------
# MODERN CLI REPLACEMENTS
# ---------------------------------------------------------------------------

# eza (replaces ls)
alias ls='eza --icons --git'          # Standard list with icons and git status
alias ll='eza -lh --icons --git'      # Long format, human-readable sizes
alias la='eza -lah --icons --git'     # Long format including hidden files
alias tree='eza --tree --icons'       # Directory tree view

# bat (replaces cat)
alias cat='bat'

# bottom (replaces top/htop)
alias top='btm'

# dust and duf (replaces du and df)
alias du='dust'
alias df='duf'

#   ---------------------------
#   5.  PROCESS MANAGEMENT
#   ---------------------------

findPid () { lsof -t -c "$@" ; }
alias memHogsTop='top -l 1 -o rsize | head -20'
alias memHogsPs='ps wwaxm -o pid,stat,vsize,rss,time,command | head -10'
alias cpu_hogs='ps wwaxr -o pid,stat,%cpu,time,command | head -10'
alias topForever='top -l 9999999 -s 10 -o cpu'
alias ttop="top -R -F -s 10 -o rsize"
my_ps() { ps $@ -u $USER -o pid,%cpu,%mem,start,time,bsdtime,command ; }


#   ---------------------------
#   6.  NETWORKING
#   ---------------------------

alias myip='curl ifconfig.me'                       # Modernized public IP check
alias localip="ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'"
alias netCons='lsof -i'
alias flushDNS='dscacheutil -flushcache; sudo killall -HUP mDNSResponder' # Updated for modern macOS
alias lsock='sudo /usr/sbin/lsof -i -P'
alias lsockU='sudo /usr/sbin/lsof -nP | grep UDP'
alias lsockT='sudo /usr/sbin/lsof -nP | grep TCP'
alias openPorts='sudo lsof -i | grep LISTEN'
alias showBlocked='sudo ipfw list'

ii() {
    echo -e "\nYou are logged on $HOST"
    echo -e "\nAdditionnal information: " ; uname -a
    echo -e "\nUsers logged on: " ; w -h
    echo -e "\nCurrent date : " ; date
    echo -e "\nMachine stats : " ; uptime
    echo -e "\nPublic facing IP Address : " ; myip
    echo
}


#   ---------------------------------------
#   7.  SYSTEMS OPERATIONS & INFORMATION
#   ---------------------------------------

alias restartdock="killall -KILL Dock"
alias mountReadWrite='/sbin/mount -uw /'
alias cleanupDS="find . -type f -name '*.DS_Store' -ls -delete && find . -type d -name '__MACOSX' -ls -delete"
alias finderShowHidden='defaults write com.apple.Finder AppleShowAllFiles YES; killall Finder'
alias finderHideHidden='defaults write com.apple.Finder AppleShowAllFiles NO; killall Finder'
alias finderHideDesktop='defaults write com.apple.Finder CreateDesktop false; killall Finder'
alias finderShowDesktop='defaults write com.apple.Finder CreateDesktop true; killall Finder'
alias cleanupLS="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"

# Disable shadow on screenshots
defaults write com.apple.screencapture disable-shadow -bool true


#   ---------------------------------------
#   8.  WEB DEVELOPMENT
#   ---------------------------------------

httpHeaders () { curl -I -L "$@" ; }
httpDebug () { curl "$@" -o /dev/null -w "dns: %{time_namelookup} connect: %{time_connect} pretransfer: %{time_pretransfer} starttransfer: %{time_starttransfer} total: %{time_total}\n" ; }


#   ---------------------------------------
#   9.  DEV TOOLS
#   ---------------------------------------

alias devs='cd ~/devs'

# Docker 
docker-ip() { docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@" }
alias docker-cleanup='docker system prune -af --volumes' # Modernized docker cleanup

# Node & JS
alias cleannode="find . -name 'node_modules' -type d -prune -print -exec rm -rf '{}' + && find . -name 'package-lock.json' -type f -prune -print -exec rm -rf '{}' +"
alias cleanupXcode="rm -rf ~/Library/Developer/Xcode/DerivedData/* && rm -rf ~/Library/Caches/com.apple.dt.Xcode"
alias cleanupAll="cleanupXcode && yarn cache clean --all"

# Git Helpers
function gitexport(){
    mkdir -p "$1"
    git archive master | tar -x -C "$1"
}
function gitcleanbranches(){
    git branch --merged | egrep -v "(^\*|master|dev|develop|main)" | xargs git branch -D
    git remote prune origin
}
alias git-list-untracked='git fetch --prune && git branch -r | awk "{print \$1}" | egrep -v -f /dev/fd/0 <(git branch -vv | grep origin) | awk "{print \$1}"'
alias git-remove-untracked='git-list-untracked | xargs git branch -d'
alias git-remove-untracked-f='git-list-untracked | xargs git branch -D'
alias lg='lazygit'

# Generate SSH Key
function sshKeyGen(){
    read "?What's the name of the Key (no spaces please)? " name
    read "?What's the email associated with it? " email
    ssh-keygen -t rsa -f ~/.ssh/id_rsa_$name -C "$email"
    ssh-add ~/.ssh/id_rsa_$name
    pbcopy < ~/.ssh/id_rsa_$name.pub
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

# # Auto-load NVM 
# autoload -U add-zsh-hook
# load-nvmrc() {
#   local node_version="$(nvm version)"
#   local nvmrc_path="$(nvm_find_nvmrc)"

#   if [ -n "$nvmrc_path" ]; then
#     local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

#     if [ "$nvmrc_node_version" = "N/A" ]; then
#       nvm install
#     elif [ "$nvmrc_node_version" != "$node_version" ]; then
#       nvm use
#     fi
#   elif [ "$node_version" != "$(nvm version default)" ]; then
#     echo "Reverting to nvm default version"
#     nvm use default
#   fi
# }
# add-zsh-hook chpwd load-nvmrc
# load-nvmrc
