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

section .data:
    _be     db  'Error: Unable to bind to port',__n
    _be_l   equ $-_be
    _fe     db  'Error: Unable to read message file',__n
    _fe_l   equ $-_fe

    _us     db  'MineProxy Version 1.0, Copyright (c) 2012 Elliott Carlson',__n
            db  __n
            db  'Usage: mineproxy <messagefile> <listenport> <serverport>',__n
    _us_l   equ $-_us

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
    call    str2long        ; convert port to long
    mov     [lcl_sock], ebx ; set the port on our local socket struct

    pop     esi             ; argv[3] - remoteport
    call    str2long        ; convert port to long
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

; convert string @ esi to short (word) and place it into ebx
; destroyed: esi, eax and ebx
str2long:
	xor	eax,eax
	xor	ebx,ebx
.n1:
	lodsb
	sub	al,'0'
	jb	.n2
        cmp	al,9
	ja	.n2
	imul	ebx,byte 10
	add	ebx,eax
	jmps	.n1
.n2:
    xchg    bh, bl          ; swap values
    shl     ebx, 16         ; 
    mov     bl, AF_INET
	ret

; open file @ ebx and read contents in to buf
read_file:
    ; open the file
    mov     eax, 5          ; open(
    mov     ecx, 0          ;   read-only mode
    int     80h             ;);

    ; check for errors
    test    eax, eax        ; test the file descriptor @ eax
    js      file_read_err   ; if the file descriptor has the sign flag,
                            ; (less than 0), jump to 'file_read_err'

    ; read the file
    mov     eax, 3          ; read(
    mov     ebx, eax        ;   file_descriptor,
    mov     ecx, buf        ;   *buf,
    mov     edx, bufsize    ;   *bufsize
    int     80h             ; );

    test    eax, eax        ; test the file read return value
    jz      file_read_err   ; got an EOF, jump to 'file_read_err'
    js      file_read_err   ; got an error, jump to 'file_read_err'

    ret                     ; return from call



; main program continues here, we do bind

do_bind:
	sys_bind ebp,lcl_sock,16
; this is the only place worth error checking
	or	eax,eax
	jnz	bind_error

	sys_listen ebp,5		;listen(s, 5)
; this should always succeed

;fork after everything is done and exit main process
;	sys_fork
	or	eax,eax
	jz	acceptloop

true_exit:
	_mov	ebx,0
	jmp 	exit

acceptloop:
	mov	[structlen],byte 16
	sys_accept ebp,filebuf,structlen
	test	eax,eax
	js	acceptloop
	mov	edi,eax			;our descriptor

	sys_wait4	0xffffffff,NULL,WNOHANG,NULL
	sys_wait4

  ; write to STDOUT
    mov     eax,  4         ; write(
    mov     ebx,  1         ;   STDOUT,
    mov     ecx,  buf       ;   *buf
    int     80h             ; );

	sys_fork		;we now fork, child goes his own way, daddy goes back to accept
	or	eax,eax
	jz	.childrun
	sys_close edi
	_jmp	acceptloop

; Child code starts here, source descriptor is in EDI
; We have to open connection to the darling remote system and
; proxy data. sounds simple? it sure ain't.
.childrun:

; at first create a socket, ignoring errors, if there are any
; we run into them later anyway
; we run into them later anyway
	sys_socket PF_INET,SOCK_STREAM,IPPROTO_TCP
	mov	esi,eax		;socket descriptor
; now we have to connect that socket to remote host :)
	sys_connect esi,rem_sock,16
	or	eax,eax
	jz	.goon
; if connect failed, @sys_exit automagically kernel closes connection
	sys_exit
.goon:
; Now the situation is this: EDI = source, ESI = destination :)))
; What we do is we fork again and each reads from themselves and
; writes into theother. waste of processes? yes. easy hack? yes!!!
	sys_fork
	or	eax,eax
	jz	.papa

	xchg	edi,esi	; the child just exchanges the descrptors :)

.papa:
	sys_read esi,filebuf,0x2000
	cmp	eax,0
	jng	.exit
	sys_write edi,filebuf,eax
	jmps	.papa
.exit:
; shutdown also the other socket, so we'll end up cleaned, no childs hanging
	sys_shutdown edi,1
	jmp 	true_exit

UDATASEG

remoteadd	resd	1
remoteport	resd	1

lcl_sock	resd	4
rem_sock	resd	4

filebuf		resb	0x2000

structlen	resb	1


section .data
   bufsize dw      1024

section .bss
   buf     resb    1024

