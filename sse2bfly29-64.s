/* Intel SIMD SSE2 implementation of Viterbi ACS butterflies
   for 256-state (k=9) convolutional code
   Copyright 2004 Phil Karn, KA9Q
   This code may be used under the terms of the GNU Lesser General Public License (LGPL)

   Modifications for x86_64, 2012 Matthias P. Braendli, HB9EGM
   - changed registers to x86-64 equivalents
   - changed instructions accordingly
   - %rip indirect addressing needed for position independent code,
     which is required because x86-64 needs dynamic libs to be PIC.
     That still doesn't work

   void update_viterbi29_blk_sse2(struct v29 *vp,unsigned char *syms,int nbits) ; 
*/
	# SSE2 (128-bit integer SIMD) version
    # All X86-64 CPUs include SSE2

	# These are offsets into struct v29, defined in viterbi29_av.c
	.set DP,512
	.set OLDMETRICS,516
	.set NEWMETRICS,520

	.text	
	.global update_viterbi29_blk_sse2,Branchtab29_sse2
	.type update_viterbi29_blk_sse2,@function
	.align 16
	
update_viterbi29_blk_sse2:
	pushq %rbp
	movq %rsp,%rbp
    /* convention different between i386 and x86_64: rsi and rdi belong to called function, not caller */
    /* Let's say we don't care (yet) */
	pushq %rsi
	pushq %rdi
	pushq %rdx
	pushq %rbx
	
	movq 8(%rbp),%rdx	# edx = vp
	testq %rdx,%rdx
	jnz  0f
	movq -1,%rax
	jmp  err		
0:	movq OLDMETRICS(%rdx),%rsi	# esi -> old metrics
	movq NEWMETRICS(%rdx),%rdi	# edi -> new metrics
	movq DP(%rdx),%rdx	# edx -> decisions

1:	movq 16(%rbp),%rax	# eax = nbits
	decq %rax
	jl   2f			# passed zero, we're done
	movq %rax,16(%rbp)

	xorq %rax,%rax
	movq 12(%rbp),%rbx	# ebx = syms
	movb (%rbx),%al
	movd %rax,%xmm6		# xmm6[0] = first symbol
	movb 1(%rbx),%al
	movd %rax,%xmm5		# xmm5[0] = second symbol
	addq $2,%rbx
	movq %rbx,12(%rbp)

	punpcklbw %xmm6,%xmm6	# xmm6[1] = xmm6[0]
	punpcklbw %xmm5,%xmm5
	movdqa thirtyones(%rip),%xmm7
	pshuflw $0,%xmm6,%xmm6	# copy low word to low 3
	pshuflw $0,%xmm5,%xmm5
	punpcklqdq %xmm6,%xmm6  # propagate to all 16
	punpcklqdq %xmm5,%xmm5
	# xmm6 now contains first symbol in each byte, xmm5 the second

	movdqa thirtyones(%rip),%xmm7
	
	# each invocation of this macro does 16 butterflies in parallel
	.MACRO butterfly GROUP
	# compute branch metrics
	movdqa Branchtab29_sse2+(16*\GROUP)(%rip),%xmm4
	movdqa Branchtab29_sse2+128+(16*\GROUP)(%rip),%xmm3
	pxor %xmm6,%xmm4
	pxor %xmm5,%xmm3
	pavgb %xmm3,%xmm4
	psrlw $3,%xmm4

	pand %xmm7,%xmm4	# xmm4 contains branch metrics
	
	movdqa (16*\GROUP)(%esi),%xmm0	# Incoming path metric, high bit = 0
	movdqa ((16*\GROUP)+128)(%esi),%xmm3	# Incoming path metric, high bit = 1
	movdqa %xmm0,%xmm2
	movdqa %xmm3,%xmm1
	paddusb %xmm4,%xmm0
	paddusb %xmm4,%xmm3
	
	# invert branch metrics
	pxor %xmm7,%xmm4
	
	paddusb %xmm4,%xmm1
	paddusb %xmm4,%xmm2
	
	# Find survivors, leave in mm0,2
	pminub %xmm1,%xmm0
	pminub %xmm3,%xmm2
	# get decisions, leave in mm1,3
	pcmpeqb %xmm0,%xmm1
	pcmpeqb %xmm2,%xmm3
	
	# interleave and store new branch metrics in mm0,2
	movdqa %xmm0,%xmm4
	punpckhbw %xmm2,%xmm0	# interleave second 16 new metrics
	punpcklbw %xmm2,%xmm4	# interleave first 16 new metrics
	movdqa %xmm0,(32*\GROUP+16)(%rdi)
	movdqa %xmm4,(32*\GROUP)(%rdi)

	# interleave decisions & store
	movdqa %xmm1,%xmm4
	punpckhbw %xmm3,%xmm1
	punpcklbw %xmm3,%xmm4
	# work around bug in gas due to Intel doc error
	.byte 0x66,0x0f,0xd7,0xd9	# pmovmskb %xmm1,%ebx
	shlq $16,%rbx
	.byte 0x66,0x0f,0xd7,0xc4	# pmovmskb %xmm4,%eax
	orq %rax,%rbx
	movq %rbx,(4*\GROUP)(%rdx)
	.endm

	# invoke macro 8 times for a total of 128 butterflies
	butterfly GROUP=0
	butterfly GROUP=1
	butterfly GROUP=2
	butterfly GROUP=3
	butterfly GROUP=4
	butterfly GROUP=5
	butterfly GROUP=6
	butterfly GROUP=7

	addq $32,%rdx		# bump decision pointer
		
	# see if we have to normalize
	movq (%rdi),%rax	# extract first output metric
	andq $255,%rax
	cmp $50,%rax		# is it greater than 50?
	movq $0,%rax
	jle done		# No, no need to normalize

	# Normalize by finding smallest metric and subtracting it
	# from all metrics
	movdqa (%rdi),%xmm0
	pminub 16(%rdi),%xmm0
	pminub 32(%rdi),%xmm0
	pminub 48(%rdi),%xmm0
	pminub 64(%rdi),%xmm0
	pminub 80(%rdi),%xmm0
	pminub 96(%rdi),%xmm0	
	pminub 112(%rdi),%xmm0	
	pminub 128(%rdi),%xmm0
	pminub 144(%rdi),%xmm0
	pminub 160(%rdi),%xmm0
	pminub 176(%rdi),%xmm0
	pminub 192(%rdi),%xmm0
	pminub 208(%rdi),%xmm0
	pminub 224(%rdi),%xmm0
	pminub 240(%rdi),%xmm0							

	# crunch down to single lowest metric
	movdqa %xmm0,%xmm1
	psrldq $8,%xmm0     # the count to psrldq is bytes, not bits!
	pminub %xmm1,%xmm0
	movdqa %xmm0,%xmm1
	psrlq $32,%xmm0
	pminub %xmm1,%xmm0
	movdqa %xmm0,%xmm1
	psrlq $16,%xmm0
	pminub %xmm1,%xmm0
	movdqa %xmm0,%xmm1
	psrlq $8,%xmm0
	pminub %xmm1,%xmm0

	punpcklbw %xmm0,%xmm0	# lowest 2 bytes
	pshuflw $0,%xmm0,%xmm0  # lowest 8 bytes
	punpcklqdq %xmm0,%xmm0	# all 16 bytes

	# xmm0 now contains lowest metric in all 16 bytes
	# subtract it from every output metric
	movdqa (%rdi),%xmm1
	psubusb %xmm0,%xmm1
	movdqa %xmm1,(%rdi)
	movdqa 16(%rdi),%xmm1
	psubusb %xmm0,%xmm1
	movdqa %xmm1,16(%rdi)	
	movdqa 32(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,32(%rdi)	
	movdqa 48(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,48(%rdi)	
	movdqa 64(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,64(%rdi)	
	movdqa 80(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,80(%rdi)	
	movdqa 96(%rdi),%xmm1	
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,96(%rdi)	
	movdqa 112(%rdi),%xmm1	
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,112(%rdi)	
	movdqa 128(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,128(%rdi)	
	movdqa 144(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,144(%rdi)	
	movdqa 160(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,160(%rdi)	
	movdqa 176(%rdi),%xmm1
	psubusb %xmm0,%xmm1
	movdqa %xmm1,176(%rdi)	
	movdqa 192(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,192(%rdi)	
	movdqa 208(%rdi),%xmm1
	psubusb %xmm0,%xmm1
	movdqa %xmm1,208(%rdi)	
	movdqa 224(%rdi),%xmm1
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,224(%rdi)	
	movdqa 240(%rdi),%xmm1							
	psubusb %xmm0,%xmm1	
	movdqa %xmm1,240(%rdi)	
	
done:		
	# swap metrics
	movq %rsi,%rax
	movq %rdi,%rsi
	movq %rax,%rdi
	jmp 1b
	
2:	movq 8(%rbp),%rbx	# ebx = vp
	# stash metric pointers
	movq %rsi,OLDMETRICS(%rbx)
	movq %rdi,NEWMETRICS(%rbx)
	movq %rdx,DP(%rbx)	# stash incremented value of vp->dp
	xorq %rax,%rax
err:	popq %rbx
	popq %rdx
	popq %rdi
	popq %rsi
	popq %rbp
	ret
	
	.data
	.align 16
thirtyones:	
	.byte 31,31,31,31,31,31,31,31,31,31,31,31,31,31,31,31

