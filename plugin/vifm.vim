" forked from
" https://github.com/hut/ranger/blob/master/examples/vim_file_chooser.vim
" https://github.com/Mizuchi/vim-ranger/blob/master/plugin/ranger.vim
" https://github.com/airodactyl/neovim-ranger

function! s:vifmGetVar(var, type, default)
    if exists(a:var)
        if  eval('type (' . a:var . ')') != a:type
            echoerr 'neovim-vifm: ' . a:var . ' must be type ' . string(a:type)
        else
            return eval(a:var)
        endif
    endif
    return a:default
endfunction

function! s:vifmGetSplitWidth()
    return s:vifmGetVar('g:vifmSplitWidth', 0, 40)
endfunction

function! s:vifmGetUseCurrent()
    return s:vifmGetVar('g:vifmUseCurrent', 0, 1)
endfunction

function! s:vifmGetLiveCwd()
    return s:vifmGetVar('g:vifmLiveCwd', 0, 0)
endfunction

function! s:vifmGetUseLcd()
    return s:vifmGetVar('g:vifmUseLcd', 0, 0)
endfunction

function! s:vifmGetFixWidth()
    return s:vifmGetVar('g:vifmFixWidth', 0, 1)
endfunction

function! s:vifmGetBufList()
    return s:vifmGetVar('g:vifmBufList', 0, 1)
endfunction

" TODO: these two focus variables have not been finalized, and so they are not
" yet documented

function! s:vifmGetAutoFocus()
    return s:vifmGetVar('g:vifmAutoFocus', 0, 1)
endfunction

function! s:vifmGetStartInsert()
    return s:vifmGetVar('g:vifmStartInsert', 0, 1)
endfunction

function! s:VifmCwdCall(dirfile)
    let l:command = ['bash', '-c', 'while true; do cat ' . shellescape(a:dirfile) . '; done']
    let l:argdict = {}
    let l:callbacks = { 'on_stdout': function('s:VifmCwdStdoutCallback') }
    let l:job = jobstart(l:command, extend(l:argdict, l:callbacks))
    return l:job
endfunction

function! s:VifmCall(dirname, mode, prev)
    let l:listfile = tempname()
    let l:command = ['vifm', '--choose-files', l:listfile ]
    let l:vifmUseCurrent = s:vifmGetUseCurrent()
    if l:vifmUseCurrent
        let l:command = l:command + [a:dirname]
    endif
    let l:argdict = {
                \ 'listfile': l:listfile,
                \ 'mode': a:mode,
                \ 'prev': a:prev,
                \ }
    let l:callbacks = { 'on_exit': function('s:VifmExitCallback') }
    let l:vifmLiveCwd = s:vifmGetLiveCwd()
    if l:vifmLiveCwd == 1
        let l:dirfile = tempname()
        silent exec '!mkfifo ' . l:dirfile
        let l:cwd_job = s:VifmCwdCall(l:dirfile)
        let l:argdict.dirfile = l:dirfile
        let l:argdict.cwd_job = l:cwd_job
        call add(l:command, '-c')
        call add(l:command, 'autocmd DirEnter * !pwd >> ' . l:dirfile)
        call add(l:command, '--choose-dir')
        call add(l:command, l:dirfile)
    endif
    call termopen(l:command, extend(l:argdict, l:callbacks))
    if a:mode ==# 'split' && s:vifmGetFixWidth()
        set winfixwidth
    endif
    if s:vifmGetBufList()
        set nobuflisted
    endif
    if s:vifmGetAutoFocus() || a:mode !=# 'split'
        if s:vifmGetStartInsert()
            startinsert
        endif
    else
        exe a:prev . 'wincmd w'
    endif
endfunction

function! s:VifmCallWithMode(dirname, mode)
    if a:mode ==# 'split'
        let l:prev = winnr()
    else
        let l:prev = bufnr('%')
    endif
    let l:vifmSplitWidth = s:vifmGetSplitWidth()
    if a:mode ==# 'split'
        exe l:vifmSplitWidth . 'vnew'
    endif
    call s:VifmCall(a:dirname, a:mode, l:prev)
endfunction

function! Vifm(dirname)
    if a:dirname !=# '' && isdirectory(a:dirname)
        let l:winnum = s:VifmWinNum()
        if l:winnum == 0
            call s:VifmCallWithMode(a:dirname, 'split')
        else
            exe l:winnum . 'wincmd w'
            startinsert
        endif
    endif
endfunction

function! VifmToggle(dirname)
    if s:VifmBufNum() != -1
        call VifmClose()
    else
        call Vifm(a:dirname)
    endif
endfunction

function! VifmNoSplit(dirname)
    if a:dirname ==# '' && isdirectory(a:dirname)
        if !s:VifmInThisBuf()
            call s:VifmCallWithMode(a:dirname, 'auto')
        endif
    endif
endfunction

function! s:VifmBufferCheck(bufnum)
    let l:bufstr = bufname(a:bufnum)
    return matchstr(l:bufstr, '^term:\/\/.*:vifm$') !=# ''
endfunction

function! s:VifmCwdStdoutCallback(job_id, data, event)
    if s:vifmGetUseLcd()
        exec 'lcd ' . fnameescape(a:data[0])
    else
        exec 'cd ' . fnameescape(a:data[0])
    endif
endfunction

function! s:VifmExitCallback(job_id, data, event) dict
    if exists('self.cwd_job')
        call jobstop(l:self.cwd_job)
    endif
    if !filereadable(l:self.listfile)
        return
    endif
    let l:names = readfile(l:self.listfile)
    if empty(l:names)
        return
    endif
    if l:self.mode ==# 'split'
        call VifmClose(l:self.mode, l:self.prev)
    else
        call VifmClose(l:self.mode, l:self.prev)
    endif
    exec 'edit ' . fnameescape(l:names[0])
    for l:name in l:names[1:]
        exec 'tabedit ' . fnameescape(l:name)
        filetype detect
    endfor
endfunction

function! s:VifmBufNum()
    let l:bufnums = tabpagebuflist()
    for l:bufnum in l:bufnums
        if s:VifmBufferCheck(l:bufnum)
            return l:bufnum
        endif
    endfor
    return -1
endfunction

function! s:VifmWinNum()
    let l:bufnum = s:VifmBufNum()
    if l:bufnum == -1
        return 0
    else
        return bufwinnr(l:bufnum)
    endif
endfunction

function! s:VifmInThisBuf()
    return s:VifmBufferCheck(bufnr('%'))
endfunction

function! s:VifmJumpBack(mode, prev)
    if a:prev == -1
        return 0
    endif
    if a:mode ==# 'split'
        silent! exe a:prev . 'wincmd w'
    else
        silent! buffer a:prev
    endif
    return 1
endfunction

function! VifmClose(...)
    if a:0 > 0
        let l:mode = a:1
    else
        let l:mode = 'split'
    endif
    if a:0 > 1
        let l:prev = a:2
    else
        let l:prev = -1
    endif
    if s:VifmInThisBuf()
        if l:mode ==# 'split'
            bdelete!
            call s:VifmJumpBack(l:mode, l:prev)
        else
            let l:bufnum = bufnr('%')
            " there might be no previous buffer to go to, silence the error
            silent! bprev
            call s:VifmJumpBack(l:mode, l:prev)
            exe 'silent! bdelete! ' . l:bufnum
        endif
        return
    else
        let l:bufnum = s:VifmBufNum()
        if l:bufnum == -1
            return
        else
            exe 'bdelete! ' . l:bufnum
        endif
    endif
endfunction

function! s:VifmAuto(dirname)
    if a:dirname !=# '' && isdirectory(a:dirname)
        " bdelete!
        call VifmNoSplit(a:dirname)
    endif
endfunction

let g:loaded_netrwPlugin = 'disable'
augroup neovimvifm
    au BufEnter * silent call s:VifmAuto(expand('<amatch>'))
augroup END

command! -complete=file -nargs=1 Vifm call Vifm(<f-args>)
command! -nargs=0 VifmClose call VifmClose()
command! -complete=file -nargs=1 VifmToggle call VifmToggle(<f-args>)
