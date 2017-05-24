#adding powerline status magicaroo

actual_path=$( /usr/local/bin/greadlink -f "${BASH_SOURCE}")
#using 2 dirname because we need to also remove the last directory
#to get the base director of the dotfiles
DOTFILES_DIR=$( dirname "$(dirname "${actual_path}")")
for DOTFILE in "$DOTFILES_DIR"/system/.{path,env,alias}
do
	[ -f "$DOTFILE" ] && source $DOTFILE
done

#powerline-daemon -q
#POWERLINE_BASH_CONTINUATION=1
#POWERLINE_BASH_SELECT=1
#. /Users/awalker/Library/Python/3.6/lib/python/site-packages/powerline/bindings/bash/powerline.sh
source /Users/awalker/Documents/gitrepos/liquidprompt/liquidprompt

ssh-add -K

  if [ -f /opt/local/etc/profile.d/bash_completion.sh ]; then
	  . /opt/local/etc/profile.d/bash_completion.sh
  fi

export PATH="$PATH:"/Applications/microchip/xc8/v1.41/bin""
eval "$(rbenv init -)"
