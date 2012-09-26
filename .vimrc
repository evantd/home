" Setting up Vundle - the vim plugin bundler
  set nocompatible          " Use Vim defaults (much better!)
  filetype off
  let vundle_readme=expand('~/.vim/bundle/vundle/README.md')
  if !filereadable(vundle_readme)
    echo "Installing Vundle.."
    echo ""
    silent !git clone https://github.com/gmarik/vundle ~/.vim/bundle/vundle
  endif
  set rtp+=~/.vim/bundle/vundle/
  call vundle#rc()
  Bundle 'gmarik/vundle'

  "Add your bundles here
  Bundle 'altercation/vim-colors-solarized'
  Bundle 'chriskempson/base16-vim'
  Bundle 'chriskempson/vim-tomorrow-theme'
  Bundle 'scrooloose/nerdtree'
  Bundle "MarcWeber/vim-addon-mw-utils"
  Bundle "tomtom/tlib_vim"
  Bundle "honza/snipmate-snippets"
  Bundle "garbas/vim-snipmate"
  Bundle "tpope/vim-haml"

  filetype plugin indent on
"  echo "Installing Bundles, please ignore key map error messages"
"  echo ""
"  BundleInstall
" Setting up Vundle - the vim plugin bundler end

" eI config
" Configuration file for vim
" initial author: John Carrino (carrino@)

" Standard vim options
  set diffopt=filler,iwhite " keep files synced and ignore whitespace
  set guioptions-=m         " Remove menu from the gui
  set guioptions-=T         " Remove toolbar
  set hidden                " hide buffers instead of closing
  set history=50            " keep 50 lines of command line history
  set ignorecase            " Do case insensitive matching
  set incsearch             " Incremental search
  set laststatus=2          " always have status bar
  set linebreak             " This displays long lines as wrapped at word boundries
  set matchtime=10          " Time to flash the brack with showmatch
  set nobackup              " Don't keep a backup file
  set nofen                 " disable folds
  set notimeout             " i like to be pokey
  set nottimeout            " take as long as i like to type commands
  set ruler                 " the ruler on the bottom is useful
  set scrolloff=1           " dont let the curser get too close to the edge
  set showcmd               " Show (partial) command in status line.
  set showmatch             " Show matching brackets.
  set textwidth=0           " Don't wrap words by default
  "set textwidth=80          " This wraps a line with a break when you reach 80 chars
  set timeoutlen=10000      " Time to wait for a map sequence to complete
  set ttimeoutlen=10000     " time to wait for a key code to complete
  set virtualedit=block     " let blocks be in virutal edit mode
  set wildmenu              " This is used with wildmode(full) to cycle options

"Longer Set options
  set cscopequickfix=s-,c-,d-,i-,t-,e-,g-,f-   " useful for cscope in quickfix
  set listchars=tab:>-,trail:-                 " prefix tabs with a > and trails with -
  set tags+=.tags,../.tags,../../.tags,../../../.tags " set ctags
  set whichwrap+=<,>,[,],h,l,~                 " arrow keys can wrap in normal and insert modes
  set wildmode=list:longest,full               " list all options, match to the longest

  set helpfile=$VIMRUNTIME/doc/help.txt
  set guifont=Courier\ 10\ Pitch\ 10
  set path+=.,..,../..,../../..,../../../..,/usr/include

  " Suffixes that get lower priority when doing tab completion for filenames.
  " These are files I am not likely to want to edit or read.
  set suffixes=.bak,~,.swp,.o,.info,.aux,.log,.dvi,.bbl,.blg,.brf,.cb,.ind,.idx,.ilg,.inx,.out,.toc,.class

" viminfo options
  " read/write a .viminfo file, don't store more than
  " 50 lines of registers
  set viminfo='20,\"50


"Set variables for plugins to use

  "vimspell variables
    "don't automatically spell check!
    let spell_auto_type=""

  " LargeFile.vim settings
  " don't run syntax and other expensive things on files larger than NUM megs
  let g:LargeFile = 100

" my own config, originally stolen from dnangle

highlight ExtraWhitespace ctermbg=red guibg=red
autocmd BufWinEnter * highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$\|	\|\t/

set nocompatible  " use VIM defaults

syntax on         " turn on syntax highlighting
set t_Co=256      " turn on 256-color support
set bg=dark       " dark terminal background
colorscheme Tomorrow-Night-Bright
"autocmd BufReadPost * SetColors darkblue delek desert elflord pablo ron torte
"autocmd BufReadPost * call NextColor(0)

set backspace=2   " allow backspacing over anything

set expandtab             " Get rid of tabs altogether and replace with spaces
set shiftwidth=2          " Set indention level to be the same as softtabstop
set softtabstop=2         " Why are tabs so big?  This fixes it
set autoindent            " always set autoindenting on

set magic         " don't need to escape ., *, etc in regexp
set showmode      " shows whether in INSERT, REPLACE, VISUAL, etc
set ruler         " show cursor position

set hlsearch      " highlight search matches
set incsearch     " incremental search
set ignorecase    " match any string case in search
set smartcase     " smart case matching

set showmatch     " show matching parenthesis on insert

set visualbell    " use visual bell instead of beeping

set foldmethod=syntax "or marker with marker set to {,}
set foldlevel=9
set foldcolumn=5 "shows how deep into the fold hierarchy you're in. use a higher number based on preference
set foldenable
let perl_fold=1
let java_highlight_functions="style"
let java_highlight_debug=1

au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g`\"" | endif
