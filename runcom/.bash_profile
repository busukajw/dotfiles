#adding powerline status magicaroo

for DOTFILE in "$DOTFILES_DIR"/system/.{path,env,alias}
do
	[ -f "$DOTFILE" ] && source $DOTFILE
done

powerline-daemon -q
POWERLINE_BASH_CONTINUATION=1
POWERLINE_BASH_SELECT=1
. /Users/awalker/Library/Python/3.5/lib/python/site-packages/powerline/bindings/bash/powerline.sh


  if [ -f /opt/local/etc/profile.d/bash_completion.sh ]; then
	  . /opt/local/etc/profile.d/bash_completion.sh
  fi
