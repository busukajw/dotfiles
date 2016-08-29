export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
# MacPorts Installer addition on 2016-08-09_at_13:16:06: adding an appropriate PATH variable for use with MacPorts.
export PATH="~/bin:/opt/local/bin:/opt/local/sbin:$PATH:/Users/awalker/Library/Python/3.5/bin"
# Finished adapting your PATH environment variable for use with MacPorts.
#adding powerline status magicaroo
powerline-daemon -q
POWERLINE_BASH_CONTINUATION=1
POWERLINE_BASH_SELECT=1
. /Users/awalker/Library/Python/3.5/lib/python/site-packages/powerline/bindings/bash/powerline.sh


export PATH="$PATH:"/Applications/microchip/xc8/v1.38/bin""
alias tma='tmux attach -d -t'
alias git-tmux='tmux new -s $(basename) $(pwd))'

  if [ -f /opt/local/etc/profile.d/bash_completion.sh ]; then
	  . /opt/local/etc/profile.d/bash_completion.sh
  fi
