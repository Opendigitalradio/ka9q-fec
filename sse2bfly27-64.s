/* Intel SIMD (SSE2) implementations of Viterbi ACS butterflies
   for 64-state (k=7) convolutional code
   Copyright 2003 Phil Karn, KA9Q
   This code may be used under the terms of the GNU Lesser General Public License (LGPL)

   Modifications for x86_64, 2012 Matthias P. Braendli, HB9EGM:
   - changed registers to x86-64 equivalents
   - changed instructions accordingly
   - %rip indirect addressing needed for position independent code,
     which is required because x86-64 needs dynamic libs to be PIC

   void update_viterbi27_blk_sse2(struct v27 *vp,unsigned char syms[],int nbits) ; 
*/
	# SSE2 (128-bit integer SIMD) version
    # All X86-64 CPUs include SSE2

	# These are offsets into struct v27, defined in viterbi27_av.c
	.set DP,128
	.set OLDMETRICS,132
	.set NEWMETRICS,136
	.text	
	.global update_viterbi27_blk_sse2,Branchtab27_sse2
	.type update_viterbi27_blk_sse2,@function
	.align 16
	
update_viterbi27_blk_sse2:
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
	pshuflw $0,%xmm6,%xmm6	# copy low word to low 3
	pshuflw $0,%xmm5,%xmm5
	punpcklqdq %xmm6,%xmm6  # propagate to all 16
	punpcklqdq %xmm5,%xmm5
	# xmm6 now contains first symbol in each byte, xmm5 the second

	movdqa thirtyones(%rip),%xmm7
	
	# each invocation of this macro does 16 butterflies in parallel
	.MACRO butterfly GROUP
	# compute branch metrics
	movdqa (Branchtab27_sse2+(16*\GROUP))(%rip),%xmm4
	movdqa (Branchtab27_sse2+32+(16*\GROUP))(%rip),%xmm3
	pxor %xmm6,%xmm4
	pxor %xmm5,%xmm3
	
	# compute 5-bit branch metric in xmm4 by adding the individual symbol metrics
	# This is okay for this
	# code because the worst-case metric spread (at high Eb/No) is only 120,
	# well within the range of our unsigned 8-bit path metrics, and even within
	# the range of signed 8-bit path metrics
	pavgb %xmm3,%xmm4
	psrlw $3,%xmm4

	pand %xmm7,%xmm4

	movdqa (16*\GROUP)(%esi),%xmm0	# Incoming path metric, high bit = 0
	movdqa ((16*\GROUP)+32)(%esi),%xmm3	# Incoming path metric, high bit = 1
	movdqa %xmm0,%xmm2
	movdqa %xmm3,%xmm1
	paddusb %xmm4,%xmm0	# note use of saturating arithmetic
	paddusb %xmm4,%xmm3	# this shouldn't be necessary, but why not?
	
	# negate branch metrics
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

	# invoke macro 2 times for a total of 32 butterflies
	butterfly GROUP=0
	butterfly GROUP=1

	addq $8,%rdx		# bump decision pointer
		
	# See if we have to normalize. This requires an explanation. We don't want
	# our path metrics to exceed 255 on the *next* iteration. Since the
	# largest branch metric is 30, that means we don't want any to exceed 225
	# on *this* iteration. Rather than look them all, we just pick an arbitrary one
	# (the first) and see if it exceeds 225-120=105, where 120 is the experimentally-
	# determined worst-case metric spread for this code and branch metrics in the range 0-30.
	
	# This is extremely conservative, and empirical testing at a variety of Eb/Nos might
	# show that a higher threshold could be used without affecting BER performance
	movq (%rdi),%rax	# extract first output metric
	andq $255,%rax
	cmp $105,%rax
	jle done		# No, no need to normalize

	# Normalize by finding smallest metric and subtracting it
	# from all metrics. We can't just pick an arbitrary small constant because
	# the minimum metric might be zero!
	movdqa (%rdi),%xmm0
	movdqa %xmm0,%xmm4	
	movdqa 16(%rdi),%xmm1
	pminub %xmm1,%xmm4
	movdqa 32(%rdi),%xmm2
	pminub %xmm2,%xmm4	
	movdqa 48(%rdi),%xmm3	
	pminub %xmm3,%xmm4

	# crunch down to single lowest metric
	movdqa %xmm4,%xmm5
	psrldq $8,%xmm5     # the count to psrldq is bytes, not bits!
	pminub %xmm5,%xmm4
	movdqa %xmm4,%xmm5
	psrlq $32,%xmm5
	pminub %xmm5,%xmm4
	movdqa %xmm4,%xmm5
	psrlq $16,%xmm5
	pminub %xmm5,%xmm4
	movdqa %xmm4,%xmm5
	psrlq $8,%xmm5
	pminub %xmm5,%xmm4	# now in lowest byte of %xmm4

	punpcklbw %xmm4,%xmm4	# lowest 2 bytes
	pshuflw $0,%xmm4,%xmm4  # lowest 8 bytes
	punpcklqdq %xmm4,%xmm4	# all 16 bytes
	
	# xmm4 now contains lowest metric in all 16 bytes
	# subtract it from every output metric
	psubusb %xmm4,%xmm0
	psubusb %xmm4,%xmm1
	psubusb %xmm4,%xmm2
	psubusb %xmm4,%xmm3	
	movdqa %xmm0,(%rdi)
	movdqa %xmm1,16(%rdi)	
	movdqa %xmm2,32(%rdi)	
	movdqa %xmm3,48(%rdi)	
	
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
