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

CODESEG

binderr     db  'Error: Unable to bind to port',__n
_binderrlen equ $-binderr
usage       db  'MineProxy Version 1.0, 1 Aug 2012, Copyright (c) 2012 Elliott Carlson',__n,__n
            db  'Usage: mineproxy <messagefile> <listenport> <serverport>',__n
_usagelen   equ $-usage

%assign binderrlen _binderrlen
%assign usagelen _usagelen


START:
    ; Grab the command line arguments
	pop	ebp
	cmp	ebp, byte 4
    ; If there are more or less than 3 arguments, exit
	jne	help_and_exit
	pop	esi		;argv[0]

	pop	esi		;local port
	call	str2long
	mov	edi,ebx

	pop	esi
	call	inet_addr
	mov     [remsockstruct+4],edx

	pop	esi		;remote port
	call	str2long
	xchg	bh,bl
	shl	ebx,16
	mov	bl,AF_INET	;if (AF_INET > 0xff) mov bx,AF_INET
	mov     [remsockstruct],ebx

; arguments processed now: create socket, setsockopt reuseddr and
; proceed to binding

	mov	ebx,edi
	xchg	bh,bl		;now save port number into bindsock struct
	shl	ebx,16
	mov	bl,AF_INET	;if (AF_INET > 0xff) mov bx,AF_INET
	mov     [sockstruct],ebx
	
.begin:
	sys_socket PF_INET,SOCK_STREAM,IPPROTO_TCP
	mov	ebp,eax		;socket descriptor

    push byte 0x1
    mov edi,esp
	sys_setsockopt ebp,SOL_SOCKET,SO_REUSEADDR,edi,4
	jmp	do_bind

bind_error:
    sys_write STDOUT,binderr,binderrlen
help_and_exit:                           
    sys_write STDOUT,usage,usagelen
	_mov	ebx,1
real_exit:
	sys_exit

; convert string @ esi to internet address, place it into edx
; ruined registers: edi, eax, ebx, edx
inet_addr:
	xor	edx,edx
	mov	ecx,4
.ipconv:
	call	str2long
	mov	dl,bl
	ror	edx,8
	loop	.ipconv
	ret

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
	ret

; main program continues here, we do bind

do_bind:
	sys_bind ebp,sockstruct,16
; this is the only place worth error checking
	or	eax,eax
	jnz	bind_error

	sys_listen ebp,5		;listen(s, 5)
; this should always succeed

;fork after everything is done and exit main process
	sys_fork
	or	eax,eax
	jz	acceptloop

true_exit:
	_mov	ebx,0
	jmps	real_exit

acceptloop:
	mov	[structlen],byte 16
	sys_accept ebp,filebuf,structlen
	test	eax,eax
	js	acceptloop
	mov	edi,eax			;our descriptor

	sys_wait4	0xffffffff,NULL,WNOHANG,NULL
	sys_wait4

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
	sys_connect esi,remsockstruct,16
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

sockstruct	resd	4
remsockstruct	resd	4

filebuf		resb	0x2000

structlen	resb	1

