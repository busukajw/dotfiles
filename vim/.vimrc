set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
"
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" The following are examples of different formats supported.
" Keep Plugin commands between vundle#begin/end.
" plugin on GitHub repo
Plugin 'tpope/vim-fugitive'
" plugin from http://vim-scripts.org/vim/scripts.html
" Git plugin not hosted on GitHub
"Plugin 'git://git.wincent.com/command-t.git'
" The sparkup vim script is in a subdirectory of this repo called vim.
" Pass the path to set the runtimepath properly.
Plugin 'rstacruz/sparkup', {'rtp': 'vim/'}
Plugin 'Valloric/YouCompleteMe'
Plugin 'altercation/vim-colors-solarized'  " New line!!
Plugin 'christoomey/vim-tmux-navigator'
Plugin 'scrooloose/nerdtree'
"Code folding plugin
Plugin 'tmhedberg/SimpylFold'
" Plugin to fix trailing white space
Plugin 'bronson/vim-trailing-whitespace'

"Auto-indention plugin
Plugin 'vim-scripts/indentpython.vim'
"Syntax check highlighting
Plugin 'scrooloose/syntastic'
"PEP8 checking
Plugin 'nvie/vim-flake8'
"Powerline status bar
Plugin 'Lokaltog/powerline', {'rtp': 'powerline/bindings/vim/'}
" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required
" To ignore plugin indent changes, instead use:
"filetype plugin on
"
" Brief help
" :PluginList       - lists configured plugins
" :PluginInstall    - installs plugins; append `!` to update or just :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line
"
" Setting up default spacing
set tabstop=4
set softtabstop=4
set shiftwidth=4
set noexpandtab
"
"PEP8 Indentation support just for py files
au BufNewFile,BufRead *.py
	\ set tabstop=4 |
	\ set softtabstop=4 |
	\ set shiftwidth=4 |
	\ set textwidth=79 |
	\ set expandtab |
	\ set autoindent |
	\ set fileformat=unix
let python_highlight_all=1
let g:ycm_python_binary_path = '~/.virtualenvs/general/bin/python3'



"Enable folding
set foldmethod=indent
set foldlevel=99
"Enable folding with <space>
nnoremap <space> za
"But still want to see Doc strings
let g:SimplylFold_docstring_preview=1

"Setting up powerline status bar
set guifont=Inconsolata\ for\ Powerline:h15
set laststatus=2
set showtabline=2
set noshowmode	"Hide the default mode text
let g:Powerline_symbols = 'fancy'
set encoding=utf-8
set t_Co=256
set fillchars+=stl:\ ,stlnc:\
"set term=xterm-256color
set termencoding=utf-8
if has("gui_running")
   let s:uname = system("uname")
   if s:uname == "Darwin\n"
	   set guifont=Inconsolata\ for\ Powerline:h15
   endif
endif
"show the 80 column
if (exists('+colorcolumn'))
	set colorcolumn=80
	highlight ColorColumn ctermbg=9
endif

" Global ycm_extra_conf.py
let g:ycm_global_ycm_extra_conf = '~/.vim/.ycm_extra_conf.py'
set pastetoggle=<F2>
set ruler
set cursorline
set showmode
syntax on
filetype plugin indent on
syntax enable
set encoding=utf-8
set number        " Show line numbers
set background=dark
"let g:solarized_termtrans = 1
let g:solarized_termcolors = 256

colorscheme solarized

