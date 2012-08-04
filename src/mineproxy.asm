; Copyright (c) 2012 Elliott Carlson <ecarlson@blockworld.org>
;
; $Id: mineproxy.asm,v 1.0 2012/08/01 23:22:39 limpidnova Exp $
;
; A minecraft proxy and notification server
;
; syntax: mineproxy <messagefile> <listenport> <serverport>
;
; MineProxy listens on the specified listenport for incoming connections.
; When a new connection is established, it will attempt to forward on the
; connected user to your running Minecraft server. In the event that the
; Minecraft server does not answer (i.e. it crashed or it has been taken
; down for maintenance), MineProxy will respond to the incoming connection
; with a custom specified message as described in the messagefile.

%include "system.inc"

section .text:
    global _start

_start:
    pop     ebx             ; argc - get the count of command line arguments
    cmp     ebx, byte 4     ; compare argc value with 4
    jne     help_and_exit   ; if argc != 4, jump to 'help_and_exit'

    pop     ebx             ; pop off argv[0] (the program name - discard this)

    pop     ebx             ; argv[1] - messagefile
    call    read_file       ; call subroutine 'read_file', which will add the
                            ; file contents to 'buf'

    pop     esi             ; argv[2] - listenport
    call    port            ; convert port to long
    mov     [lcl_sock], ebx ; set the port on our local socket struct

    pop     esi             ; argv[3] - remoteport
    call    port            ; convert port to long
    mov     [rem_sock], ebx ; set the port on our remote socket struct
    
    ; create a socket descriptor
    sys_socket PF_INET, SOCK_STREAM, IPPROTO_TCP
    mov     ebp, eax        ; copy descriptor to ebp

    ; set options on the socket descriptor
    sys_setsockopt ebp, SOL_SOCKET, SO_REUSEADDR, 0x1, 4
    jmp     do_bind         ; jump to do_bind

bind_error:
    ; display bind error stored in _be
    sys_write STDOUT, _be, _be_l
    jmp     help_and_exit 

file_read_err:
    ; display file read error stored in _fe
    sys_write STDOUT, _fe, _fe_l

help_and_exit:                           
    ; display help/usage stored in _us
    sys_write STDOUT, _us, _us_l
    _mov	ebx, 1

exit:
    ; exit the program
    sys_exit

; convert a string representation of a port to a short (word)
port:
    xor     eax, eax        ; set eax to 0 via bitwise xor on itself
    xor     ebx, ebx        ; set ebx to 0 via bitwise xor on itself
._port_loop:
    lodsb
    sub     al, '0'
    jb      ._port_end
    cmp     al, 9
    ja      ._port_end
    imul    ebx, byte 10
    add     ebx, eax
    jmps    ._port_loop
._port_end:
    xchg    bh, bl          ; swap values
    shl     ebx, 16         ; 
    mov     bl, AF_INET

    ret                     ; return from call

read_file:
    ; open the file specifiedin ebx
    mov     eax, 5          ; open(
    mov     ecx, 0          ;   read-only mode
    int     80h             ;);

    ; check for error
    test    eax, eax        ; test the file descriptor
    js      file_read_err   ; if signed (negative), jump to 'file_read_err'

    ; read the file in to 'buf'
    mov     eax, 3          ; read(
    mov     ebx, eax        ;   file_descriptor,
    mov     ecx, buf        ;   *buf,
    mov     edx, bufsize    ;   *bufsize
    int     80h             ; );

    test    eax, eax        ; test the file read return value
    jz      file_read_err   ; got an EOF, jump to 'file_read_err'
    js      file_read_err   ; got an error, jump to 'file_read_err'

    ret                     ; return from call

do_bind:
    ; attempt to bind the local socket to the requested port
    sys_bind ebp, lcl_sock, 16
    or      eax, eax        ; bitwise or on eax (to set value of eax in stack)
    jnz     bind_error      ; if not 0, then there was an error binding
    sys_listen ebp, 5       ; open the socket for incoming connections

;    sys_fork                ; fork the program to a backgorund child process 
    or      eax, eax        ; check the return value from fork
    jz      .accept_loop    ; if 0 (success), go in to the accept loop

.process_exit:
    _mov    bx, 0           ; set return code
    jmp     exit            ; jump to exit

.accept_loop:
    ; create a pointer to maintain a socket
    mov	    [addr_len], byte 16
    ; accept the incoming request using the socket pointer
    sys_accept ebp, addr_pnt, addr_len

    test    eax, eax        ; test that the socket connected successfully
    js      .accept_loop    ; if signed (negative), wait for next request
    mov     edi, eax        ; move socket descriptor

    ; check and read information from child processes (clean up, terminate)
    sys_wait4 0xffffffff, NULL, WNOHANG, NULL
    sys_wait4

    sys_fork                ; fork the accepted connection as a child
    or      eax, eax        ; check the return value of sys_fork
    jz      .remote_conn    ; if it returned 0 (success) jump to '.remote_conn'

    sys_close edi           ; close the connection
    _jmp    .accept_loop    ; loop back to continue listening for connections

.remote_conn:
    ; create the remote server socket to proxy through
    sys_socket PF_INET, SOCK_STREAM, IPPROTO_TCP
    mov     esi, eax        ; get the socket descriptor for the remote system

    ; connect to the socket
    sys_connect esi, rem_sock, 16
    or      eax, eax        ; check the return value of sys_connect
    jz      .proxy          ; if it returned 0 (success) jump to '.proxy'

    sys_exit                ; sys_connect failed, exit out

.proxy:
    ; fork again to allow the processes to communicate exclusively with
    ; each other. this is a waste of process descriptors and should be 
    ; optimized in the future
    sys_fork                ; fork the remote connection
    or      eax, eax        ; check the return value of sys_fork
    jz      .comms          ; if successful, jump to '.comms'

    xchg    edi, esi        ; exchange the descriptors - see explanation below:

; important to note; esi (source) and edi (destination) are interchangable
; in this routine - in the 'source' fork, esi refers to itself, and edi to
; the destination; in the 'destination' fork, esi refers to itself, and edi
; to the source - this allows bi-directional communication from the two
; processes
.comms:
    ; read from source (esi)
    sys_read esi, addr_pnt, 0x2000
    cmp     eax, 0          ; compare sys_read response to 0
    jng     .exit           ; if the response is 0 or negative, exit
    
    ; write to the destination (edi)
    sys_write edi, addr_pnt, eax
    jmps    .comms          ; loop the communication process until the
                            ; connection closes

.exit:
    ; ensure that if we (esi) are closing, that the remote (edi) is closed
    sys_shutdown edi, 1
    jmp     .process_exit

section .data:
    _be     db  'Error: Unable to bind to port',__n
    _be_l   equ $-_be
    _fe     db  'Error: Unable to read message file',__n
    _fe_l   equ $-_fe

    _us     db  'MineProxy Version 1.0, Copyright (c) 2012 Elliott Carlson',__n
            db  __n
            db  'Usage: mineproxy <messagefile> <listenport> <serverport>',__n
    _us_l   equ $-_us

    bufsize dw  1024

section .bss
    buf         resb    1024

    lcl_sock	resd    4
    rem_sock	resd    4

    addr_pnt	resb    0x2000
    addr_len	resb    1
