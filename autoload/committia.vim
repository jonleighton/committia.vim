let s:save_cpo = &cpo
set cpo&vim

let g:committia_use_singlecolumn = get(g:, 'committia_use_singlecolumn', 'fallback')
let g:committia_min_window_width = get(g:, 'committia_min_window_width', 160)
let g:committia_edit_window_width = get(g:, 'committia_edit_window_width', 80)
let g:committia_diff_window_opencmd = get(g:, 'committia_diff_window_opencmd', 'botright vsplit')
let g:committia_status_window_opencmd = get(g:, 'committia_status_window_opencmd', 'belowright split')
let g:committia_singlecolumn_diff_window_opencmd = get(g:, 'committia_singlecolumn_diff_window_opencmd', 'belowright split')
let g:committia_hooks = get(g:, 'committia_hooks', {})
let g:committia_use_terminal = get(g:, 'committia_use_terminal', 1)

inoremap <silent> <Plug>(committia-scroll-diff-down-half) <C-o>:call committia#scroll_window('diff', 'C-d')<CR>
inoremap <silent> <Plug>(committia-scroll-diff-up-half) <C-o>:call committia#scroll_window('diff', 'C-u')<CR>
inoremap <silent> <Plug>(committia-scroll-diff-down-page) <C-o>:call committia#scroll_window('diff', 'C-f')<CR>
inoremap <silent> <Plug>(committia-scroll-diff-up-page) <C-o>:call committia#scroll_window('diff', 'C-b')<CR>
inoremap <silent> <Plug>(committia-scroll-diff-down) <C-o>:call committia#scroll_window('diff', 'C-e')<CR>
inoremap <silent> <Plug>(committia-scroll-diff-up) <C-o>:call committia#scroll_window('diff', 'C-y')<CR>
nnoremap <silent> <Plug>(committia-scroll-diff-down-half) :<C-u>call committia#scroll_window('diff', 'C-d')<CR>
nnoremap <silent> <Plug>(committia-scroll-diff-up-half) :<C-u>call committia#scroll_window('diff', 'C-u')<CR>
nnoremap <silent> <Plug>(committia-scroll-diff-down-page) :<C-u>call committia#scroll_window('diff', 'C-f')<CR>
nnoremap <silent> <Plug>(committia-scroll-diff-up-page) :<C-u>call committia#scroll_window('diff', 'C-b')<CR>
nnoremap <silent> <Plug>(committia-scroll-diff-down) :<C-u>call committia#scroll_window('diff', 'C-e')<CR>
nnoremap <silent> <Plug>(committia-scroll-diff-up) :<C-u>call committia#scroll_window('diff', 'C-y')<CR>

let s:current_info = {}

function! s:use_terminal() abort
    return g:committia_use_terminal && has('terminal')
endfunction

function! s:open_window(vcs, type, info, ft) abort
    let content = call('committia#' . a:vcs . '#' . a:type, [])

    let bufname = '__committia_' . a:type . '__'
    let coltype = a:info['singlecolumn'] ? 'singlecolumn_' : ''
    execute 'silent' g:committia_{coltype}{a:type}_window_opencmd bufname
    let a:info[a:type . '_winnr'] = bufwinnr(bufname)
    let a:info[a:type . '_bufnr'] = bufnr('%')
    call setline(1, content)
    execute 0
    execute 'setlocal ft=' . a:ft
    setlocal nonumber bufhidden=wipe buftype=nofile readonly nolist nobuflisted noswapfile nomodifiable nomodified nofoldenable
endfunction

" In terminal mode this will open a buffer that doesn't get used
" Implement a callback for both that moves the cursor to the start
" DRY it up
" Also consider what the functions in git.vim do, do we need them?
function! s:open_term(vcs, type, info, term_opts, callback) abort
    " FIXME
    let foo = call('committia#' . a:vcs . '#load', [])

    let coltype = a:info['singlecolumn'] ? 'singlecolumn_' : ''

    execute 'silent' g:committia_{coltype}{a:type}_window_opencmd '__temp__'
    execute 'vertical' a:info.edit_winnr . 'resize' g:committia_edit_window_width

    " TODO: open all windows first
    " let a:info[a:type . '_winnr'] = winnr('$')

    let cmd = a:vcs . ' ' . get(g:, 'committia#' . a:vcs . '#term_' . a:type . '_cmd', '')
    let term_opts = {
    \ 'curwin': 1,
    \ 'norestore': 1,
    \ 'exit_cb': function('s:term_exit', [a:type, a:info, a:callback]),
    \ }

    let a:info[a:type . '_bufnr'] = term_start(cmd, extend(term_opts, a:term_opts))
    normal bd#
    setlocal nonumber bufhidden=wipe buftype=nofile readonly nolist nobuflisted noswapfile nomodifiable nomodified nofoldenable signcolumn=no colorcolumn=
endfunction

function! s:term_exit(type, info, callback, job, status) abort
    if a:status != 0
        return 0
    endif

    " Wait for the output before we manipulate the buffer
    let bufnr = a:info[a:type . '_bufnr']
    call term_wait(bufnr)
    redraw

    let prev_winnr = winnr()

    " echom a:info

    execute bufwinnr(bufnr) . 'wincmd w'
    normal gg
    call a:callback(a:info)
    execute prev_winnr . 'wincmd w'
endfunction

" Open diff window.  If no diff is detected, close the window and return to
" the original window.
" It returns 0 if the window is not open, othewise 1
function! s:open_diff_window(vcs, info) abort
    if s:use_terminal()
        " Set GIT_PAGER if delta is not present
        call s:open_term(a:vcs, 'diff', a:info, {}, function('s:diff_window_opened'))
    else
        call s:open_window(a:vcs, 'diff', a:info, 'git', term_opts)

        if !s:diff_window_opened(a:info)
            return 0
        end
    endif

    return 1
endfunction

function! s:diff_window_opened(info) abort
    " echom "diff_window_opened"
    " echom winnr()
    " if readfile(bufname(a:info.diff_bufnr)) ==# ['']
    "     execute a:info.diff_winnr . 'wincmd c'
    "     wincmd p
    "     return 0
    " endif

    return 1
endfunction

function! s:open_status_window(vcs, info) abort
    if s:use_terminal()
        let term_opts = {'env': {'GIT_PAGER': ''}}
        call s:open_term(a:vcs, 'status', a:info, term_opts, function('s:status_window_opened'))
    else
        call s:open_window(a:vcs, 'status', a:info, 'gitcommit')
        call s:status_window_opened(a:info)
    endif
    return 1
endfunction

function! s:status_window_opened(info) abort
    if line('$') < winheight(0)
        execute 'resize' line('$')
    endif
endfunction

function! s:execute_hook(name, info) abort
    if has_key(g:committia_hooks, a:name)
        call call(g:committia_hooks[a:name], [a:info], g:committia_hooks)
    endif
endfunction

function! s:remove_all_contents_except_for_commit_message(vcs) abort
    1
    " Handle squash message
    let line = call('committia#' . a:vcs . '#end_of_edit_region_line', [])
    if 0 < line && line <= line('$')
        execute 'silent' line . ',$delete _'
    endif
    1
    " FIXME: DRY
    execute 'vertical resize' g:committia_edit_window_width
endfunction

function! s:callback_on_window_closed() abort
    if bufnr('%') == s:current_info.edit_bufnr
        for n in ['diff', 'status']
            if has_key(s:current_info, n . '_bufnr')
                let winnr = bufwinnr(s:current_info[n . '_bufnr'])
                if winnr != -1
                    execute winnr . 'wincmd w'
                    wincmd c
                endif
            endif
        endfor
        let s:current_info = {}
        autocmd! plugin-committia-winclosed
    endif
endfunction

function! s:callback_on_window_closed_workaround() abort
    let edit_winnr = bufwinnr(s:current_info.edit_bufnr)
    if edit_winnr == -1
        quit!
    endif
endfunction

function! s:get_map_of(cmd) abort
    if stridx(a:cmd, '-') == -1
        return a:cmd
    endif
    return eval('"\<' . a:cmd . '>"')
endfunction

function! committia#scroll_window(type, cmd) abort
    let target_winnr = bufwinnr(s:current_info[a:type . '_bufnr'])
    if target_winnr == -1
        return
    endif
    noautocmd execute target_winnr . 'wincmd w'
    noautocmd execute 'normal!' s:get_map_of(a:cmd)
    noautocmd wincmd p
endfunction

function! s:set_callback_on_closed() abort
    augroup plugin-committia-winclosed
        if exists('##QuitPre')
            autocmd QuitPre COMMIT_EDITMSG,MERGE_MSG call s:callback_on_window_closed()
        else
            autocmd WinEnter __committia_diff__,__committia_status__ nested call s:callback_on_window_closed_workaround()
        end
    augroup END
endfunction

function! committia#open_multicolumn(vcs) abort
    let info = {'vcs' : a:vcs, 'edit_winnr' : winnr(), 'edit_bufnr' : bufnr('%'), 'singlecolumn' : 0}

    let diff_window_opened = s:open_diff_window(a:vcs, info)
    if !diff_window_opened
        return
    endif
    " FIXME: need to deal with hooks
    call s:execute_hook('diff_open', info)
    wincmd p

    call s:open_status_window(a:vcs, info)
    call s:execute_hook('status_open', info)
    wincmd p

    call s:remove_all_contents_except_for_commit_message(info.vcs)
    call s:execute_hook('edit_open', info)

    let s:current_info = info
    setlocal bufhidden=wipe
    let b:committia_opened = 1
    call s:set_callback_on_closed()
endfunction

function! committia#open_singlecolumn(vcs) abort
    let info = {'vcs' : a:vcs, 'edit_winnr' : winnr(), 'edit_bufnr' : bufnr('%'), 'singlecolumn' : 1}

    let diff_window_opened = s:open_diff_window(a:vcs, info)
    if !diff_window_opened
        return
    endif
    call s:execute_hook('diff_open', info)
    wincmd p

    let height = min([line('$') + 3, get(g:, 'committia_singlecolumn_edit_max_winheight', 16)])
    execute 'resize' height
    call s:execute_hook('edit_open', info)

    let s:current_info = info
    setlocal bufhidden=wipe
    let b:committia_opened = 1
    call s:set_callback_on_closed()
endfunction

function! committia#open(vcs) abort
    let is_narrow = winwidth(0) < g:committia_min_window_width
    let use_singlecolumn
                \ = g:committia_use_singlecolumn ==# 'always'
                \ || (is_narrow && g:committia_use_singlecolumn ==# 'fallback')

    if is_narrow && !use_singlecolumn
        call s:execute_hook('edit_open', {'vcs' : a:vcs})
        return
    endif

    " When opening a commit buffer with --amend flag, Vim tries to move the
    " cursor to the previous position. Detect it and reset the cursor
    " position.
    if line('.') != 1
        keepjumps call cursor(1, 1)
    endif

    if use_singlecolumn
        call committia#open_singlecolumn(a:vcs)
    else
        call committia#open_multicolumn(a:vcs)
    endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
