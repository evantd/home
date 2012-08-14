" eI config
" Configuration file for vim
" initial author: John Carrino (carrino@)

" Standard vim options
  set autoindent            " always set autoindenting on
  set backspace=2           " allow backspacing over everything in insert mode
  set cindent shiftwidth=4  " Same thing with cindent
  set diffopt=filler,iwhite " keep files synced and ignore whitespace
  set expandtab             " Get rid of tabs altogether and replace with spaces
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
  set nocompatible          " Use Vim defaults (much better!)
  set nofen                 " disable folds
  set notimeout             " i like to be pokey
  set nottimeout            " take as long as i like to type commands
  set ruler                 " the ruler on the bottom is useful
  set scrolloff=1           " dont let the curser get too close to the edge
  set shiftwidth=4          " Set indention level to be the same as softtabstop
  set showcmd               " Show (partial) command in status line.
  set showmatch             " Show matching brackets.
  set softtabstop=4         " Why are tabs so big?  This fixes it
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

"Use a temp directory in the home dir rather than in tmp where it can get
"cleaned up without our consent
perl <<EOT
  # Get the user name, should probably get the home dir...
  my $home_dir = (getpwuid($<))[7];

  if ( -e $home_dir ) {
    my $temp_location = "$home_dir/.vim-tmp";
    my $tmp_dir = $temp_location . '/vXXX';
    my $swp_dir = $temp_location . '/swps';

    # If the location doesn't exist, create it
    mkdir $temp_location unless ( -e $temp_location );

    mkdir $tmp_dir unless ( -e $tmp_dir );
    mkdir $swp_dir unless ( -e $swp_dir );

    # Set TMPDIR and directory to the new location
    VIM::DoCommand("let \$TMPDIR = '" . $tmp_dir . "'") if ( -w $tmp_dir );
    VIM::DoCommand("set directory=" . $swp_dir) if ( -w $swp_dir );
  }
EOT

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

"Turn on filetype plugins to automagically
  "Grab commands for particular filetypes.
  "Grabbed from $VIM/ftplugin
  filetype plugin on
  filetype indent on

" my own config, originally stolen from dnangle

highlight ExtraWhitespace ctermbg=red guibg=red
autocmd BufWinEnter * highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$\|	\|\t/

set nocompatible  " use VIM defaults

syntax on         " turn on syntax highlighting
set t_Co=256      " turn on 256-color support
set bg=dark       " dark terminal background
colorscheme darkblue
autocmd BufReadPost * SetColors darkblue delek desert elflord pablo ron torte
autocmd BufReadPost * call NextColor(0)

set backspace=2   " allow backspacing over anything

set tabstop=8     " hard tab is 8 spaces
set softtabstop=4 " soft tab is 4 spaces
set shiftwidth=4  " use 4 spaces for indent
set expandtab     " expand tabs to spaces
set autoindent    " start new lines at same indent as last line
set smartindent   " use fancy autoindenting

set magic         " don't need to escape ., *, etc in regexp
set showmode      " shows whether in INSERT, REPLACE, VISUAL, etc
set ruler         " show cursor position

set hlsearch      " highlight search matches
set incsearch     " incremental search
set ignorecase    " match any string case in search
set smartcase     " smart case matching

set showmatch     " show matching parenthesis on insert

set visualbell    " use visual bell instead of beeping

map T :TlistToggle<CR>
let Tlist_Close_On_Select=1
let Tlist_Exit_OnlyWindow=1
let Tlist_Process_File_Always=1
let Tlist_File_Fold_Auto_Close=1
let Tlist_GainFocus_On_ToggleOpen=1
let Tlist_Display_Prototype=1 " java is too verbose to make this reasonable for vertical splits
let Tlist_Use_Horiz_Window=1
let Tlist_WinHeight=20
let Tlist_Use_Right_Window=1
let Tlist_Ctags_Cmd='~/bin/ctags-wrapper'
let Tlist_Sort_Type='name'
set updatetime=1000
set statusline=%<%f\ %h%m%r%w%y%=%([%{Tlist_Get_Tag_Prototype_By_Line()}]%)\ %l/%L,%c%V\ \ %P

set foldmethod=syntax "or marker with marker set to {,}
set foldlevel=9
set foldcolumn=5 "shows how deep into the fold hierarchy you're in. use a higher number based on preference
set foldenable
let perl_fold=1
let java_highlight_functions="style"
let java_highlight_debug=1

au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g`\"" | endif
